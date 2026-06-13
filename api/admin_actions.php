<?php
// FILE PATH: c:/Users/LENOVO/slfm_salesman_app/api/admin_actions.php
// MASTER ADMIN API V2: Handles Attendance & Salesman Full Management

date_default_timezone_set('Asia/Kolkata');

// Force Error Reporting for Debugging
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");

require 'db_connect.php';

$json_data = json_decode(file_get_contents('php://input'), true);

if (file_get_contents('php://input') && is_null($json_data)) {
    echo json_encode(["status" => "error", "message" => "Invalid JSON input"]);
    exit;
}

$action = $json_data['action'] ?? $_POST['action'] ?? '';

if ($action == 'ping') {
    echo json_encode(["status" => "success", "file" => "admin_actions.php", "path" => __FILE__]);
    exit;
}

// --- HELPER: Sync to Firebase RTDB for Real-time UI Refresh ---
function sendSyncSignal($sid)
{
    if (empty($sid))
        return;
    $rtdb_url = "https://admin-decd9-default-rtdb.asia-southeast1.firebasedatabase.app";
    $rtdb_secret = "y9O4hN0n1Od4HuPf8co9uaRT2t750HUOYnhTaJJ3";
    $sync_data = ['data_sync_timestamp' => (int) round(microtime(true) * 1000)];

    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $rtdb_url . "/salesmen_status/" . $sid . ".json?auth=" . $rtdb_secret);
    curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "PATCH");
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($sync_data));
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_exec($ch);
}

// --- HELPER: Generate Salesman ID (SM + 3 random digits) ---
function generateSalesmanID($conn)
{
    do {
        $rand = rand(100, 999);
        $new_id = "SM" . $rand;
        $check = $conn->query("SELECT id FROM salesmen WHERE salesman_id = '$new_id'");
    } while ($check->num_rows > 0);
    return $new_id;
}

// --- 1. GET ALL SALESMEN (With Filters) ---
if ($action == 'get_salesmen_list') {
    $showroom = $json_data['showroom'] ?? '';
    $role = $json_data['role'] ?? '';
    $gender = $json_data['gender'] ?? '';

    $where = [];
    if (!empty($showroom))
        $where[] = "showroom_name = '" . $conn->real_escape_string($showroom) . "'";
    if (!empty($role))
        $where[] = "role = '" . $conn->real_escape_string($role) . "'";
    if (!empty($gender))
        $where[] = "gender = '" . $conn->real_escape_string($gender) . "'";

    $where_sql = !empty($where) ? " WHERE " . implode(" AND ", $where) : "";
    $sql = "SELECT * FROM salesmen $where_sql ORDER BY name ASC";

    $result = $conn->query($sql);
    $data = [];
    if ($result) {
        while ($row = $result->fetch_assoc()) {
            $data[] = $row;
        }
        echo json_encode(["status" => "success", "data" => $data]);
    } else {
        echo json_encode(["status" => "error", "message" => "SQL Error: " . $conn->error]);
    }
}

// --- 2. ADD SALESMAN (SINGLE & BULK) ---
elseif ($action == 'add_salesman') {
    $users = $json_data['users'] ?? [];
    if (isset($json_data['name'])) {
        $users = [$json_data];
    }

    if (empty($users)) {
        echo json_encode(["status" => "error", "message" => "No user data received"]);
        exit;
    }

    $added_count = 0;
    $details = [];

    foreach ($users as $user) {
        $name = $conn->real_escape_string($user['name'] ?? '');
        $phone = $conn->real_escape_string($user['phone'] ?? '');
        $showroom_raw = trim($user['showroom_name'] ?? 'Main Branch');
        // 🔥 FIX: Normalize showroom_name to canonical form from DB
        $safe_lookup = $conn->real_escape_string(strtolower($showroom_raw));
        $canon_sql = "SELECT showroom_name FROM salesmen 
                      WHERE LOWER(TRIM(showroom_name)) = '$safe_lookup' 
                      ORDER BY id ASC LIMIT 1";
        $canon_res = $conn->query($canon_sql);
        if ($canon_res && $canon_res->num_rows > 0) {
            $showroom_raw = $canon_res->fetch_assoc()['showroom_name'];
        }
        $showroom = $conn->real_escape_string($showroom_raw);
        $role = $conn->real_escape_string($user['role'] ?? 'salesman');
        $gender = $conn->real_escape_string($user['gender'] ?? 'Male');
        $pass = $conn->real_escape_string($user['password'] ?? '123456');
        $password = $pass; // Storing as plain text per user request
        $address = $conn->real_escape_string($user['showroom_address'] ?? 'mannargudi');

        $sid = generateSalesmanID($conn);
        $sql = "INSERT INTO salesmen (salesman_id, name, phone, showroom_name, showroom_address, gender, password_hash, role) 
                VALUES ('$sid', '$name', '$phone', '$showroom', '$address', '$gender', '$password', '$role')";

        if ($conn->query($sql) === TRUE) {
            $added_count++;
            $details[] = [
                "name" => $name, 
                "salesman_id" => $sid, 
                "password" => $pass,
                "status" => "Added"
            ];
        } else {
            $details[] = ["name" => $name, "status" => "Failed: " . $conn->error];
        }
    }
    echo json_encode(["status" => "success", "total_added" => $added_count, "details" => $details]);
}

// --- 3. THE MASTER ALTER FEATURE (Salesman Table) ---
elseif ($action == 'alter_salesman') {
    $sid = $conn->real_escape_string($json_data['salesman_id'] ?? '');
    if (empty($sid)) {
        echo json_encode(["status" => "error", "message" => "Salesman ID Required"]);
        exit;
    }

    $fields = [];
    $allowed_fields = [
        'name',
        'phone',
        'role',
        'gender',
        'showroom_name',
        'showroom_address',
        'status',
        'relieving_date',
        'shift_start_time',
        'shift_end_time',
        'custom_late_cutoff',
        'allow_late_entry',
        'half_day_start',
        'half_day_end',
        'is_device_locked',
        'remote_attendance_enabled',
        'primary_device_id'
    ];

    foreach ($allowed_fields as $field) {
        if (array_key_exists($field, $json_data)) {
            $val = $json_data[$field];

            // 🔥 FIX: Normalize showroom_name to the CANONICAL form from DB
            // This prevents duplicates like 'office' vs 'Office' when admin saves via dropdown
            if ($field === 'showroom_name' && !is_null($val) && $val !== '') {
                $safe_lookup = $conn->real_escape_string(strtolower(trim($val)));
                $canon_sql = "SELECT showroom_name FROM salesmen 
                              WHERE LOWER(TRIM(showroom_name)) = '$safe_lookup' 
                              ORDER BY id ASC LIMIT 1";
                $canon_res = $conn->query($canon_sql);
                if ($canon_res && $canon_res->num_rows > 0) {
                    $val = $canon_res->fetch_assoc()['showroom_name'];
                }
            }

            if (is_null($val) || $val === "" || $val === "00:00:00") {
                $fields[] = "$field = NULL";
            } else {
                $safe_val = $conn->real_escape_string($val);
                $fields[] = "$field = '$safe_val'";
            }
        }
    }

    // 🔥 AUTOMATIC RELIEVING DATE: If status is Suspended, set date. If Active, clear it.
    if (isset($json_data['status'])) {
        $new_status = $json_data['status'];
        if ($new_status === 'Suspended') {
            $today = date('Y-m-d');
            // Only set if not explicitly provided in the request
            if (!isset($json_data['relieving_date']) || empty($json_data['relieving_date'])) {
                $fields[] = "relieving_date = '$today'";
            }
        } elseif ($new_status === 'Active') {
            $fields[] = "relieving_date = NULL";
        }
    }

    if (isset($json_data['password']) && !empty($json_data['password'])) {
        $pass = $conn->real_escape_string($json_data['password']);
        $fields[] = "password_hash = '$pass'";
    }

    if (empty($fields)) {
        echo json_encode(["status" => "error", "message" => "No changes provided"]);
        exit;
    }

    $sql = "UPDATE salesmen SET " . implode(", ", $fields) . " WHERE salesman_id = '$sid'";
    if ($conn->query($sql) === TRUE) {
        // 🔥 SYNC TO FIREBASE RTDB (Real-time UI Push)
        $sync_data = [];
        if (isset($json_data['status']))
            $sync_data['status'] = $json_data['status'];
        if (isset($json_data['remote_attendance_enabled']))
            $sync_data['remote_attendance_enabled'] = (int) $json_data['remote_attendance_enabled'];
        if (isset($json_data['is_device_locked']))
            $sync_data['is_device_locked'] = (int) $json_data['is_device_locked'];
        if (isset($json_data['allow_late_entry']))
            $sync_data['allow_late_entry'] = (int) $json_data['allow_late_entry'];

        // Always add sync signal for other field changes (like showroom name, shift times etc)
        $sync_data['data_sync_timestamp'] = round(microtime(true) * 1000);

        if (!empty($sync_data)) {
            $rtdb_url = "https://admin-decd9-default-rtdb.asia-southeast1.firebasedatabase.app";
            $rtdb_secret = "y9O4hN0n1Od4HuPf8co9uaRT2t750HUOYnhTaJJ3";
            $ch = curl_init();
            curl_setopt($ch, CURLOPT_URL, $rtdb_url . "/salesmen_status/" . $sid . ".json?auth=" . $rtdb_secret);
            curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "PATCH");
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($sync_data));
            curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_exec($ch);
        }
        echo json_encode(["status" => "success", "message" => "Salesman Profile Updated Successfully"]);
    } else {
        echo json_encode(["status" => "error", "message" => "Update Failed: " . $conn->error]);
    }
}

// --- 4. ATTENDANCE LOGS & ALTER ---
elseif ($action == 'search_attendance') {
    $date_start = $json_data['date_start'] ?? date('Y-m-d');
    $date_end = $json_data['date_end'] ?? date('Y-m-d');
    $salesman_id = $json_data['salesman_id'] ?? '';
    $gender = $json_data['gender'] ?? '';
    $role = $json_data['role'] ?? '';
    $showroom_name = $json_data['showroom_name'] ?? '';
    $status_filter = $json_data['status_filter'] ?? '';

    $where = "WHERE a.date BETWEEN '$date_start' AND '$date_end'";
    if (!empty($salesman_id)) {
        $where .= " AND a.salesman_id = '$salesman_id'";
    }
    if (!empty($gender)) {
        $where .= " AND s.gender = '$gender'";
    }
    if (!empty($role)) {
        $where .= " AND s.role = '$role'";
    }
    if (!empty($showroom_name)) {
        $where .= " AND a.showroom_name = '$showroom_name'";
    }

    if ($status_filter === 'Late') {
        $where .= " AND a.is_late = 1";
    } elseif ($status_filter === 'Present') {
        $where .= " AND a.status = 'Present'";
    } elseif ($status_filter === 'Half Day') {
        $where .= " AND a.status = 'Half Day'";
    } elseif ($status_filter === 'Leave') {
        $where .= " AND a.status = 'Leave'";
    } elseif ($status_filter === 'Absent') {
        $where .= " AND a.status = 'Absent'";
    } elseif ($status_filter === 'Missing Out') {
        $where .= " AND (a.clock_out_time IS NULL OR a.clock_out_time = '') AND a.clock_in_time IS NOT NULL";
    }

    $sql = "SELECT a.*, s.role, s.gender, s.phone 
            FROM attendance a 
            LEFT JOIN salesmen s ON a.salesman_id = s.salesman_id 
            $where 
            ORDER BY a.date DESC, a.clock_in_time DESC";
    $result = $conn->query($sql);
    $data = [];

    // Base URL for images
    $protocol = isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? "https" : "http";
    $host = $_SERVER['HTTP_HOST'];
    $script_dir = dirname($_SERVER['PHP_SELF']);
    $script_dir = str_replace('\\', '/', trim($script_dir, '/\\'));
    $base_url = "$protocol://$host/";
    // Hostinger Fix: Ensure images point to the /api/uploads folder
    if (strpos($script_dir, 'api') !== false) {
        $base_url .= "api/";
    } else {
        $base_url .= $script_dir . "/";
    }

    if ($result) {
        while ($row = $result->fetch_assoc()) {
            $img_fields = ['selfie_url', 'clock_out_selfie_url', 'reentry_selfie_url', 'final_out_selfie_url'];
            foreach ($img_fields as $f) {
                if (!empty($row[$f]))
                    $row[$f] = $base_url . $row[$f];
            }
            $data[] = $row;
        }
        echo json_encode(["status" => "success", "data" => $data]);
    } else {
        echo json_encode(["status" => "error", "message" => "Query Failed: " . $conn->error]);
    }
} elseif ($action == 'alter_attendance') {
    $id = $json_data['id'] ?? '';
    if (empty($id)) {
        echo json_encode(["status" => "error", "message" => "Record ID Required"]);
        exit;
    }

    $fields_to_update = [];
    $allowed_fields = [
        'status',
        'clock_in_time',
        'clock_out_time',
        'admin_approval',
        'is_late',
        'late_entry_approved',
        'modified_by',
        'modification_reason',
        'latitude',
        'longitude',
        'out_latitude',
        'out_longitude',
        'is_proxy_device',
        'location_distance',
        'is_out_of_location',
        'resume_count',
        'selfie_url',
        'clock_out_selfie_url',
        'reentry_selfie_url',
        'final_out_selfie_url',
        'device_id_used',
        'device_model_used',
        'updated_at'
    ];

    foreach ($allowed_fields as $field) {
        if (array_key_exists($field, $json_data)) {
            $val = $json_data[$field];
            if (is_null($val) || $val === "" || $val === "00:00:00") {
                $fields_to_update[] = "$field = NULL";

                // 🔥 FIX: Admin clock_out delete pannumbothu, re-entry fields um auto-clear
                // Ithunala Flutter sync logic local DB messages ah correct ah cleanup pannum
                if ($field === 'clock_out_time') {
                    $fields_to_update[] = "resume_count = 0";
                    $fields_to_update[] = "reentry_selfie_url = NULL";
                    $fields_to_update[] = "final_out_selfie_url = NULL";
                    $fields_to_update[] = "clock_out_selfie_url = NULL";
                }
            } else {
                $safe_val = $conn->real_escape_string($val);
                $fields_to_update[] = "$field = '$safe_val'";
            }
        }
    }

    $sql = "UPDATE attendance SET " . implode(", ", $fields_to_update) . " WHERE id = '$id'";
    if ($conn->query($sql) === TRUE) {
        // 🔥 Real-time Sync Trigger: Fetch salesman_id for this record
        $getSid = $conn->query("SELECT salesman_id FROM attendance WHERE id = '$id'");
        if ($sRow = $getSid->fetch_assoc()) {
            $sid = $sRow['salesman_id'];
            // 🚀 Logic Fix: Trigger performance summary update after admin edit
            $protocol = isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? "https" : "http";
            $perf_url = "$protocol://" . $_SERVER['HTTP_HOST'] . dirname($_SERVER['PHP_SELF']) . "/update_salesman_summary.php";
            $perf_data = json_encode(['salesman_id' => $sid]);
            $opts = ['http' => ['header' => "Content-type: application/json\r\n", 'method' => 'POST', 'content' => $perf_data, 'timeout' => 1]];
            @file_get_contents($perf_url, false, stream_context_create($opts));

            sendSyncSignal($sid);
        }
        echo json_encode(["status" => "success", "message" => "Attendance Record Updated"]);
    } else {
        echo json_encode(["status" => "error", "message" => "Update Failed: " . $conn->error]);
    }
}

// --- 5. DASHBOARD STATS & ADVANCED APPROVALS ---
elseif ($action == 'get_pending_attendance') {
    require_once 'billing_counter/get_pending_attendance.php';
    exit;
} elseif ($action == 'approve_attendance') {
    require_once 'billing_counter/approve_attendance.php';
    exit;
} elseif ($action == 'get_dashboard_stats') {
    $today = date('Y-m-d');
    $sevenDaysAgo = date('Y-m-d', strtotime('-7 days'));

    // 1. Total Salesmen (Active/Non-Suspended)
    $res = $conn->query("SELECT COUNT(*) as total FROM salesmen WHERE status != 'Suspended'");
    $total_salesmen = $res->fetch_assoc()['total'] ?? 0;

    // 2. Today's Attendance Breakdowns
    $stats = [
        'total' => $total_salesmen,
        'present' => 0,
        'late' => 0,
        'half_day' => 0,
        'absent' => 0,
        'leave_today' => 0,
        'pending_approval' => 0,
        'no_out_time' => 0
    ];

    // 4. Detailed Statuses from Attendance Table (Today)
    $res = $conn->query("SELECT status, is_late FROM attendance WHERE date = '$today'");
    $attendance_count = 0;
    while ($row = $res->fetch_assoc()) {
        $attendance_count++;
        $status = $row['status'];
        if ($status === 'Present')
            $stats['present']++;
        if ($status === 'Absent')
            $stats['absent']++;
        if ($status === 'Half Day')
            $stats['half_day']++;
        if ($status === 'Leave')
            $stats['leave_today']++;
        if ($row['is_late'] == 1)
            $stats['late']++;
    }

    // 🔥 SYNC: Calculate Pending Approvals (Last 7 Days - Matching get_pending_attendance.php)
    $showroom_sql = !empty($showroom) ? " AND s.showroom_name = '$showroom' " : "";

    $res_pending = $conn->query("
        SELECT a.admin_approval, a.clock_out_time, s.gender, a.is_out_of_location 
        FROM attendance a 
        JOIN salesmen s ON a.salesman_id = s.salesman_id 
        WHERE a.date BETWEEN '$sevenDaysAgo' AND '$today'
          AND a.clock_out_time IS NOT NULL
          $showroom_sql
    ");

    while ($p_row = $res_pending->fetch_assoc()) {
        $adminAppr = $p_row['admin_approval'] ?? '';
        $is_already_actioned = (!empty($adminAppr) && $adminAppr !== 'Pending');

        // 🔥 SYNC: EXACT matching logic from get_pending_attendance.php
        $clockOutTs = strtotime($p_row['clock_out_time']);
        $hour = (int) date('H', $clockOutTs);
        $gender = strtolower($p_row['gender'] ?? 'male');

        // Rules: Female max 8 PM (20), Male max 9 PM (21)
        $maxHour = ($gender === 'female') ? 20 : 21;

        $timeStr = date('H:i', $clockOutTs);
        $is_early_out = ($timeStr >= '19:30' && $hour < $maxHour);
        $is_out_of_loc_pending = ($p_row['is_out_of_location'] == 1 && ($adminAppr === 'Pending' || empty($adminAppr)));

        // Count if it triggers the approval rules
        if ($is_early_out || $is_out_of_loc_pending) {
            $stats['pending_approval']++;
        }
    }

    // 5. PAST "Missing Out" Records (Current Month ONLY - Exclude Today)
    $res_missed = $conn->query("
        SELECT COUNT(*) as total 
        FROM attendance a
        JOIN salesmen s ON a.salesman_id = s.salesman_id
        WHERE a.date >= DATE_FORMAT(CURRENT_DATE, '%Y-%m-01') 
          AND a.date < '$today' 
          AND (a.clock_out_time IS NULL OR a.clock_out_time = '') 
          AND (a.clock_in_time IS NOT NULL AND a.clock_in_time != '')
          $showroom_sql
    ");
    $stats['no_out_time'] = $res_missed->fetch_assoc()['total'] ?? 0;

    // Default Absent logic: If no specific 'Absent' records exist, fallback to calculation vs active staff
    if ($stats['absent'] === 0) {
        $stats['absent'] = max(0, $total_salesmen - $attendance_count);
    }

    // 3. Pending Leave Requests (All time pending)
    $res = $conn->query("SELECT COUNT(*) as total FROM leave_requests WHERE status = 'Pending'");
    $stats['pending_leaves'] = $res->fetch_assoc()['total'] ?? 0;

    echo json_encode(["status" => "success", "data" => $stats]);
} elseif ($action == 'approve_attendance_action') {
    $attendance_id = $json_data['attendance_id'] ?? '';
    $sub_action = $json_data['sub_action'] ?? ''; // approve, reject, undo
    $approver_id = 'ADMIN'; // Default for dashboard actions
    $approver_id = $json_data['approver_id'] ?? 'ADMIN';

    if (empty($attendance_id)) {
        echo json_encode(["status" => "error", "message" => "Attendance ID is required"]);
        exit;
    }

    // Step 1: Fetch Data
    $checkStmt = $conn->prepare("
        SELECT a.clock_in_time, a.clock_out_time, a.status, a.is_out_of_location, s.gender, s.salesman_id, s.custom_late_cutoff 
        FROM attendance a 
        JOIN salesmen s ON a.salesman_id = s.salesman_id 
        WHERE a.id = ?
    ");
    $checkStmt->bind_param("i", $attendance_id);
    $checkStmt->execute();
    $result = $checkStmt->get_result();

    if ($row = $result->fetch_assoc()) {
        $clockInTime = strtotime($row['clock_in_time']);
        $dateStr = date('Y-m-d', $clockInTime);
        $gender = strtolower($row['gender'] ?? 'male');
        $custom_cutoff = $row['custom_late_cutoff'];
        $is_out_of_loc = $row['is_out_of_location'] ?? 0;

        // Thresholds
        $late_cutoff_str = !empty($custom_cutoff) ? date('H:i:s', strtotime($custom_cutoff) + 59) : "10:00:59";
        $late_cutoff = strtotime("$dateStr $late_cutoff_str");
        $leave_cutoff = strtotime("$dateStr 15:00:59");

        // Base Status Logic
        $baseStatus = 'Present';
        if ($clockInTime > $leave_cutoff)
            $baseStatus = 'Leave';
        elseif ($clockInTime > $late_cutoff)
            $baseStatus = 'Half Day';

        $finalStatus = $row['status'];
        $adminApprovalText = $row['admin_approval'];

        if ($sub_action === 'approve') {
            $finalStatus = $baseStatus;
            $adminApprovalText = 'Approved';
        } elseif ($sub_action === 'reject') {
            $adminApprovalText = 'Rejected';
            if ($baseStatus === 'Present')
                $finalStatus = 'Half Day';
            else
                $finalStatus = 'Leave';
        } elseif ($sub_action === 'undo') {
            $adminApprovalText = ($is_out_of_loc == 1) ? 'Pending' : null;
            $finalStatus = $baseStatus;
            // Handle out-time if exists
            if (!empty($row['clock_out_time'])) {
                $out_time = strtotime($row['clock_out_time']);
                $exit_cutoff = ($gender == 'female') ? strtotime("$dateStr 20:00:00") : strtotime("$dateStr 21:00:00");
                if ($out_time < strtotime("$dateStr 14:30:00"))
                    $finalStatus = 'Leave';
                elseif ($out_time < $exit_cutoff)
                    $finalStatus = ($baseStatus == 'Half Day') ? 'Leave' : 'Half Day';
            }
        }

        $updateStmt = $conn->prepare("UPDATE attendance SET status = ?, admin_approval = ?, modified_by = ? WHERE id = ?");
        $updateStmt->bind_param("sssi", $finalStatus, $adminApprovalText, $approver_id, $attendance_id);

        if ($updateStmt->execute()) {
            sendSyncSignal($row['salesman_id']); // Trigger app refresh
            echo json_encode(["status" => "success", "message" => "Updated to $finalStatus ($adminApprovalText)", "new_status" => $finalStatus]);
        } else {
            echo json_encode(["status" => "error", "message" => "DB Update Failed"]);
        }
    } else {
        echo json_encode(["status" => "error", "message" => "Record not found"]);
    }
}

// --- 5. LEAVE MANAGEMENT ---
elseif ($action == 'get_pending_leaves') {
    // 🔥 FIX: Return ALL leaves for current + previous month (not just Pending)
    $first_day_prev_month = date('Y-m-01', strtotime('first day of last month'));
    $sql = "SELECT l.*, s.name as salesman_name, s.showroom_name 
            FROM leave_requests l 
            JOIN salesmen s ON l.salesman_id = s.salesman_id 
            WHERE l.leave_date >= '$first_day_prev_month'
            ORDER BY l.leave_date DESC, l.created_at DESC";
    $result = $conn->query($sql);
    $data = [];
    if ($result) {
        while ($row = $result->fetch_assoc()) {
            $data[] = $row;
        }
        echo json_encode(["status" => "success", "data" => $data]);
    } else {
        echo json_encode(["status" => "error", "message" => "Query Failed: " . $conn->error]);
    }
} elseif ($action == 'update_leave_status') {
    $id = $json_data['id'] ?? '';
    $status = $json_data['status'] ?? ''; // Approved or Rejected

    if (empty($id) || empty($status)) {
        echo json_encode(["status" => "error", "message" => "ID and Status required"]);
        exit;
    }

    $sql = "UPDATE leave_requests SET status = ? WHERE id = ?";
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("si", $status, $id);

    if ($stmt->execute()) {
        // 🆔 Get salesman_id for this leave request for sync signal
        $getSid = $conn->query("SELECT salesman_id FROM leave_requests WHERE id = '$id'");
        if ($lRow = $getSid->fetch_assoc()) {
            sendSyncSignal($lRow['salesman_id']);
        }
        echo json_encode(["status" => "success", "message" => "Leave Request $status"]);
    } else {
        echo json_encode(["status" => "error", "message" => "Update Failed: " . $conn->error]);
    }
} elseif ($action == 'delete_leave') {
    $id = $json_data['id'] ?? '';
    // Optional: Pass salesman_id to force sync even if row is gone
    $sid = $json_data['salesman_id'] ?? '';

    if (empty($id)) {
        echo json_encode(["status" => "error", "message" => "ID required"]);
        exit;
    }

    // 🆔 Try to find salesman_id if not provided
    if (empty($sid)) {
        $getSid = $conn->query("SELECT salesman_id FROM leave_requests WHERE id = '$id'");
        if ($lRow = $getSid->fetch_assoc()) {
            $sid = $lRow['salesman_id'];
        }
    }

    $sql = "DELETE FROM leave_requests WHERE id = ?";
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("i", $id);

    if ($stmt->execute()) {
        $affected = $stmt->affected_rows;
        if (!empty($sid)) {
            sendSyncSignal($sid);
        }

        if ($affected > 0) {
            echo json_encode(["status" => "success", "message" => "Leave Request Deleted Successfully"]);
        } else {
            // If already gone, still return success to allow UI to clear
            echo json_encode(["status" => "success", "message" => "Record already removed. Sync signal sent.", "warning" => "Record not found"]);
        }
    } else {
        echo json_encode(["status" => "error", "message" => "Delete Failed: " . $conn->error]);
    }
} elseif ($action == 'delete_salesman') {
    $sid = $json_data['salesman_id'] ?? '';
    if (empty($sid)) {
        echo json_encode(["status" => "error", "message" => "Salesman ID Required"]);
        exit;
    }

    // 🔥 Safety: Also clear from RTDB if possible
    sendSyncSignal($sid);

    $sql = "DELETE FROM salesmen WHERE salesman_id = ?";
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("s", $sid);

    if ($stmt->execute()) {
        echo json_encode(["status" => "success", "message" => "Salesman $sid Deleted Successfully"]);
    } else {
        echo json_encode(["status" => "error", "message" => "Delete Failed: " . $conn->error]);
    }
} elseif ($action == 'delete_attendance') {
    $id = $json_data['id'] ?? '';
    $sid = $json_data['salesman_id'] ?? '';

    if (empty($id)) {
        echo json_encode(["status" => "error", "message" => "Record ID Required"]);
        exit;
    }

    $sql = "DELETE FROM attendance WHERE id = ?";
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("i", $id);

    if ($stmt->execute()) {
        if (!empty($sid)) sendSyncSignal($sid);
        echo json_encode(["status" => "success", "message" => "Attendance Record Deleted"]);
    } else {
        echo json_encode(["status" => "error", "message" => "Delete Failed: " . $conn->error]);
    }
}

// --- 6. FEATURE CONTROLS (SHOWROOM SPECIFIC) ---
elseif ($action == 'get_feature_controls') {
    $showroom = trim($json_data['showroom_name'] ?? 'All Showrooms');
    $showroom_lower = strtolower($showroom);
    
    // We use LOWER() and TRIM() to ensure we find the records regardless of how they were saved
    $sql = "SELECT feature_name, is_active, showroom_name FROM feature_control 
            WHERE LOWER(TRIM(showroom_name)) = '$showroom_lower' 
            OR showroom_name = 'All Showrooms' 
            ORDER BY (showroom_name = 'All Showrooms') DESC";
            
    $result = $conn->query($sql);
    $data = [];
    if ($result) {
        while ($row = $result->fetch_assoc()) {
            // Priority logic: The loop preserves the order from the query.
            // With ORDER BY DESC, 'All Showrooms' comes first, then Specific showroom.
            // So the specific showroom correctly overrides 'All Showrooms'.
            $data[$row['feature_name']] = $row;
        }
        echo json_encode(["status" => "success", "data" => $data]);
    } else {
        echo json_encode(["status" => "error", "message" => "SQL Error: " . $conn->error]);
    }
} elseif ($action == 'update_feature_control') {
    $feature = trim($json_data['feature_name'] ?? '');
    $showroom = trim($json_data['showroom_name'] ?? 'All Showrooms');
    $is_active = (int) ($json_data['is_active'] ?? 1);

    if (empty($feature)) {
        echo json_encode(["status" => "error", "message" => "Feature Name Required"]);
        exit;
    }
    
    $safe_feature = $conn->real_escape_string($feature);
    $safe_showroom = $conn->real_escape_string($showroom);

    $sql = "INSERT INTO feature_control (feature_name, showroom_name, is_active) 
            VALUES ('$safe_feature', '$safe_showroom', $is_active) 
            ON DUPLICATE KEY UPDATE is_active=$is_active";

    if ($conn->query($sql)) {
        // 🔥 SYNC TO FIREBASE RTDB (Real-time Feature Push)
        // 🔥 CRITICAL FIX: Distributed App uses .toLowerCase() on showroom name.
        // We must sync to lowercase paths in Firebase so the app can find them.
        $fb_showroom = strtolower($showroom); 
        
        $rtdb_url = "https://admin-decd9-default-rtdb.asia-southeast1.firebasedatabase.app";
        $rtdb_secret = "y9O4hN0n1Od4HuPf8co9uaRT2t750HUOYnhTaJJ3";
        $fb_url = $rtdb_url . "/features/" . rawurlencode($fb_showroom) . "/" . $feature . ".json?auth=" . $rtdb_secret;

        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $fb_url);
        curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "PUT");
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($is_active == 1)); // Sync as boolean
        curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_exec($ch);

        echo json_encode(["status" => "success", "message" => "Feature Updated & Synced to $fb_showroom"]);
    } else {
        echo json_encode(["status" => "error", "message" => "SQL Error: " . $conn->error]);
    }
}

// --- 7. GET DYNAMIC METADATA (ROLES & SHOWROOMS) ---
elseif ($action == 'get_metadata') {
    // 1. Get Unique Roles from existing data
    $roles = [];
    $res = $conn->query("SELECT DISTINCT role FROM salesmen WHERE role IS NOT NULL AND role != '' ORDER BY role ASC");
    if ($res) {
        while ($row = $res->fetch_assoc()) {
            $roles[] = $row['role'];
        }
    }
    if (empty($roles)) {
        $roles = ['salesman', 'manager', 'supervisor', 'admin'];
    }

    // 2. Showroom List Logic (STRICTLY FROM DATABASE — CANONICAL NAMES ONLY)
    // 🔥 FIX: GROUP BY LOWER(TRIM()) to deduplicate case variants like 'office' vs 'Office'.
    // Picks the showroom_name from the EARLIEST record (MIN(id)) as the canonical form.
    $showrooms = [];
    $rooms_sql = "SELECT s.showroom_name 
                  FROM salesmen s
                  INNER JOIN (
                      SELECT MIN(id) as first_id 
                      FROM salesmen 
                      WHERE showroom_name IS NOT NULL AND TRIM(showroom_name) != '' 
                      GROUP BY LOWER(TRIM(showroom_name))
                  ) canon ON s.id = canon.first_id
                  ORDER BY s.showroom_name ASC";
    $res_rooms = $conn->query($rooms_sql);
    if ($res_rooms) {
        while ($row = $res_rooms->fetch_assoc()) {
            $room_name = trim($row['showroom_name']);
            if (!empty($room_name)) {
                $showrooms[] = $room_name;
            }
        }
    }

    echo json_encode(["status" => "success", "roles" => $roles, "showrooms" => $showrooms]);
} 

// --- 8. VERSION MANAGEMENT (SALESMAN APP) ---
elseif ($action == 'get_version_config') {
    $version_file = __DIR__ . '/apps/salesman/salesman_version.json';
    if (file_exists($version_file)) {
        $config = json_decode(file_get_contents($version_file), true);
        echo json_encode(["status" => "success", "data" => $config]);
    } else {
        echo json_encode(["status" => "error", "message" => "Version file not found"]);
    }
} elseif ($action == 'list_apks') {
    $dir = 'apps/salesman/';
    $files = [];
    if (is_dir($dir)) {
        $all_files = scandir($dir);
        foreach ($all_files as $file) {
            if (pathinfo($file, PATHINFO_EXTENSION) === 'apk') {
                $files[] = $file;
            }
        }
    }
    echo json_encode(["status" => "success", "data" => array_reverse($files)]);
} elseif ($action == 'update_version_config') {
    $version_file = __DIR__ . '/apps/salesman/salesman_version.json';
    
    // Validate required fields
    if (!isset($json_data['version']) || !isset($json_data['build_number'])) {
        echo json_encode(["status" => "error", "message" => "Missing version or build_number"]);
        exit;
    }

    $new_config = [
        "version" => $json_data['version'],
        "build_number" => (int)$json_data['build_number'],
        "mandatory" => ($json_data['mandatory'] === true || $json_data['mandatory'] === 'true' || $json_data['mandatory'] == 1),
        "is_global" => ($json_data['is_global'] === true || $json_data['is_global'] === 'true' || $json_data['is_global'] == 1),
        "message" => $json_data['message'] ?? "Bug fixes and performance improvements.",
        "download_url" => $json_data['download_url'] ?? "https://skyblue-raven-196549.hostingersite.com/api/apps/salesman/app-release.apk",
        "target_showrooms" => $json_data['target_showrooms'] ?? [] // Array of showroom names
    ];

    if (file_put_contents($version_file, json_encode($new_config, JSON_PRETTY_PRINT))) {
        echo json_encode(["status" => "success", "message" => "Version Configuration Updated Successfully"]);
    } else {
        echo json_encode(["status" => "error", "message" => "Failed to write version file"]);
    }
} 
// --- 9. ANNOUNCEMENT SYNC (MYSQL PERSISTENCE) ---
elseif ($action == 'save_announcement') {
    // Ensure table exists
    $conn->query("CREATE TABLE IF NOT EXISTS `announcements` (
        `id` int(11) NOT NULL AUTO_INCREMENT,
        `announcement_id` varchar(255) NOT NULL,
        `message` text NOT NULL,
        `target` varchar(255) NOT NULL,
        `sender_id` varchar(255) DEFAULT NULL,
        `timestamp` bigint(20) NOT NULL,
        `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
        PRIMARY KEY (`id`),
        UNIQUE KEY `announcement_id` (`announcement_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $ann_id = $conn->real_escape_string($json_data['announcement_id'] ?? '');
    $message = $conn->real_escape_string($json_data['message'] ?? '');
    $target = $conn->real_escape_string($json_data['target'] ?? 'global');
    $sender = $conn->real_escape_string($json_data['sender_id'] ?? 'Admin');
    $ts = $json_data['timestamp'] ?? round(microtime(true) * 1000);

    if (empty($ann_id) || empty($message)) {
        echo json_encode(["status" => "error", "message" => "Missing data"]);
        exit;
    }

    $sql = "INSERT INTO announcements (announcement_id, message, target, sender_id, timestamp) 
            VALUES ('$ann_id', '$message', '$target', '$sender', $ts)
            ON DUPLICATE KEY UPDATE message='$message', target='$target', sender_id='$sender', timestamp=$ts";

    if ($conn->query($sql) === TRUE) {
        echo json_encode(["status" => "success", "message" => "Announcement saved to MySQL"]);
    } else {
        echo json_encode(["status" => "error", "message" => "MySQL Error: " . $conn->error]);
    }
} elseif ($action == 'delete_announcement') {
    $ann_id = $conn->real_escape_string($json_data['announcement_id'] ?? '');
    if (empty($ann_id)) {
        echo json_encode(["status" => "error", "message" => "ID required"]);
        exit;
    }
    $sql = "DELETE FROM announcements WHERE announcement_id = '$ann_id'";
    if ($conn->query($sql) === TRUE) {
        echo json_encode(["status" => "success", "message" => "Announcement deleted from MySQL"]);
    } else {
        echo json_encode(["status" => "error", "message" => "MySQL Error: " . $conn->error]);
    }
}
// --- 10. NORMALIZE SHOWROOM NAMES (One-time cleanup) ---
elseif ($action == 'normalize_showrooms') {
    // 🔥 Finds the canonical (earliest) showroom_name for each case-insensitive group
    // and updates all variant records to use the canonical form.
    $canon_sql = "SELECT MIN(id) as first_id, LOWER(TRIM(showroom_name)) as normalized
                  FROM salesmen 
                  WHERE showroom_name IS NOT NULL AND TRIM(showroom_name) != ''
                  GROUP BY LOWER(TRIM(showroom_name))";
    $canon_res = $conn->query($canon_sql);
    
    $fixed = 0;
    $details = [];
    
    if ($canon_res) {
        while ($row = $canon_res->fetch_assoc()) {
            $first_id = (int)$row['first_id'];
            $normalized = $conn->real_escape_string($row['normalized']);
            
            // Get the canonical name from the earliest record
            $name_res = $conn->query("SELECT showroom_name FROM salesmen WHERE id = $first_id");
            if ($name_res && $name_res->num_rows > 0) {
                $canonical = $name_res->fetch_assoc()['showroom_name'];
                $safe_canonical = $conn->real_escape_string($canonical);
                
                // Update all records with same name (case-insensitive) to use canonical form
                $update_sql = "UPDATE salesmen SET showroom_name = '$safe_canonical' 
                               WHERE LOWER(TRIM(showroom_name)) = '$normalized' 
                               AND showroom_name != '$safe_canonical'";
                $conn->query($update_sql);
                $affected = $conn->affected_rows;
                
                if ($affected > 0) {
                    $fixed += $affected;
                    $details[] = "Fixed $affected records: → '$canonical'";
                    
                    // Also fix feature_control table
                    $conn->query("UPDATE feature_control SET showroom_name = '$safe_canonical' 
                                  WHERE LOWER(TRIM(showroom_name)) = '$normalized' 
                                  AND showroom_name != '$safe_canonical'");
                }
            }
        }
    }
    
    echo json_encode([
        "status" => "success", 
        "message" => "Normalized $fixed showroom records",
        "details" => $details
    ]);
} 
// --- 11. SERVICE REPORTS MANAGEMENT ---
elseif ($action == 'get_all_service_reports') {
    $where = [];
    if (!empty($json_data['showroom'])) {
        $where[] = "showroom_name = '" . $conn->real_escape_string($json_data['showroom']) . "'";
    }
    if (!empty($json_data['status'])) {
        $where[] = "status = '" . $conn->real_escape_string($json_data['status']) . "'";
    }
    
    $where_clause = count($where) > 0 ? "WHERE " . implode(" AND ", $where) : "";
    $sql = "SELECT * FROM service_reports $where_clause ORDER BY created_at DESC LIMIT 500";
    
    $res = $conn->query($sql);
    $data = [];
    if ($res) {
        while ($row = $res->fetch_assoc()) {
            $data[] = $row;
        }
        echo json_encode(["status" => "success", "data" => $data]);
    } else {
        echo json_encode(["status" => "error", "message" => "Database Error: " . $conn->error]);
    }
} elseif ($action == 'delete_service_report') {
    $id = $conn->real_escape_string($json_data['id'] ?? '');
    if (empty($id)) {
        echo json_encode(["status" => "error", "message" => "ID required"]);
        exit;
    }
    $sql = "DELETE FROM service_reports WHERE id = '$id'";
    if ($conn->query($sql) === TRUE) {
        echo json_encode(["status" => "success", "message" => "Service report deleted successfully"]);
    } else {
        echo json_encode(["status" => "error", "message" => "Database error: " . $conn->error]);
    }
} else {
    // Default response for simple visiting the URL
    echo json_encode([
        "status" => "success",
        "message" => "Master Admin API is Online",
        "time" => date("Y-m-d H:i:s"),
        "received_action" => $action
    ]);
}

$conn->close();
?>
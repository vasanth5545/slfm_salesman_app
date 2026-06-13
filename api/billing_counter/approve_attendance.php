<?php
// slfm_backend_scripts/approve_attendance.php

// Enable CORS
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");

// Handle preflight OPTIONS request
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

// Locate db_connect.php
$possible_paths = [
    __DIR__ . '/../db_connect.php',
    __DIR__ . '/db_connect.php'
];

$db_connected = false;
foreach ($possible_paths as $path) {
    if (file_exists($path)) {
        require_once $path;
        $db_connected = true;
        break;
    }
}

if (!$db_connected) {
    echo json_encode(["status" => "error", "message" => "Database connection file not found"]);
    exit;
}

// Disable error display for cleaner JSON
error_reporting(E_ERROR | E_PARSE);
ini_set('display_errors', 0);
date_default_timezone_set('Asia/Kolkata');

// 🔥 Handle JSON input from dashboard
$json_input = file_get_contents('php://input');
$data = json_decode($json_input, true);

$action = $data['action'] ?? $_POST['action'] ?? '';
$attendance_id = $data['attendance_id'] ?? $_POST['attendance_id'] ?? '';
$approver_id = $data['staff_id'] ?? $data['approver_id'] ?? $_POST['approver_id'] ?? '';

if (empty($attendance_id)) {
    echo json_encode(["status" => "error", "message" => "Attendance ID is required (Received: " . json_encode($data) . ")"]);
    exit;
}

if (empty($approver_id)) {
    echo json_encode(["status" => "error", "message" => "Approver ID is required"]);
    exit;
}

// 🔥 SECURITY CHECK: Only Admin AND Owner can approve/reject
$startStmt = $conn->prepare("SELECT role FROM billing_staff WHERE staff_id = ?");
$startStmt->bind_param("s", $approver_id);
$startStmt->execute();
$res = $startStmt->get_result();
if ($res->num_rows > 0) {
    $r = $res->fetch_assoc();
    $user_role = strtolower($r['role']);

    // 🔥 FIX: Check for BOTH 'admin' and 'owner'
    if ($user_role !== 'admin' && $user_role !== 'owner') {
        echo json_encode(["status" => "error", "message" => "Permission Denied: Only Admin or Owner can perform this action."]);
        exit;
    }
} else {
    echo json_encode(["status" => "error", "message" => "Approver not found."]);
    exit;
}
$startStmt->close();

// Check if Action is Valid 
if ($action !== 'approve' && $action !== 'reject' && $action !== 'undo') {
    echo json_encode(["status" => "error", "message" => "Invalid Action"]);
    exit;
}

// STEP 1: Fetch Data from Database 
$checkStmt = $conn->prepare("
    SELECT a.clock_in_time, a.clock_out_time, a.status, a.is_out_of_location, s.gender, s.salesman_id, s.custom_late_cutoff 
    FROM attendance a 
    JOIN salesmen s ON a.salesman_id = s.salesman_id 
    WHERE a.id = ?
");
$checkStmt->bind_param("i", $attendance_id);
$checkStmt->execute();
$result = $checkStmt->get_result();

if ($result && $result->num_rows > 0) {
    $row = $result->fetch_assoc();

    if (empty($row['clock_in_time'])) {
        echo json_encode(["status" => "error", "message" => "Clock In time not found for this record."]);
        exit;
    }

    $clockInTime = strtotime($row['clock_in_time']);
    $dateStr = date('Y-m-d', $clockInTime);
    $is_out_of_location = $row['is_out_of_location'] ?? 0;
    $gender = strtolower($row['gender'] ?? 'male');
    $custom_late_cutoff = $row['custom_late_cutoff'];
    $salesman_id = $row['salesman_id'];

    // Define Thresholds (Intime Cutoffs)
    $late_cutoff_str = "10:00:59"; // Default cutoff

    // 🔥 ALTERNATIVE LOGIC: Only for those who have a custom late cutoff in DB (like SM234, SM454)
    // Other employees will still use the default 10:00:59
    if (!empty($custom_late_cutoff)) {
        // Adding 59 seconds (e.g., 10:30:00 becomes 10:30:59)
        $late_cutoff_str = date('H:i:s', strtotime($custom_late_cutoff) + 59);
    }

    $late_cutoff = strtotime("$dateStr $late_cutoff_str");
    $leave_cutoff = strtotime("$dateStr 15:00:59"); // 3:00 PM

    // STEP 2: Determine "Base Status" depending strictly on IN-TIME
    $baseStatus = 'Present';
    if ($clockInTime > $leave_cutoff) {
        $baseStatus = 'Leave';       // Vanthathe 3 PM ku mela
    } elseif ($clockInTime > $late_cutoff) {
        $baseStatus = 'Half Day';    // Vanthathu 10 AM to 3 PM kulla (Salesman 2 scenario)
    } else {
        $baseStatus = 'Present';     // Vanthathu 10 AM kulla (Salesman 1 scenario)
    }

    // STEP 3: Apply Approve or Reject logic based on Base Status
    $finalStatus = '';
    $adminApprovalText = null; // Default null

    if ($action === 'approve') {
        // Owner approved -> Forgive them and give status based on In-Time
        $finalStatus = $baseStatus;
        $adminApprovalText = 'Approved';

    } elseif ($action === 'reject') {
        // Owner rejected -> Punish / Downgrade the status
        $adminApprovalText = 'Rejected';

        // 🔥 REMOVED: is_out_of_location == 1 iruntha Leave nu maathum logic neekappattathu
        
        if ($baseStatus === 'Present') {
            $finalStatus = 'Half Day'; // Came early, left early -> Rejected -> Half Day
        } elseif ($baseStatus === 'Half Day') {
            $finalStatus = 'Leave';    // Came late, left early -> Rejected -> Leave
        } else {
            $finalStatus = 'Leave';    // Already Leave -> Stays Leave
        }
        
    } elseif ($action === 'undo') {
        // 🔥 NEW: UNDO LOGIC
        // If out of location, it goes back to 'Pending', else NULL
        $adminApprovalText = ($is_out_of_location == 1) ? 'Pending' : null;

        // Re-calculate the strictly punished status as if admin never touched it
        $finalStatus = $baseStatus;
        if (!empty($row['clock_out_time'])) {
            $out_time_str = date('H:i:s', strtotime($row['clock_out_time']));
            $exit_cutoff = ($gender == 'female') ? '20:00:00' : '21:00:00';

            if ($out_time_str < '14:30:00') {
                $finalStatus = 'Leave';
            } elseif ($out_time_str < $exit_cutoff) {
                $finalStatus = ($baseStatus == 'Half Day') ? 'Leave' : 'Half Day';
            }
        }
    }

    // STEP 4: Update the Final Status in Database 
    $updateStmt = $conn->prepare("UPDATE attendance SET status = ?, admin_approval = ? WHERE id = ?");
    $updateStmt->bind_param("ssi", $finalStatus, $adminApprovalText, $attendance_id);

    if ($updateStmt->execute()) {

        // Performance trigger (optional, you can add it if you want)
        $protocol = isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? "https" : "http";
        $host = $_SERVER['HTTP_HOST'];
        $script_dir = dirname($_SERVER['PHP_SELF']);
        $script_dir = trim(str_replace('\\', '/', $script_dir), '/');
        $base_url_for_perf = "$protocol://$host/$script_dir/";

        if (strpos($script_dir, 'billing_counter') !== false) {
            $base_url_for_perf = str_replace('billing_counter', '', $base_url_for_perf);
            $base_url_for_perf = rtrim($base_url_for_perf, '/') . '/';
        }

        $perf_url = $base_url_for_perf . "update_salesman_summary.php";

        $chkStmt = $conn->prepare("SELECT salesman_id FROM attendance WHERE id = ?");
        $chkStmt->bind_param("i", $attendance_id);
        $chkStmt->execute();
        $sRes = $chkStmt->get_result();
        if ($sRow = $sRes->fetch_assoc()) {
            $data = json_encode(['salesman_id' => $sRow['salesman_id']]);
            $options = [
                'http' => [
                    'header' => "Content-type: application/json\r\n",
                    'method' => 'POST',
                    'content' => $data,
                    'ignore_errors' => true,
                    'timeout' => 1
                ]
            ];
            $context = stream_context_create($options);
            @file_get_contents($perf_url, false, $context);
        }
        $chkStmt->close();

        // Dynamic success message
        $msg_text = ($action === 'undo') ? "Undo successful. Status reverted to $finalStatus." : "Attendance $adminApprovalText successfully! Status set to $finalStatus.";

        echo json_encode([
            "status" => "success",
            "message" => $msg_text,
            "new_status" => $finalStatus
        ]);
    } else {
        echo json_encode(["status" => "error", "message" => "DB Error: " . $conn->error]);
    }
    $updateStmt->close();

} else {
    echo json_encode(["status" => "error", "message" => "Attendance Record Not Found"]);
}

$checkStmt->close();
$conn->close();
?>
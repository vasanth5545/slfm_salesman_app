<?php
// FILE PATH: C:\xampp\htdocs\slfm_api\leave.php

error_reporting(0);
ini_set('display_errors', 0);

header("Content-Type: application/json");
date_default_timezone_set('Asia/Kolkata');

require 'db_connect.php';

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
    curl_setopt($ch, CURLOPT_TIMEOUT, 3);
    curl_exec($ch);
    curl_close($ch);
}

// --- HELPER: Get leave_apply_limit from RTDB (default 10) ---
function getLeaveApplyLimit($sid)
{
    $default_limit = 10; // fallback: 10:00 AM
    if (empty($sid))
        return $default_limit;

    $rtdb_url = "https://admin-decd9-default-rtdb.asia-southeast1.firebasedatabase.app";
    $rtdb_secret = "y9O4hN0n1Od4HuPf8co9uaRT2t750HUOYnhTaJJ3";

    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $rtdb_url . "/salesmen_status/" . $sid . "/leave_apply_limit.json?auth=" . $rtdb_secret);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 3);
    $response = curl_exec($ch);
    curl_close($ch);

    if ($response !== false && $response !== 'null') {
        $val = json_decode($response, true);
        if (is_numeric($val))
            return (int) $val;
    }
    return $default_limit;
}

$json_data = json_decode(file_get_contents('php://input'), true);
$action = $json_data['action'] ?? $_POST['action'] ?? '';
$salesman_id = $json_data['salesman_id'] ?? $_POST['salesman_id'] ?? '';

if (empty($salesman_id)) {
    echo json_encode(["status" => "error", "message" => "Salesman ID Required"]);
    exit;
}

// --- 1. APPLY LEAVE ---
if ($action == 'apply_leave') {
    $date = $json_data['date'] ?? $_POST['date'] ?? '';
    $type = $json_data['type'] ?? $_POST['type'] ?? 'Full Day';
    $reason = $json_data['reason'] ?? $_POST['reason'] ?? '';

    if (empty($date) || empty($reason)) {
        echo json_encode(["status" => "error", "message" => "Date and Reason required"]);
        exit;
    }

    $today = date('Y-m-d');
    $current_time = date('H:i');
    $current_hour = (int) date('H');

    if ($date < $today) {
        echo json_encode(["status" => "error", "message" => "Cannot apply leave for past dates."]);
        exit;
    }

    // 🔥 FIX: Dynamic leave apply limit from RTDB (synced with Flutter)
    $leave_limit_hour = getLeaveApplyLimit($salesman_id);
    if ($date == $today && $current_hour >= $leave_limit_hour) {
        $display_hour = $leave_limit_hour > 12 ? $leave_limit_hour - 12 : $leave_limit_hour;
        $am_pm = $leave_limit_hour >= 12 ? 'PM' : 'AM';
        echo json_encode(["status" => "error", "message" => "Time exceeded! Apply before $display_hour:00 $am_pm."]);
        exit;
    }

    $month_start = date('Y-m-01');
    $month_end = date('Y-m-t');

    // 🔥 CALCULATE TOTAL LEAVE DAYS (Full Day = 1.0, Half Day = 0.5)
    $calc_sql = "SELECT 
                    SUM(CASE 
                        WHEN leave_type = 'Full Day' THEN 1.0 
                        WHEN leave_type = 'Half Day' THEN 0.5 
                        ELSE 0 
                    END) as total_days
                 FROM leave_requests 
                 WHERE salesman_id = '$salesman_id' 
                 AND leave_date BETWEEN '$month_start' AND '$month_end'
                 AND status != 'Rejected' AND status != 'Cancelled'";

    $calc_res = $conn->query($calc_sql);
    $calc_row = $calc_res->fetch_assoc();
    $current_leave_days = (float) ($calc_row['total_days'] ?? 0);

    // 🎯 AUTO-APPROVAL LOGIC: First 4 days = Approved, Beyond 4 = Pending
    $leave_status = ($current_leave_days < 4) ? 'Approved' : 'Pending';
    $status_message = ($current_leave_days < 4) ? 'Approved' : 'Pending (Awaiting Admin Approval)';

    $safe_reason = $conn->real_escape_string($reason);
    $safe_type = $conn->real_escape_string($type);
    $safe_date = $conn->real_escape_string($date);

    // Check Duplicate
    $check_sql = "SELECT id FROM leave_requests WHERE salesman_id = '$salesman_id' AND leave_date = '$safe_date' AND status != 'Rejected' AND status != 'Cancelled'";
    if ($conn->query($check_sql)->num_rows > 0) {
        echo json_encode(["status" => "error", "message" => "Leave already applied for this date"]);
        exit;
    }

    $php_now = date('Y-m-d H:i:s');
    $sql = "INSERT INTO leave_requests (salesman_id, leave_date, leave_type, reason, status, created_at) 
            VALUES ('$salesman_id', '$safe_date', '$safe_type', '$safe_reason', '$leave_status', '$php_now')";

    if ($conn->query($sql) === TRUE) {
        $new_leave_id = $conn->insert_id; // 🔥 FIX: Return real MySQL ID

        // Calculate remaining leave days
        $new_leave_value = ($type == 'Full Day') ? 1.0 : 0.5;
        $new_total = $current_leave_days + $new_leave_value;
        $remaining = 4 - $new_total;

        // Build message with remaining days
        if ($remaining > 0) {
            $remaining_msg = " Remaining: " . number_format($remaining, 1) . " days";
        } else {
            $remaining_msg = " (Limit reached. Further requests need admin approval)";
        }

        // 🔥 FIX: Send RTDB sync signal for real-time UI refresh
        sendSyncSignal($salesman_id);

        echo json_encode([
            "status" => "success",
            "message" => "Leave $status_message!$remaining_msg",
            "remaining_days" => max(0, $remaining),
            "leave_id" => $new_leave_id,
            "leave_status" => $leave_status
        ]);
    } else {
        echo json_encode(["status" => "error", "message" => "Database Error: " . $conn->error]);
    }
}

// --- 2. GET HISTORY ---
elseif ($action == 'get_history') {

    // 🔥 FIX 2: Auto-upgrade Half Day leave → Full Day if time >= 15:00 and no clock-in today.
    // Rule: Half Day leave apply பண்ணி 3 மணி ஆனாலும் clock in இல்லாமல் போனால் Full Day ஆகும்.
    $today = date('Y-m-d');
    $current_time = date('H:i');
    if ($current_time >= '15:00') {
        // Find today's Half Day leaves with no clock-in
        $check_clock_sql = "SELECT COUNT(*) as cnt FROM attendance 
                            WHERE salesman_id = '$salesman_id' AND date = '$today' 
                            AND clock_in_time IS NOT NULL";
        $check_res = $conn->query($check_clock_sql);
        $has_clock_in = ($check_res && $check_res->fetch_assoc()['cnt'] > 0);

        if (!$has_clock_in) {
            // Upgrade Half Day → Full Day in DB
            $conn->query("UPDATE leave_requests 
                          SET leave_type = 'Full Day' 
                          WHERE salesman_id = '$salesman_id' 
                          AND leave_date = '$today' 
                          AND leave_type = 'Half Day' 
                          AND status IN ('Approved', 'Pending')");
        }
    }

    // 🔥 FIX: Only fetch current month + previous month (performance + cost reduction)
    $first_day_prev_month = date('Y-m-01', strtotime('first day of last month'));
    $sql = "SELECT id, leave_date, leave_type, reason, status, created_at 
            FROM leave_requests 
            WHERE salesman_id = '$salesman_id' 
            AND leave_date >= '$first_day_prev_month'
            ORDER BY leave_date DESC";

    $result = $conn->query($sql);
    $history = [];

    if ($result) {
        while ($row = $result->fetch_assoc()) {
            $history[] = $row;
        }
        echo json_encode(["status" => "success", "data" => $history]);
    } else {
        echo json_encode(["status" => "error", "message" => "Failed to fetch history"]);
    }
}

// --- 2b. UPGRADE HALF LEAVES (Called by Flutter after 3 PM) ---
elseif ($action == 'upgrade_half_leaves') {
    // Upgrade today's Half Day leaves to Full Day if no clock-in and time >= 15:00
    $today = date('Y-m-d');
    $current_time = date('H:i');

    if ($current_time < '15:00') {
        echo json_encode(["status" => "info", "message" => "Too early - upgrade happens after 3:00 PM"]);
        exit;
    }

    $check_clock_sql = "SELECT COUNT(*) as cnt FROM attendance 
                        WHERE salesman_id = '$salesman_id' AND date = '$today' 
                        AND clock_in_time IS NOT NULL";
    $check_res = $conn->query($check_clock_sql);
    $has_clock_in = ($check_res && $check_res->fetch_assoc()['cnt'] > 0);

    if ($has_clock_in) {
        echo json_encode(["status" => "info", "message" => "Clock-in found — no upgrade needed"]);
        exit;
    }

    $upgrade_sql = "UPDATE leave_requests 
                    SET leave_type = 'Full Day' 
                    WHERE salesman_id = '$salesman_id' 
                    AND leave_date = '$today' 
                    AND leave_type = 'Half Day' 
                    AND status IN ('Approved', 'Pending')";

    if ($conn->query($upgrade_sql)) {
        $affected = $conn->affected_rows;
        echo json_encode([
            "status" => "success",
            "message" => $affected > 0 ? "Half Day upgraded to Full Day" : "No Half Day leaves to upgrade",
            "upgraded" => $affected > 0
        ]);
    } else {
        echo json_encode(["status" => "error", "message" => "DB Error: " . $conn->error]);
    }
}

// --- 3. REQUEST CANCELLATION (FIXED ID & ADDED NAME) ---
elseif ($action == 'request_cancellation') {
    $leave_id = $json_data['leave_id'] ?? $_POST['leave_id'] ?? '';
    $message = $json_data['message'] ?? $_POST['message'] ?? '';

    if (empty($leave_id)) {
        echo json_encode(["status" => "error", "message" => "ID required"]);
        exit;
    }

    $safe_message = $conn->real_escape_string($message);

    // Check if leave exists
    $check_sql = "SELECT id, leave_date FROM leave_requests WHERE id = '$leave_id' AND salesman_id = '$salesman_id'";
    $check_res = $conn->query($check_sql);

    if ($check_res->num_rows > 0) {
        $row = $check_res->fetch_assoc();
        $leave_date = $row['leave_date'];
        $today = date('Y-m-d');

        if ($leave_date >= $today) {

            // A. Update Main Table
            $upd_sql = "UPDATE leave_requests SET status = 'Cancelled' WHERE id = '$leave_id'";
            $conn->query($upd_sql);

            // B. Get Salesman Name from 'salesmen' table
            // (Assuming table name is 'salesmen' and column is 'name' or 'full_name')
            $name_sql = "SELECT name FROM salesmen WHERE salesman_id = '$salesman_id'";
            $name_res = $conn->query($name_sql);
            $salesman_name = "Unknown";
            if ($name_res && $name_res->num_rows > 0) {
                $salesman_name = $name_res->fetch_assoc()['name'];
            }

            $php_now = date('Y-m-d H:i:s');
            // C. Insert into Cancel Table with NAME
            $insert_cancel_sql = "INSERT INTO leave_cancel_requests (salesman_id, salesman_name, leave_id, cancel_reason, created_at) 
                                   VALUES ('$salesman_id', '$salesman_name', '$leave_id', '$safe_message', '$php_now')";

            if ($conn->query($insert_cancel_sql)) {
                echo json_encode(["status" => "success", "message" => "Leave Cancelled & Saved with Name!"]);
            } else {
                echo json_encode(["status" => "error", "message" => "Save Failed: " . $conn->error]);
            }

        } else {
            echo json_encode(["status" => "error", "message" => "Cannot cancel past leaves"]);
        }
    } else {
        echo json_encode(["status" => "error", "message" => "Leave not found"]);
    }
}

// --- 4. GET CANCEL REQUESTS ---
elseif ($action == 'get_cancel_requests') {
    $sql = "SELECT 
                c.cancel_reason as request_message, 
                c.created_at, 
                l.leave_date, 
                l.leave_type,
                l.status
            FROM leave_cancel_requests c
            JOIN leave_requests l ON c.leave_id = l.id
            WHERE c.salesman_id = '$salesman_id'
            ORDER BY c.created_at DESC";

    $result = $conn->query($sql);
    $requests = [];

    if ($result) {
        while ($row = $result->fetch_assoc()) {
            $requests[] = $row;
        }
        echo json_encode(["status" => "success", "data" => $requests]);
    } else {
        echo json_encode(["status" => "error", "message" => "Failed to fetch requests"]);
    }
}

// --- 5. GET ALL LEAVES (For HTML WebView — All Salesmen, 2 Months) ---
elseif ($action == 'get_all_leaves') {
    $first_day_prev_month = date('Y-m-01', strtotime('first day of last month'));

    $sql = "SELECT lr.id, lr.salesman_id, s.name AS salesman_name, 
                   lr.leave_date, lr.leave_type, lr.reason, lr.status, lr.created_at
            FROM leave_requests lr
            LEFT JOIN salesmen s ON lr.salesman_id = s.salesman_id
            WHERE lr.leave_date >= '$first_day_prev_month'
            ORDER BY lr.leave_date DESC, lr.created_at DESC";

    $result = $conn->query($sql);
    $leaves = [];

    if ($result) {
        while ($row = $result->fetch_assoc()) {
            $leaves[] = $row;
        }
        echo json_encode(["status" => "success", "data" => $leaves]);
    } else {
        echo json_encode(["status" => "error", "message" => "Failed to fetch leaves"]);
    }
}

$conn->close();
?>
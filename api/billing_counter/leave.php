<?php
// slfm_api/billing_counter/leave.php

error_reporting(E_ALL);
ini_set('display_errors', 0);

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST");
header("Access-Control-Allow-Headers: Content-Type");

date_default_timezone_set('Asia/Kolkata');

// 2. DB Connection (Robust)
// Tries current dir first, then parent dir
$db_found = false;
$possible_paths = [
    __DIR__ . '/db_connect.php',     
    __DIR__ . '/../db_connect.php' 
];
foreach ($possible_paths as $path) {
    if (file_exists($path)) {
        require $path;
        $db_found = true;
        break;
    }
}

if (!$db_found) {
    echo json_encode(["status" => "error", "message" => "db_connect.php not found"]);
    exit;
}

$json_data = json_decode(file_get_contents('php://input'), true);
$action = $json_data['action'] ?? $_POST['action'] ?? '';

// ----------------------------------------------------------------------
// ACTION: APPLY LEAVE
// ----------------------------------------------------------------------
if ($action == 'apply_leave') {
    $salesman_id = $json_data['salesman_id'] ?? $_POST['salesman_id'] ?? '';
    $leave_date  = $json_data['leave_date'] ?? $_POST['leave_date'] ?? '';
    $leave_type  = $json_data['leave_type'] ?? $_POST['leave_type'] ?? 'Full Day';
    $reason      = $json_data['reason'] ?? $_POST['reason'] ?? '';

    if (empty($salesman_id) || empty($leave_date) || empty($reason)) {
        echo json_encode(["status" => "error", "message" => "Missing required fields"]);
        exit;
    }

    // Optional: Check if already exists for this date
    $checkSql = "SELECT id FROM leave_requests WHERE salesman_id = '$salesman_id' AND leave_date = '$leave_date' AND status != 'Rejected'";
    $checkRes = $conn->query($checkSql);
    if ($checkRes && $checkRes->num_rows > 0) {
        echo json_encode(["status" => "error", "message" => "Leave request already exists for this date"]);
        exit;
    }

    $stmt = $conn->prepare("INSERT INTO leave_requests (salesman_id, leave_date, leave_type, reason, status) VALUES (?, ?, ?, ?, 'Pending')");
    $stmt->bind_param("ssss", $salesman_id, $leave_date, $leave_type, $reason);

    if ($stmt->execute()) {
        echo json_encode(["status" => "success", "message" => "Leave applied successfully"]);
    } else {
        echo json_encode(["status" => "error", "message" => "Failed to apply leave: " . $stmt->error]);
    }
}

// ----------------------------------------------------------------------
// ACTION: CANCEL LEAVE REQUEST
// ----------------------------------------------------------------------
elseif ($action == 'cancel_leave') {
    $salesman_id   = $json_data['salesman_id'] ?? $_POST['salesman_id'] ?? '';
    $leave_id      = $json_data['leave_id'] ?? $_POST['leave_id'] ?? '';
    $cancel_reason = $json_data['reason'] ?? $_POST['reason'] ?? 'By User';

    if (empty($salesman_id) || empty($leave_id)) {
        echo json_encode(["status" => "error", "message" => "Missing ID or Leave ID"]);
        exit;
    }

    // 1. Fetch Salesman Name for the record
    $nameSql = "SELECT name FROM salesmen WHERE salesman_id = '$salesman_id'";
    $nameRes = $conn->query($nameSql);
    $salesman_name = "Unknown";
    if ($nameRes && $nameRes->num_rows > 0) {
        $r = $nameRes->fetch_assoc();
        $salesman_name = $r['name'];
    }

    // 2. Insert into leave_cancel_requests
    $stmt = $conn->prepare("INSERT INTO leave_cancel_requests (salesman_id, salesman_name, leave_id, cancel_reason) VALUES (?, ?, ?, ?)");
    $stmt->bind_param("ssss", $salesman_id, $salesman_name, $leave_id, $cancel_reason);

    if ($stmt->execute()) {
        echo json_encode(["status" => "success", "message" => "Cancel request submitted"]);
    } else {
        echo json_encode(["status" => "error", "message" => "Failed to submit request: " . $stmt->error]);
    }
}

// ----------------------------------------------------------------------
// ACTION: GET LEAVE HISTORY (For App List)
// ----------------------------------------------------------------------
elseif ($action == 'get_leave_history') {
    $salesman_id = $json_data['salesman_id'] ?? $_POST['salesman_id'] ?? '';

    if (empty($salesman_id)) {
        echo json_encode(["status" => "error", "message" => "Missing Salesman ID"]);
        exit;
    }

    $sql = "SELECT * FROM leave_requests WHERE salesman_id = '$salesman_id' ORDER BY created_at DESC";
    $result = $conn->query($sql);
    
    $data = [];
    if ($result) {
        while ($row = $result->fetch_assoc()) {
            $data[] = $row;
        }
    }

    echo json_encode(["status" => "success", "data" => $data]);
}

else {
    echo json_encode(["status" => "error", "message" => "Invalid Action"]);
}

$conn->close();
?>

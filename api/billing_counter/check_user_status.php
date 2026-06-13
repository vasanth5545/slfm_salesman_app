<?php
// billing_counter/check_user_status.php
// Check if staff_id exists in the database

header("Content-Type: application/json");
require 'db_connect.php';

$json_data = json_decode(file_get_contents('php://input'), true);

$staff_id = $json_data['staff_id'] ?? $_POST['staff_id'] ?? '';

if (empty($staff_id)) {
    echo json_encode(["status" => "error", "message" => "Staff ID required"]);
    exit;
}

// Check if user exists
$sql = "SELECT staff_id FROM billing_staff WHERE staff_id = '$staff_id'";
$result = $conn->query($sql);

if ($result && $result->num_rows > 0) {
    echo json_encode(["status" => "active", "message" => "User is active"]);
} else {
    echo json_encode(["status" => "inactive", "message" => "User not found"]);
}

$conn->close();
?>

<?php
// api/billing_counter/toggle_feature.php
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: POST");
include 'db_connect.php'; 

$feature_name = isset($_POST['feature_name']) ? $conn->real_escape_string($_POST['feature_name']) : null; 
$status = isset($_POST['status']) ? intval($_POST['status']) : null; 

if ($feature_name === null || $status === null) {
    echo json_encode(['status' => 'error', 'message' => 'Missing feature_name or status parameter']);
    exit;
}

$sql = "INSERT INTO feature_control (feature_name, is_active) 
        VALUES ('$feature_name', $status) 
        ON DUPLICATE KEY UPDATE is_active = $status";

if ($conn->query($sql) === TRUE) {
    echo json_encode(['status' => 'success', 'message' => "Feature '$feature_name' updated successfully."]);
} else {
    echo json_encode(['status' => 'error', 'message' => 'Failed to update feature: ' . $conn->error]);
}
$conn->close();
?>

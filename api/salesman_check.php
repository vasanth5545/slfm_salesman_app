<?php
// api/salesman_check.php
// Lightweight endpoint for Splash Screen to verify salesman status
// Returns: active/suspended status from MySQL salesmen table
// Used by Flutter app at startup to block suspended users

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require 'db_connect.php';

$json_data = json_decode(file_get_contents('php://input'), true);
$salesman_id = $json_data['salesman_id'] ?? $_POST['salesman_id'] ?? $_GET['salesman_id'] ?? '';

if (empty($salesman_id)) {
    echo json_encode(["status" => "error", "message" => "Salesman ID required"]);
    exit;
}

$safe_id = $conn->real_escape_string($salesman_id);
$sql = "SELECT salesman_id, name, status, showroom_name FROM salesmen WHERE salesman_id = '$safe_id' LIMIT 1";
$result = $conn->query($sql);

if ($result && $result->num_rows > 0) {
    $row = $result->fetch_assoc();
    $account_status = $row['status'] ?? 'Active';
    
    echo json_encode([
        "status" => "success",
        "data" => [
            "salesman_id" => $row['salesman_id'],
            "name" => $row['name'],
            "account_status" => $account_status,
            "showroom_name" => $row['showroom_name'] ?? 'Main Branch'
        ]
    ]);
} else {
    // Salesman not found in DB
    echo json_encode([
        "status" => "error",
        "message" => "Salesman not found",
        "data" => [
            "account_status" => "NotFound"
        ]
    ]);
}

$conn->close();
?>

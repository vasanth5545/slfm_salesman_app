<?php
// register_salesman.php
// Registers a new salesman with Showroom Details

header("Content-Type: application/json");
require 'db_connect.php';

// Get JSON Input
$json_data = json_decode(file_get_contents('php://input'), true);

// Extract Data
$salesman_id = $json_data['salesman_id'] ?? $_POST['salesman_id'] ?? '';
$name = $json_data['name'] ?? $_POST['name'] ?? '';
$password = $json_data['password'] ?? $_POST['password'] ?? '';
$showroom_name = $json_data['showroom_name'] ?? $_POST['showroom_name'] ?? 'Main Branch';
$showroom_address = $json_data['showroom_address'] ?? $_POST['showroom_address'] ?? '';

// Validation
if (empty($salesman_id) || empty($name) || empty($password)) {
    echo json_encode(["status" => "error", "message" => "ID, Name, and Password are required"]);
    exit;
}

// Check if ID exists
$check_sql = "SELECT id FROM salesmen WHERE salesman_id = '$salesman_id'";
if ($conn->query($check_sql)->num_rows > 0) {
    echo json_encode(["status" => "error", "message" => "Salesman ID already exists"]);
    exit;
}

// Insert into Database
$sql = "INSERT INTO salesmen (salesman_id, name, password_hash, showroom_name, showroom_address, status) 
        VALUES ('$salesman_id', '$name', '$password', '$showroom_name', '$showroom_address', 'Active')";

if ($conn->query($sql) === TRUE) {
    echo json_encode([
        "status" => "success", 
        "message" => "Salesman Registered Successfully",
        "data" => [
            "salesman_id" => $salesman_id,
            "name" => $name,
            "showroom" => $showroom_name
        ]
    ]);
} else {
    echo json_encode(["status" => "error", "message" => "Database Error: " . $conn->error]);
}

$conn->close();
?>
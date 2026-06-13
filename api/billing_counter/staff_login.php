<?php
// billing_counter/staff_login.php
// Login for Billing Staff (Admin/Staff)

header("Content-Type: application/json");
require '../db_connect.php'; // Corrected path (same directory)

$json_data = json_decode(file_get_contents('php://input'), true);

$staff_id = $json_data['staff_id'] ?? $_POST['staff_id'] ?? '';
$password = $json_data['password'] ?? $_POST['password'] ?? '';

if (empty($staff_id) || empty($password)) {
    echo json_encode(["status" => "error", "message" => "Staff ID and Password required"]);
    exit;
}

$sql = "SELECT * FROM billing_staff WHERE staff_id = '$staff_id'";
$result = $conn->query($sql);

if ($result && $result->num_rows > 0) {
    $row = $result->fetch_assoc();
    
    // Check password (Simple check for now, in real app use password_verify)
    if ($password === $row['password_hash']) {
        echo json_encode([
            "status" => "success",
            "message" => "Login Successful",
            "data" => [
                "staff_id" => $row['staff_id'],
                "name" => $row['name'],
                "role" => $row['role'],
                "showroom" => $row['showroom'] // 🔥 Added showoom field
            ]
        ]);
    } else {
        echo json_encode(["status" => "error", "message" => "Invalid Password"]);
    }
} else {
    echo json_encode(["status" => "error", "message" => "Staff ID not found"]);
}

$conn->close();
?>

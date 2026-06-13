<?php
// login.php
// Updated to return showroom_name AND handle Device Locking
header("Content-Type: application/json");
require 'db_connect.php';
// Handle both JSON and POST data
$json_data = json_decode(file_get_contents('php://input'), true);
$salesman_id = isset($json_data['salesman_id']) ? $conn->real_escape_string($json_data['salesman_id']) : (isset($_POST['salesman_id']) ? $conn->real_escape_string($_POST['salesman_id']) : '');
$password = isset($json_data['password']) ? $conn->real_escape_string($json_data['password']) : (isset($_POST['password']) ? $conn->real_escape_string($_POST['password']) : '');
// 📱 NEW: Device Info Inputs
$device_id = isset($json_data['device_id']) ? $conn->real_escape_string($json_data['device_id']) : (isset($_POST['device_id']) ? $conn->real_escape_string($_POST['device_id']) : '');
$device_model = isset($json_data['device_model']) ? $conn->real_escape_string($json_data['device_model']) : (isset($_POST['device_model']) ? $conn->real_escape_string($_POST['device_model']) : '');
if (empty($salesman_id) || empty($password)) {
    echo json_encode(["status" => "error", "message" => "ID and Password required"]);
    exit;
}
$sql = "SELECT * FROM salesmen WHERE salesman_id = '$salesman_id'";
$result = $conn->query($sql);
if ($result && $result->num_rows > 0) {
    $row = $result->fetch_assoc();
    
    if ($row['status'] !== 'Active') {
        echo json_encode(["status" => "error", "message" => "Account Suspended"]);
        exit;
    }
    if ($password === $row['password_hash']) {
        
        // --- 🔒 DEVICE LOCKING LOGIC (ADDED) ---
        // Only run if device_id is sent (App side feature)
        if (!empty($device_id)) {
            // Check if 'primary_device_id' exists in the row (Handling database mismatch safely)
            if (array_key_exists('primary_device_id', $row)) {
                
                // Case 1: First Time Binding (If NULL or Empty)
                if (empty($row['primary_device_id'])) {
                    $updateSql = "UPDATE salesmen SET primary_device_id = '$device_id', primary_device_model = '$device_model', is_device_locked = 1 WHERE id = " . $row['id'];
                    $conn->query($updateSql);
                }
                
                // Case 2: Mismatch Check (Emergency Logic: We do NOT block, just logging implicitly)
                // If you want to BLOCK in future, uncomment this:
                /*
                else if ($row['primary_device_id'] !== $device_id) {
                     echo json_encode(["status" => "error", "message" => "Device Mismatch! Please use your registered device."]);
                     exit;
                }
                */
            }
        }
        // --- 🔒 END DEVICE LOCKING LOGIC ---
        echo json_encode([
            "status" => "success",
            "message" => "Login successful",
            "data" => [
                "id" => $row['id'],
                "name" => $row['name'],
                "salesman_id" => $row['salesman_id'],
                "profile_photo" => $row['profile_photo'] ?? '',
                "avatar_animal" => $row['avatar_animal'] ?? '',
                // IMPORTANT: Send Showroom Details (PRESERVED)
                "showroom_name" => $row['showroom_name'] ?? "Main Branch", 
                "showroom_address" => $row['showroom_address'] ?? "",
                "role" => $row['role'] ?? "salesman",
                "custom_late_cutoff" => $row['custom_late_cutoff'] ?? "10:00:59"
            ]
        ]);
    } else {
        echo json_encode(["status" => "error", "message" => "Incorrect Password"]);
    }
} else {
    echo json_encode(["status" => "error", "message" => "Invalid ID"]);
}
$conn->close();
?>

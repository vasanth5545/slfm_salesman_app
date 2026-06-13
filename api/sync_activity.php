<?php
// sync_activity.php - FIXED TIMEZONE
header("Content-Type: application/json");
date_default_timezone_set('Asia/Kolkata');
require 'db_connect.php';

// Get Input
$json_data = json_decode(file_get_contents('php://input'), true);
$salesman_id = $json_data['salesman_id'] ?? $_POST['salesman_id'] ?? $_GET['salesman_id'] ?? '';

if (empty($salesman_id)) {
    echo json_encode(["status" => "error", "message" => "Salesman ID Required"]);
    exit;
}

// 🔥 FORCE MYSQL TO IST (+05:30)
$conn->query("SET time_zone = '+05:30'");

// 🔥 USE MySQL 'NOW()' function (Safest for Timezone)
$sql = "UPDATE salesmen SET last_sync = NOW() WHERE salesman_id = '$salesman_id'";

if ($conn->query($sql) === TRUE) {
    if ($conn->affected_rows > 0) {
        // Fetch the inserted time back to be 100% sure
        $time_query = $conn->query("SELECT DATE_FORMAT(last_sync, '%h:%i %p') as ist_time FROM salesmen WHERE salesman_id = '$salesman_id'");
        $row = $time_query->fetch_assoc();
        
        echo json_encode([
            "status" => "success",
            "message" => "Sync Updated",
            "last_sync" => $row['ist_time'] // Returns exact DB time
        ]);
    } else {
        // Check Existence
        $check = $conn->query("SELECT id FROM salesmen WHERE salesman_id = '$salesman_id'");
        if ($check->num_rows > 0) {
             echo json_encode(["status" => "success", "message" => "Already Synced just now"]);
        } else {
             echo json_encode(["status" => "error", "message" => "Salesman ID Not Found"]);
        }
    }
} else {
    echo json_encode(["status" => "error", "message" => "SQL Error: " . $conn->error]);
}

$conn->close();
?>
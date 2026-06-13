<?php
// FILE: api/create_rewards_table.php
// PURPOSE: Initializes the special_rewards table with dynamic limit tracking.

header("Content-Type: application/json");
require_once __DIR__ . '/db_connect.php';

// Single table for both rewards tracking and limit configuration
$sql = "CREATE TABLE IF NOT EXISTS special_rewards (
    id INT AUTO_INCREMENT PRIMARY KEY,
    salesman_id VARCHAR(50) DEFAULT NULL, -- NULL indicates a CONFIG record
    reward_name VARCHAR(100) NOT NULL,
    min_billed INT DEFAULT 1000, -- Dynamic limit
    unlocked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)";

if ($conn->query($sql) === TRUE) {
    // Insert default config if not exists
    $check = $conn->query("SELECT id FROM special_rewards WHERE salesman_id IS NULL AND reward_name = 'Scarface'");
    if ($check->num_rows == 0) {
        $conn->query("INSERT INTO special_rewards (salesman_id, reward_name, min_billed) VALUES (NULL, 'Scarface', 1000)");
    }
    echo json_encode(["status" => "success", "message" => "Table 'special_rewards' initialized with dynamic config."]);
} else {
    echo json_encode(["status" => "error", "message" => "Error: " . $conn->error]);
}

$conn->close();
?>

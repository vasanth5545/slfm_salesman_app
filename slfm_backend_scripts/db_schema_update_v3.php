<?php
// slfm_backend_scripts/db_schema_update_v3.php
// Purpose: Add 'allow_late_entry' column to salesmen table for Manual Override (Task 2)

error_reporting(E_ALL);
ini_set('display_errors', 1);
header("Content-Type: application/json");

require_once 'db_connect.php';

$response = ["status" => "pending", "messages" => []];

// 1. Add 'allow_late_entry' to salesmen table
$table = "salesmen";
$column = "allow_late_entry";
$check_sql = "SHOW COLUMNS FROM $table LIKE '$column'";
$result = $conn->query($check_sql);

if ($result && $result->num_rows == 0) {
    // Add Column: TINYINT(1) default 0
    $alter_sql = "ALTER TABLE $table ADD COLUMN $column TINYINT(1) DEFAULT 0 AFTER shift_end_time";
    if ($conn->query($alter_sql) === TRUE) {
        $response['messages'][] = "✅ Column '$column' added to '$table' successfully.";
    } else {
        $response['messages'][] = "❌ Error adding column '$column': " . $conn->error;
    }
} else {
    $response['messages'][] = "ℹ️ Column '$column' already exists in '$table'.";
}

echo json_encode($response);
$conn->close();
?>

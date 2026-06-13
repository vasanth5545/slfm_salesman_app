<?php
// slfm_backend_scripts/db_schema_update_v4.php
// PURPOSE: Add 'excluded_dates' column to 'salesman_monthly_performance' table

require_once 'db_connect.php';

// SQL to Add Column
$sql = "ALTER TABLE `salesman_monthly_performance` 
        ADD COLUMN `excluded_dates` TEXT DEFAULT NULL AFTER `report_month`";

if ($conn->query($sql) === TRUE) {
    echo json_encode(["status" => "success", "message" => "Column 'excluded_dates' added successfully."]);
} else {
    // Check if duplicate column error
    if (strpos($conn->error, "Duplicate column") !== false) {
        echo json_encode(["status" => "success", "message" => "Column 'excluded_dates' already exists."]);
    } else {
        echo json_encode(["status" => "error", "message" => "Error adding column: " . $conn->error]);
    }
}

$conn->close();
?>

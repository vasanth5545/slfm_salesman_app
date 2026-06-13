<?php
// slfm_backend_scripts/db_schema_update_v2.php
// PURPOSE: Add 'total_worked_days' column to salesman_monthly_performance
header("Content-Type: application/json");
require_once __DIR__ . '/db_connect.php';

$response = [];

// Check specific column
$check_col = $conn->query("SHOW COLUMNS FROM salesman_monthly_performance LIKE 'total_worked_days'");
if ($check_col->num_rows == 0) {
    // Add the column
    $sql = "ALTER TABLE salesman_monthly_performance 
            ADD COLUMN total_worked_days DECIMAL(5,2) DEFAULT 0.00 
            AFTER attendance_percentage";
    
    if ($conn->query($sql) === TRUE) {
        $response['status'] = 'success';
        $response['message'] = "Added column 'total_worked_days' successfully.";
    } else {
        $response['status'] = 'error';
        $response['message'] = "Error adding column: " . $conn->error;
    }
} else {
    $response['status'] = 'success';
    $response['message'] = "Column 'total_worked_days' already exists.";
}

echo json_encode($response);
$conn->close();
?>

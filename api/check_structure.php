<?php
// check_structure.php
// RUN THIS in browser: http://your-domain/check_structure.php
header("Content-Type: application/json");
require 'db_connect.php';
$table = 'location_history';
// Check if table exists
$check = $conn->query("SHOW TABLES LIKE '$table'");
if ($check->num_rows == 0) {
    echo json_encode(["status" => "error", "message" => "Table '$table' does NOT exist!"]);
    exit;
}
// Get Columns
$sql = "DESCRIBE $table";
$result = $conn->query($sql);
$columns = [];
while($row = $result->fetch_assoc()) {
    $columns[] = $row['Field'] . " (" . $row['Type'] . ")";
}
echo json_encode([
    "status" => "success", 
    "table" => $table, 
    "columns" => $columns
], JSON_PRETTY_PRINT);
$conn->close();
?>
<?php
// slfm_backend_scripts/fix_performance_all.php
// PURPOSE: Return all salesmen IDs for frontend sequential recalculation.

require_once 'db_connect.php';

header('Content-Type: application/json');

$sql = "SELECT salesman_id FROM salesmen";
$result = $conn->query($sql);
$salesmen = [];

if ($result && $result->num_rows > 0) {
    while($row = $result->fetch_assoc()) {
        $salesmen[] = $row['salesman_id'];
    }
}

echo json_encode(["status" => "success", "salesmen" => $salesmen]);
$conn->close();
?>

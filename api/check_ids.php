<?php
require_once 'db_connect.php';
$result = $conn->query("SELECT salesman_id, name, showroom_name FROM salesmen LIMIT 10");
$data = [];
while($row = $result->fetch_assoc()) {
    $data[] = $row;
}
echo json_encode($data, JSON_PRETTY_PRINT);
?>

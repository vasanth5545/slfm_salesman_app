<?php
require_once 'db_connect.php';
$result = $conn->query("DESCRIBE salesmen");
$schema = [];
while($row = $result->fetch_assoc()) {
    $schema[] = $row;
}
echo json_encode($schema, JSON_PRETTY_PRINT);
?>

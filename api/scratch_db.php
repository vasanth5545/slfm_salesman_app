<?php
require 'db_connect.php';
$res = $conn->query("SELECT * FROM attendance WHERE salesman_id='SM008' AND date='2026-06-05'");
$row = $res->fetch_assoc();
echo json_encode($row);
?>

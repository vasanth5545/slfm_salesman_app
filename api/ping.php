<?php
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json");
echo json_encode(["status" => "ok", "message" => "PHP Server is alive", "time" => date("Y-m-d H:i:s")]);
?>

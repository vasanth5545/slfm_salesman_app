<?php
// FILE: api/get_avatar_availability.php
// PURPOSE: Returns a list of animal avatars that are already assigned to salesmen.

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
require_once __DIR__ . '/db_connect.php';

$sql = "SELECT avatar_animal FROM salesmen WHERE avatar_animal IS NOT NULL AND avatar_animal != ''";
$result = $conn->query($sql);

$taken_animals = [];
if ($result && $result->num_rows > 0) {
    while ($row = $result->fetch_assoc()) {
        $taken_animals[] = $row['avatar_animal'];
    }
}

echo json_encode([
    "status" => "success",
    "taken_animals" => $taken_animals
]);

$conn->close();
?>

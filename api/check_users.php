<?php
require_once 'db_connect.php';

$ids = ["SM002", "SM008"];
foreach ($ids as $id) {
    $sql = "SELECT salesman_id, name, allow_late_entry, custom_late_cutoff FROM salesmen WHERE salesman_id = '$id'";
    $res = $conn->query($sql);
    if ($res && $res->num_rows > 0) {
        $row = $res->fetch_assoc();
        echo "ID: " . $row['salesman_id'] . " | Name: " . $row['name'] . " | Allow Late: " . $row['allow_late_entry'] . " | Cutoff: " . ($row['custom_late_cutoff'] ?? 'Default (10:00:59)') . "\n";
    } else {
        echo "ID: $id not found\n";
    }
}
?>
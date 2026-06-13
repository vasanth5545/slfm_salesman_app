<?php
// slfm_api/billing_counter/mark_notifications_seen.php

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

$db_found = false;
$possible_paths = [
    __DIR__ . '/../db_connect.php', 
    __DIR__ . '/db_connect.php'     
];
foreach ($possible_paths as $path) {
    if (file_exists($path)) {
        require $path;
        $db_found = true;
        break;
    }
}
if (!$db_found) {
    http_response_code(500);
    echo json_encode(["status" => "error", "message" => "Critical: db_connect.php not found."]);
    exit;
}

$ids_input = $_POST['ids'] ?? '';

if (empty($ids_input)) {
    echo json_encode(["status" => "error", "message" => "No IDs provided"]);
    exit;
}

$ids_array = json_decode($ids_input, true);

if (is_array($ids_array) && count($ids_array) > 0) {
    // Sanitize IDs
    $safe_ids = array_map('intval', $ids_array);
    $ids_string = implode(',', $safe_ids);
    
    // Database-la seen status-a update pandrom
    $sql = "UPDATE attendance SET is_seen_by_admin = 1 WHERE id IN ($ids_string)";
    if ($conn->query($sql) === TRUE) {
        echo json_encode(["status" => "success", "message" => "Marked as seen on server"]);
    } else {
        echo json_encode(["status" => "error", "message" => "DB Error: " . $conn->error]);
    }
} else {
    echo json_encode(["status" => "error", "message" => "Invalid IDs format"]);
}

$conn->close();
?>
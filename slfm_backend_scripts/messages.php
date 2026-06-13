<?php
// slfm_backend_scripts/messages.php
error_reporting(E_ERROR | E_PARSE);
ini_set('display_errors', 0);
header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");

$db_path = __DIR__ . '/db_connect.php';
if (file_exists($db_path)) {
    require_once $db_path;
} else {
    echo json_encode(["status" => "error", "message" => "db_connect.php not found"]);
    exit;
}

$json_data = json_decode(file_get_contents('php://input'), true);
$action = $_GET['action'] ?? $json_data['action'] ?? $_POST['action'] ?? '';
$salesman_id = $_GET['salesman_id'] ?? $json_data['salesman_id'] ?? $_POST['salesman_id'] ?? '';

if (empty($salesman_id)) {
    echo json_encode(["status" => "error", "message" => "Salesman ID is required"]);
    exit;
}

// Ensure the messages table exists
$table_check = $conn->query("SHOW TABLES LIKE 'messages'");
if ($table_check->num_rows == 0) {
    $create_sql = "
    CREATE TABLE messages (
        id INT AUTO_INCREMENT PRIMARY KEY,
        salesman_id VARCHAR(50) NOT NULL,
        message_text TEXT,
        message_type VARCHAR(50) NOT NULL,
        status VARCHAR(20) DEFAULT 'delivered',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )";
    $conn->query($create_sql);
}

if ($action == 'sync_messages') {
    $last_id = isset($_GET['last_id']) ? (int)$_GET['last_id'] : (isset($json_data['last_id']) ? (int)$json_data['last_id'] : 0);
    $sql = "SELECT * FROM messages WHERE salesman_id = '$salesman_id' AND id > $last_id ORDER BY id ASC";
    $result = $conn->query($sql);
    
    $messages = [];
    if ($result) {
        while($row = $result->fetch_assoc()) {
            $messages[] = $row;
        }
    }
    echo json_encode(["status" => "success", "data" => $messages]);
    exit;
}
elseif ($action == 'send_message') {
    $message_text = $conn->real_escape_string($json_data['message_text'] ?? $_POST['message_text'] ?? '');
    $message_type = $conn->real_escape_string($json_data['message_type'] ?? $_POST['message_type'] ?? 'leave_request');
    $created_at = $conn->real_escape_string($json_data['created_at'] ?? $_POST['created_at'] ?? date('Y-m-d H:i:s')); // allow offline timestamp

    $sql = "INSERT INTO messages (salesman_id, message_text, message_type, status, created_at) 
            VALUES ('$salesman_id', '$message_text', '$message_type', 'sent', '$created_at')";
    
    if ($conn->query($sql) === TRUE) {
        $insert_id = $conn->insert_id;
        echo json_encode([
            "status" => "success", 
            "id" => $insert_id,
            "message" => "Message sent successfully"
        ]);
    } else {
        echo json_encode(["status" => "error", "message" => $conn->error]);
    }
    exit;
} else {
    echo json_encode(["status" => "error", "message" => "Invalid action"]);
}
?>

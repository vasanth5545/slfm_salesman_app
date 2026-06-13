<?php
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Content-Type: application/json; charset=UTF-8");

error_reporting(0);

// 🔥 FIX: Reverted to 'localhost'. '127.0.0.1' is strictly blocked by Hostinger/cPanel firewalls.
if (file_exists(__DIR__ . '/db_config.php')) {
    // Local / Production Server load
    require __DIR__ . '/db_config.php';
} else {
    // Dummy credentials for Public GitHub display
    $servername = "localhost";
    $username = "dummy_user";
    $password = "dummy_password";
    $dbname = "dummy_db";
}

// 🚀 AUTO-RETRY LOGIC: Server busy aaga irunthal udane error tharamal 3 murai try seiyum.
$max_retries = 3;
$retry_count = 0;
$connected = false;
$last_error = "";

while ($retry_count < $max_retries && !$connected) {
    try {
        // 1. PDO Connection
        $pdo = new PDO("mysql:host=$servername;dbname=$dbname;charset=utf8mb4", $username, $password);
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
        $pdo->exec("SET time_zone = '+05:30'");

        // 2. MySQLi Connection
        $conn = @new mysqli($servername, $username, $password, $dbname);
        if (!$conn->connect_error) {
            $conn->set_charset("utf8mb4");
            $conn->query("SET time_zone = '+05:30'");
        }

        $connected = true; // Connection Success
    } catch (Exception $e) {
        $last_error = $e->getMessage();
        $retry_count++;
        usleep(500000); // Wait for 0.5 seconds before retrying
    }
}

// 3 times try panniyum connect aagalana mattum error kaattum
if (!$connected) {
    die(json_encode([
        "success" => false,
        "status" => "error",
        "message" => "Database Server Busy: " . $last_error
    ]));
}

// 3. Helper Functions required by the billing system API scripts
if (!function_exists('getJsonInput')) {
    function getJsonInput()
    {
        return json_decode(file_get_contents("php://input"), true);
    }
}

if (!function_exists('sendSuccess')) {
    function sendSuccess($data = [])
    {
        echo json_encode(array_merge(["success" => true], $data));
        exit();
    }
}

if (!function_exists('sendError')) {
    function sendError($message, $code = 400)
    {
        http_response_code($code);
        echo json_encode(["success" => false, "message" => $message]);
        exit();
    }
}
?>
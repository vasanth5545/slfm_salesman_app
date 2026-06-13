<?php
header('Content-Type: application/json');
header("Cache-Control: no-cache, no-store, must-revalidate"); // 🔥 Prevent Caching
header("Pragma: no-cache");
header("Expires: 0");

// 🔥 DEBUG LOG: See if the app is even hitting the server
$log_file = __DIR__ . '/version_check_log.txt';
$log_data = date('Y-m-d H:i:s') . " - IP: " . $_SERVER['REMOTE_ADDR'] . " - ID: " . ($_GET['salesman_id'] ?? 'N/A') . " - VER: " . ($_GET['current_version'] ?? 'N/A') . "\n";
file_put_contents($log_file, $log_data, FILE_APPEND);

// require_once 'db_connect.php'; 
// 🔥 REMOVED DB DEPENDENCY FOR GLOBAL UPDATES TO PREVENT TIMEOUTS/ERRORS

// Path to the version config file
$json_path = __DIR__ . '/apps/salesman/salesman_version.json';

if (!file_exists($json_path)) {
    http_response_code(404);
    echo json_encode(["status" => "error", "message" => "Version config not found at " . $json_path]);
    exit;
}

$json_content = file_get_contents($json_path);
if ($json_content === false) {
    echo json_encode(["status" => "error", "message" => "Failed to read version file"]);
    exit;
}

$config = json_decode($json_content, true);
if ($config === null) {
    echo json_encode(["status" => "error", "message" => "JSON decode failed"]);
    exit;
}

// 🔥 Ensure mandatory fields exist for Flutter logic
if (!isset($config['target_showrooms'])) $config['target_showrooms'] = [];
if (!isset($config['is_global'])) $config['is_global'] = true;

$salesman_id = isset($_GET['salesman_id']) ? $_GET['salesman_id'] : '';
$current_version = isset($_GET['current_version']) ? $_GET['current_version'] : '';
$abi = isset($_GET['abi']) ? $_GET['abi'] : 'unknown'; // 🔥 Architecture detection

// 🚀 ARCHITECTURE LOGIC: Deciding the correct filename
$base_download_url = "https://skyblue-raven-196549.hostingersite.com/api/apps/salesman/";

if ($abi == 'unknown') {
    // Detect for OLD apps using User-Agent
    $user_agent = $_SERVER['HTTP_USER_AGENT'];
    if (strpos($user_agent, 'arm64') !== false || strpos($user_agent, 'aarch64') !== false) {
        $apk_name = "slfm_attendance_v8a.apk";
    } else {
        $apk_name = "slfm_attendance_v7a.apk";
    }
} else {
    // Detect for NEW apps using explicit parameter
    $apk_name = ($abi == 'armeabi-v7a') ? "slfm_attendance_v7a.apk" : "slfm_attendance_v8a.apk";
}

$config['download_url'] = $base_download_url . $apk_name;

// Default response is the server config
$response_config = $config;

// Logic to decide if update should be shown
$show_update = false;

if (!empty($config['is_global']) || empty($config['target_showrooms'])) {
    // 1. GLOBAL UPDATE or NO SPECIFIC SHOWROOMS: Everyone sees it
    $show_update = true;
} 
/*
elseif (!empty($salesman_id)) {
    // 2. TARGETED UPDATE: Check salesman's showroom
    $stmt = $conn->prepare("SELECT showroom_name FROM salesmen WHERE salesman_id = ?");
    $stmt->bind_param("s", $salesman_id);
    $stmt->execute();
    $result = $stmt->get_result();

    if ($row = $result->fetch_assoc()) {
        $user_showroom = $row['showroom_name'];
        if (in_array($user_showroom, $config['target_showrooms'])) {
            $show_update = true;
        }
    }
}
*/

// 3. APPLY FILTER
if (!$show_update) {
    // NOT TARGETED: "Hide" the update by returning build_number 0
    if (!empty($current_version)) {
        $response_config['version'] = $current_version;
    } else {
        $response_config['version'] = "0.0.0";
    }
    $response_config['build_number'] = 0;
}

// Final data type enforcement for mobile app
$response_config['mandatory'] = (bool) ($response_config['mandatory'] ?? false);
$response_config['is_global'] = (bool) ($response_config['is_global'] ?? false);

echo json_encode($response_config, JSON_UNESCAPED_SLASHES);
?>
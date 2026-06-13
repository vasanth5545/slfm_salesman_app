<?php
// api/update_remote_attendance.php
// BRIDGE: MySQL → Firebase RTDB
// When admin enables/disables Remote Attendance:
//   1. Updates MySQL `salesmen.remote_attendance_enabled`
//   2. Writes to Firebase RTDB `/attendance_settings/{salesman_id}/remote_attendance_enabled` for real-time app UI update

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

date_default_timezone_set('Asia/Kolkata');
require 'db_connect.php';

// ============================================================
// 🔥 FIREBASE RTDB CONFIGURATION
// ============================================================
$FIREBASE_RTDB_URL = "https://admin-decd9-default-rtdb.asia-southeast1.firebasedatabase.app";
$FIREBASE_DB_SECRET = "y9O4hN0n1Od4HuPf8co9uaRT2t750HUOYnhTaJJ3";

// Parse Input
$json_data = json_decode(file_get_contents('php://input'), true);
$salesman_id = $json_data['salesman_id'] ?? trim($_POST['salesman_id'] ?? '');
$is_enabled = isset($json_data['is_enabled']) ? (bool) $json_data['is_enabled'] : (isset($_POST['is_enabled']) ? filter_var($_POST['is_enabled'], FILTER_VALIDATE_BOOLEAN) : null);

if (empty($salesman_id) || $is_enabled === null) {
    echo json_encode(["status" => "error", "message" => "salesman_id and is_enabled are required"]);
    exit;
}

$safe_id = $conn->real_escape_string($salesman_id);
$mysql_val = $is_enabled ? 1 : 0;

// ============================================================
// STEP 1: UPDATE MySQL
// ============================================================
// Make sure you run: ALTER TABLE salesmen ADD COLUMN remote_attendance_enabled BOOLEAN DEFAULT FALSE;
$sql = "UPDATE salesmen SET remote_attendance_enabled = $mysql_val WHERE salesman_id = '$safe_id'";
$mysql_success = false;

if ($conn->query($sql) === TRUE) {
    if ($conn->affected_rows > 0 || $conn->info != "") {
        $mysql_success = true;
    } else {
        echo json_encode(["status" => "error", "message" => "Salesman not found: $salesman_id"]);
        exit;
    }
} else {
    echo json_encode(["status" => "error", "message" => "MySQL Error: " . $conn->error]);
    exit;
}

// ============================================================
// STEP 2: WRITE TO FIREBASE RTDB (Real-time UI Push)
// ============================================================
$rtdb_success = false;
$rtdb_error = "";

// We use PUT specifically on the node to avoid overwriting anything else.
// RTDB structure: /salesmen_status/SM008/remote_attendance_enabled = true/false
$rtdb_path = "/salesmen_status/" . urlencode($salesman_id) . "/remote_attendance_enabled.json";
$rtdb_full_url = $FIREBASE_RTDB_URL . $rtdb_path . "?auth=" . $FIREBASE_DB_SECRET;

// Firebase interprets literal strings "true" or "false" if not careful. Json_encode handles proper boolean.
$rtdb_data = json_encode($is_enabled);

$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, $rtdb_full_url);
curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "PUT");
curl_setopt($ch, CURLOPT_POSTFIELDS, $rtdb_data);
curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_TIMEOUT, 10);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true);

$response = curl_exec($ch);
$http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$curl_error = curl_error($ch);

if ($http_code == 200) {
    $rtdb_success = true;
} else {
    $rtdb_error = "RTDB Write Failed (HTTP $http_code): $curl_error | Response: $response";
}

echo json_encode([
    "status" => "success",
    "message" => "Remote Attendance for $salesman_id set to " . ($is_enabled ? "ON" : "OFF"),
    "mysql_updated" => $mysql_success,
    "rtdb_updated" => $rtdb_success,
    "rtdb_error" => $rtdb_error ?: null
]);

$conn->close();
?>
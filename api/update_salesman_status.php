<?php
// api/update_salesman_status.php
// KILL-SWITCH BRIDGE: MySQL → Firebase RTDB
// When admin suspends/activates a salesman:
//   1. Updates MySQL `salesmen.status`
//   2. Writes to Firebase RTDB `/salesmen_status/{salesman_id}` for real-time push
// The Flutter app listens to RTDB and auto-logouts on suspension.

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
// RTDB URL from firebase_options.dart
$FIREBASE_RTDB_URL = "https://admin-decd9-default-rtdb.asia-southeast1.firebasedatabase.app";

// 🔑 DATABASE SECRET: Get from Firebase Console → Project Settings → Service accounts → Database secrets
$FIREBASE_DB_SECRET = "y9O4hN0n1Od4HuPf8co9uaRT2t750HUOYnhTaJJ3";
// ============================================================

$json_data = json_decode(file_get_contents('php://input'), true);
$salesman_id = $json_data['salesman_id'] ?? $_POST['salesman_id'] ?? '';
$new_status = $json_data['status'] ?? $_POST['status'] ?? ''; // 'Active' or 'Suspended'
$admin_key = $json_data['admin_key'] ?? $_POST['admin_key'] ?? '';

// Basic Validation
if (empty($salesman_id) || empty($new_status)) {
    echo json_encode(["status" => "error", "message" => "salesman_id and status required"]);
    exit;
}

// Validate status value
$new_status = ucfirst(strtolower($new_status));
if (!in_array($new_status, ['Active', 'Suspended'])) {
    echo json_encode(["status" => "error", "message" => "status must be 'Active' or 'Suspended'"]);
    exit;
}

$safe_id = trim($conn->real_escape_string($salesman_id));
$status_input = trim($new_status);

// Normalize status: Always store as 'Active' or 'Suspended'
$normalized_status = ucfirst(strtolower($status_input));

// ============================================================
// STEP 1: UPDATE MySQL
// ============================================================
if ($normalized_status === 'Suspended') {
    $relieving_date = date('Y-m-d');
    $sql = "UPDATE salesmen SET status = '$normalized_status', relieving_date = '$relieving_date' WHERE salesman_id = '$safe_id'";
} else {
    $sql = "UPDATE salesmen SET status = '$normalized_status', relieving_date = NULL WHERE salesman_id = '$safe_id'";
}
$mysql_success = false;

if ($conn->query($sql) === TRUE) {
    if ($conn->affected_rows > 0) {
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
// STEP 2: WRITE TO FIREBASE RTDB (Real-time Kill-Switch)
// ============================================================
$rtdb_success = false;
$rtdb_error = "";

// Build RTDB URL:  /salesmen_status/{salesman_id}.json?auth={secret}
$rtdb_path = "/salesmen_status/" . urlencode($salesman_id) . ".json";
$rtdb_full_url = $FIREBASE_RTDB_URL . $rtdb_path . "?auth=" . $FIREBASE_DB_SECRET;

// Data to write
$rtdb_data = json_encode([
    "status" => $normalized_status,
    "updated_at" => round(microtime(true) * 1000), // millisecond timestamp
    "updated_by" => "admin_panel"
]);

// Use cURL for PATCH request to update only specific fields
$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, $rtdb_full_url);
curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "PATCH");
curl_setopt($ch, CURLOPT_POSTFIELDS, $rtdb_data);
curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_TIMEOUT, 10);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);

$response = curl_exec($ch);
$http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$curl_error = curl_error($ch);
curl_close($ch);

if ($http_code == 200 && !empty($response)) {
    $rtdb_success = true;
} else {
    $rtdb_error = "RTDB Write Failed (HTTP $http_code): $curl_error | Response: $response";
}

// ============================================================
// RESPONSE
// ============================================================
echo json_encode([
    "status" => "success",
    "message" => "Salesman $salesman_id status changed to $new_status",
    "mysql_updated" => $mysql_success,
    "rtdb_updated" => $rtdb_success,
    "rtdb_error" => $rtdb_error ?: null,
    "timestamp" => date('Y-m-d H:i:s')
]);

$conn->close();
?>
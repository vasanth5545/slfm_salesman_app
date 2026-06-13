<?php
// FILE PATH: Hostinger /api/upload_image.php
ini_set('memory_limit', '256M'); // Handle Large Base64 Payloads
header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

$input = file_get_contents('php://input');
$data = json_decode($input, true);

if (!$data) {
    echo json_encode(['status' => 'error', 'message' => 'Invalid JSON input or Payload too large']);
    exit;
}

// 🔥 SECURITY FIX: Secret Key Check
// Firebase Cloud Function-ல் இருந்து வரும் secret_key-ஐ சரிபார்க்கிறது. 
// இது தவறாக இருந்தால், வேறு யாரும் போலியாக அப்லோட் செய்ய முடியாது!
$secret_key = isset($data['secret_key']) ? $data['secret_key'] : '';
if ($secret_key !== 'Rajendran_Vasanthvarman_White_Fire_Team_@_SLFM_Team_CEO') {
    http_response_code(403); // Forbidden status code
    echo json_encode(['status' => 'error', 'message' => 'Unauthorized Access! Fake Upload Blocked!']);
    exit;
}
// ---------------------------------------------------------

$base64 = $data['image'] ?? '';
$showroom = $data['showroom'] ?? 'Main Branch';
$filename = $data['filename'] ?? 'image_' . time() . '.jpg';
$date = $data['date'] ?? date('Y-m-d');

if(empty($base64)) {
    echo json_encode(['status' => 'error', 'message' => 'No image data received']);
    exit;
}

// Base64 Cleaning
if (strpos($base64, ',') !== false) {
    $parts = explode(',', $base64);
    $base64 = $parts[1];
}
$base64 = str_replace(' ', '+', $base64);

// 🔥 Directory Creation - Added 'attendance' folder as requested
$safe_showroom = preg_replace('/[^A-Za-z0-9\-]/', '_', $showroom);
$dir = "firebase_photo_uploads/attendance/$safe_showroom/$date/";

if (!is_dir($dir)) {
    mkdir($dir, 0777, true);
}

$filepath = $dir . $filename;
$decoded_image = base64_decode($base64);

if ($decoded_image === false) {
    echo json_encode(['status' => 'error', 'message' => 'Base64 decode failed.']);
    exit;
}

if (file_put_contents($filepath, $decoded_image)) {
    echo json_encode(['status' => 'success', 'path' => $filepath]);
} else {
    echo json_encode(['status' => 'error', 'message' => 'Failed to write file to disk. Check folder permissions.']);
}
?>
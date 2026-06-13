<?php
// FILE: api/save_walking_bill.php
// PURPOSE: Upload walking customer bill photos
// STORAGE PATH: firebase_photo_uploads/bills/{date}/
// OLD PATH (legacy): api/uploads/bills/
// FILENAME FORMAT: salesman_name_salesman_id_yyyy_mm_dd_random.jpg

error_reporting(0);
ini_set('display_errors', 0);

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST");
header("Access-Control-Allow-Headers: Content-Type");

// 🔥 Set Timezone
date_default_timezone_set('Asia/Kolkata');

// --- HELPER: Image Compression ---
function compressImage($source, $destination, $quality) {
    $info = getimagesize($source);
    if (!$info) return false;

    if ($info['mime'] == 'image/jpeg')
        $image = imagecreatefromjpeg($source);
    elseif ($info['mime'] == 'image/png')
        $image = imagecreatefrompng($source);
    else
        return false;

    imagejpeg($image, $destination, $quality);
    imagedestroy($image);
    return true;
}

// Only accept POST
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo json_encode(["status" => "error", "message" => "POST method required"]);
    exit;
}

// Get filename from form data
$filename = $_POST['filename'] ?? '';

if (empty($filename)) {
    echo json_encode(["status" => "error", "message" => "Filename is required"]);
    exit;
}

// Check if image file was uploaded
if (!isset($_FILES['image']) || $_FILES['image']['error'] !== UPLOAD_ERR_OK) {
    echo json_encode(["status" => "error", "message" => "Image upload failed"]);
    exit;
}

// 🔥 Security: Validate MIME type
$finfo = new finfo(FILEINFO_MIME_TYPE);
$mime_type = $finfo->file($_FILES['image']['tmp_name']);

if ($mime_type !== 'image/jpeg' && $mime_type !== 'image/png') {
    echo json_encode(["status" => "error", "message" => "Security Alert: Invalid image format"]);
    exit;
}

// 🔥 NEW PATH: firebase_photo_uploads/bills/{date}/
$today_date = date('Y-m-d');
$upload_dir = "firebase_photo_uploads/bills/$today_date/";

if (!is_dir($upload_dir)) {
    mkdir($upload_dir, 0777, true);
}

// Sanitize filename (remove any dangerous characters)
$safe_filename = preg_replace('/[^a-zA-Z0-9_\-\.]/', '_', $filename);

// Ensure .jpg extension
if (!preg_match('/\.jpg$/i', $safe_filename)) {
    $safe_filename .= '.jpg';
}

$filepath = $upload_dir . $safe_filename;

// Move uploaded file
if (!move_uploaded_file($_FILES['image']['tmp_name'], $filepath)) {
    echo json_encode(["status" => "error", "message" => "Failed to save file"]);
    exit;
}

// 🔥 Compress image (Quality: 60 - good balance of size/quality)
compressImage($filepath, $filepath, 60);

// 🔥 Return the relative path as image_url
// This will be stored in Firebase as bill_photo
echo json_encode([
    "status" => "success",
    "message" => "Bill photo uploaded successfully",
    "image_url" => $filepath
]);
?>

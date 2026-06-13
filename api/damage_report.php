<?php
// slfm_backend_scripts/damage_report.php
// Handles Damage Reports with Multiple Image Uploads
// UPDATED: Added Image Compression (Quality 60) + Auto-Schema Fix

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *"); // Fix CORS if needed
date_default_timezone_set('Asia/Kolkata');

// 1. DB Connect (adjusted path check)
$db_path = __DIR__ . '/db_connect.php';
if (file_exists($db_path)) {
    require_once $db_path;
} else {
    http_response_code(500);
    echo json_encode(["status" => "error", "message" => "db_connect.php not found"]);
    exit;
}

// Check for POST request
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo json_encode(["status" => "error", "message" => "Only POST allowed"]);
    exit;
}

// --- HELPER: Image Compression Function ---
function compressImage($source, $destination, $quality) {
    // Check GD Library
    if (!extension_loaded('gd')) {
        return false; // Cannot compress, return false (will save original)
    }

    $info = getimagesize($source);
    if ($info['mime'] == 'image/jpeg') 
        $image = imagecreatefromjpeg($source);
    elseif ($info['mime'] == 'image/png') 
        $image = imagecreatefrompng($source);
    else 
        return false;

    // Save compressed image
    imagejpeg($image, $destination, $quality); // Converts PNG to JPG (smaller) or keeps JPG
    imagedestroy($image);
    return true;
}

$action = $_POST['action'] ?? '';

if ($action == 'report_damage') {
    
    // 🔥 AUTO-SCHEMA FIX: Ensure table exists with correct column 'images'
    // Previous version used 'image_urls', user's new version uses 'images'
    $conn->query("CREATE TABLE IF NOT EXISTS damage_reports (
        id INT AUTO_INCREMENT PRIMARY KEY,
        salesman_id VARCHAR(50) NOT NULL,
        os_code VARCHAR(50),
        brand VARCHAR(100),
        model VARCHAR(100),
        rate VARCHAR(50),
        description TEXT,
        images TEXT, 
        status VARCHAR(20) DEFAULT 'Pending',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    // Check if 'images' column exists (migration check)
    $col_check = $conn->query("SHOW COLUMNS FROM damage_reports LIKE 'images'");
    if ($col_check && $col_check->num_rows == 0) {
        $conn->query("ALTER TABLE damage_reports ADD COLUMN images TEXT AFTER description");
    }

    $salesman_id = $_POST['salesman_id'] ?? '';
    $os_code = $_POST['os_code'] ?? '';
    $brand = $_POST['brand'] ?? '';
    $model = $_POST['model'] ?? '';
    $rate = $_POST['rate'] ?? '';
    $description = $_POST['description'] ?? '';

    // Validation
    if (empty($salesman_id) || empty($os_code) || empty($description)) {
        echo json_encode(["status" => "error", "message" => "Required fields missing"]);
        exit;
    }

    // 1. Create Upload Directory
    $upload_dir = 'uploads/damage_reports/';
    if (!is_dir("uploads")) { @mkdir("uploads", 0777, true); }
    if (!is_dir($upload_dir)) {
        mkdir($upload_dir, 0777, true);
    }

    // 2. Handle Image Uploads (Max 3)
    $uploaded_images = [];
    $errors = [];

    // Loop through possible keys: image_0, image_1, image_2
    for ($i = 0; $i < 3; $i++) {
        $key = "image_$i";
        if (isset($_FILES[$key]) && $_FILES[$key]['error'] === UPLOAD_ERR_OK) {
            $tmp_name = $_FILES[$key]['tmp_name'];
            $name = basename($_FILES[$key]['name']);
            $ext = strtolower(pathinfo($name, PATHINFO_EXTENSION));
            
            // Allow only specific types
            if (!in_array($ext, ['jpg', 'jpeg', 'png', 'webp'])) {
                continue; 
            }

            // Generate Unique Name: DMG_SalesID_Time_Index.jpg
            $safe_os = preg_replace('/[^A-Za-z0-9]/', '', $os_code);
            $new_name = "DMG_{$salesman_id}_{$safe_os}_" . time() . "_$i." . $ext;
            $target_path = $upload_dir . $new_name;

            if (move_uploaded_file($tmp_name, $target_path)) {
                // 🔥 COMPRESSION ADDED HERE (Quality: 60)
                // Try compression, if it fails (no GD), file is already there anyway
                @compressImage($target_path, $target_path, 60);
                
                $uploaded_images[] = $target_path;
            } else {
                $errors[] = "Failed to upload $key";
            }
        }
    }

    // Convert array to comma-separated string for DB (e.g., "path1.jpg,path2.jpg")
    $images_str = implode(',', $uploaded_images);

    // 3. Insert into Database
    $stmt = $conn->prepare("INSERT INTO damage_reports (salesman_id, os_code, brand, model, rate, description, images, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, NOW())");
    $stmt->bind_param("sssssss", $salesman_id, $os_code, $brand, $model, $rate, $description, $images_str);

    if ($stmt->execute()) {
        echo json_encode([
            "status" => "success", 
            "message" => "Report Submitted Successfully",
            "uploaded_count" => count($uploaded_images)
        ]);
    } else {
        echo json_encode(["status" => "error", "message" => "Database Error: " . $stmt->error]);
    }

    $stmt->close();
} else {
    echo json_encode(["status" => "error", "message" => "Invalid Action"]);
}

$conn->close();
?>

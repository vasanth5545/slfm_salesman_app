<?php
// api/lunch.php
// 🍽️ LUNCH TIME MODULE: Handles Lunch In/Out, Status, History
// Separate from attendance.php — Clean module separation.

// 1. Error Reporting
error_reporting(E_ERROR | E_PARSE);
ini_set('display_errors', 0);
ini_set('memory_limit', '256M');

// 2. Headers
header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

// 3. Timezone
date_default_timezone_set('Asia/Kolkata');

// 4. DB Connect
$db_path = __DIR__ . '/db_connect.php';
if (file_exists($db_path)) {
    require_once $db_path;
} else {
    http_response_code(500);
    echo json_encode(["status" => "error", "message" => "db_connect.php not found"]);
    exit;
}

// 5. Get Input
$json_data = json_decode(file_get_contents('php://input'), true);
$action = $json_data['action'] ?? $_POST['action'] ?? '';
$salesman_id = $json_data['salesman_id'] ?? $_POST['salesman_id'] ?? '';

if ($action == 'ping') {
    echo json_encode(["status" => "success", "file" => "lunch.php", "path" => __FILE__]);
    exit;
}

// Base URL for Images
$protocol = isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? "https" : "http";
$host = $_SERVER['HTTP_HOST'];
$script_dir = dirname($_SERVER['PHP_SELF']);
$script_dir = trim($script_dir, '/\\');
$script_dir = str_replace('\\', '/', $script_dir);
$base_url = "$protocol://$host/$script_dir/";

// Validate ID
if (empty($salesman_id)) {
    echo json_encode(["status" => "error", "message" => "Salesman ID is required"]);
    exit;
}

// ---------------------------------------------------------
// GLOBAL TIME VARIABLES
// ---------------------------------------------------------
$capture_time = $json_data['capture_time'] ?? $_POST['capture_time'] ?? '';
$date = date('Y-m-d');
$current_time_str = date('H:i:s');
$current_time_ampm = date('h:i:s A');
$timestamp = date('Y-m-d H:i:s');

if (!empty($capture_time)) {
    $capture_ts = strtotime($capture_time);
    if ($capture_ts !== false) {
        $date = date('Y-m-d', $capture_ts); // 🔥 CRITICAL: Update the date to match capture_time
        $current_time_str = date('H:i:s', $capture_ts);
        $current_time_ampm = date('h:i:s A', $capture_ts);
        $timestamp = date('Y-m-d H:i:s', $capture_ts);
    }
}


// ---------------------------------------------------------
// LUNCH WINDOW CONFIGURATION
// ---------------------------------------------------------
$LUNCH_WINDOW_START = '13:00:00'; // 01:00 PM
$LUNCH_WINDOW_END = '16:00:00'; // 04:00 PM
$LUNCH_MAX_DURATION = 3600;       // 1 hour in seconds

// ---------------------------------------------------------
// HELPER: FETCH SALESMAN DETAILS
// ---------------------------------------------------------
$showroom_name = 'Main Branch';
$salesman_name = $salesman_id;

$salesman_sql = "SELECT showroom_name, name FROM salesmen WHERE salesman_id = '" . $conn->real_escape_string($salesman_id) . "'";
$salesman_res = $conn->query($salesman_sql);
if ($salesman_res && $salesman_res->num_rows > 0) {
    $s_row = $salesman_res->fetch_assoc();
    $showroom_name = !empty($s_row['showroom_name']) ? $s_row['showroom_name'] : 'Main Branch';
    $salesman_name = $s_row['name'] ?? $salesman_id;
}

// ---------------------------------------------------------
// HELPER: SANITIZE URL
// ---------------------------------------------------------
function sanitizeLunchUrl($url)
{
    if (empty($url))
        return "";
    $url = str_replace('\\', '/', $url);
    $url = str_replace(' ', '%20', $url);
    return $url;
}

// ---------------------------------------------------------
// HELPER: COOLDOWN CHECK (5 MINUTES) ⏳
// Prevents duplicate submissions within 5 minutes of a REAL user action.
// Does NOT block if the record was auto-marked (Absent by cron).
// ---------------------------------------------------------
function enforceSmartCooldown($conn, $salesman_id)
{
    $date = date('Y-m-d');
    $last_time = 0;
    $current_img = "";

    // Cross-table check removed to allow independent module actions.
    // 2. Check Lunch Table
    $lunch_sql = "SELECT updated_at, lunch_in_selfie_url, lunch_out_selfie_url FROM lunch_attendance WHERE salesman_id = '$salesman_id' AND date = '$date'";
    $lunch_res = $conn->query($lunch_sql);
    if ($lunch_res && $lunch_res->num_rows > 0) {
        $row = $lunch_res->fetch_assoc();
        if (!empty($row['updated_at'])) {
            $lunch_time = strtotime($row['updated_at']);
            if ($lunch_time > $last_time)
                $last_time = $lunch_time;
        }
        $current_img = $row['lunch_in_selfie_url'];
        if (!empty($row['lunch_out_selfie_url'])) {
            $current_img = $row['lunch_out_selfie_url'];
        }
    }

    // 3. Block if within 5 mins
    if ($last_time > 0) {
        $diff = time() - $last_time;
        if ($diff < 120) { // 120 seconds = 2 minutes
            // 🔥 SMART BLOCK: Send 'error' containing 'already' so old app deletes duplicate
            // but INCLUDES the image_url so the UI doesn't ghost!
            echo json_encode([
                "status" => "error",
                "message" => "Already processed. Please wait 2 minutes.",
                "image_url" => $current_img,
                "data" => [
                    "image_url" => $current_img
                ]
            ]);
            exit;
        }
    }
}

// ---------------------------------------------------------
// HELPER: IMAGE WATERMARK (Same as attendance.php)
// ---------------------------------------------------------
function applyLunchWatermark($imageData, $salesmanName, $showroomName, $timeText)
{
    if (!extension_loaded('gd'))
        return $imageData;

    $im = @imagecreatefromstring($imageData);
    if ($im) {
        $width = imagesx($im);
        $height = imagesy($im);
        $white = imagecolorallocate($im, 255, 255, 255);
        $bg_color = imagecolorallocatealpha($im, 0, 0, 0, 60);
        $font = 5;

        if ($salesmanName) {
            $len = strlen($salesmanName) * imagefontwidth($font);
            imagefilledrectangle($im, 5, 5, 10 + $len, 25, $bg_color);
            imagestring($im, $font, 8, 8, $salesmanName, $white);
        }
        if ($showroomName) {
            $len = strlen($showroomName) * imagefontwidth($font);
            imagefilledrectangle($im, 5, $height - 25, 10 + $len, $height - 5, $bg_color);
            imagestring($im, $font, 8, $height - 22, $showroomName, $white);
        }
        if ($timeText) {
            $len = strlen($timeText) * imagefontwidth($font);
            imagefilledrectangle($im, $width - $len - 10, $height - 25, $width - 5, $height - 5, $bg_color);
            imagestring($im, $font, $width - $len - 7, $height - 22, $timeText, $white);
        }
        ob_start();
        imagejpeg($im, null, 80);
        $data = ob_get_clean();
        return $data;
    }
    return $imageData;
}

// ---------------------------------------------------------
// AUTO-CREATE TABLE IF NOT EXISTS
// ---------------------------------------------------------
$create_table_sql = "CREATE TABLE IF NOT EXISTS `lunch_attendance` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `salesman_id` VARCHAR(50) NOT NULL,
    `salesman_name` VARCHAR(100) NOT NULL,
    `showroom_name` VARCHAR(100) DEFAULT NULL,
    `date` DATE NOT NULL,
    `lunch_in_time` DATETIME DEFAULT NULL,
    `lunch_out_time` DATETIME DEFAULT NULL,
    `lunch_in_selfie_url` TEXT DEFAULT NULL,
    `lunch_out_selfie_url` TEXT DEFAULT NULL,
    `in_latitude` DECIMAL(10, 8) DEFAULT NULL,
    `in_longitude` DECIMAL(11, 8) DEFAULT NULL,
    `out_latitude` DECIMAL(10, 8) DEFAULT NULL,
    `out_longitude` DECIMAL(11, 8) DEFAULT NULL,
    `extra_break_time` INT DEFAULT 0 COMMENT 'Extra seconds beyond 1 hour',
    `duration_seconds` INT DEFAULT 0 COMMENT 'Total lunch duration in seconds',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `unique_lunch_per_day` (`salesman_id`, `date`),
    INDEX `idx_date` (`date`),
    INDEX `idx_salesman` (`salesman_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;";
$conn->query($create_table_sql);

// Add location columns if they do not exist
$check_cols = $conn->query("SHOW COLUMNS FROM `lunch_attendance` LIKE 'in_latitude'");
if ($check_cols && $check_cols->num_rows == 0) {
    $conn->query("ALTER TABLE `lunch_attendance` 
        ADD `in_latitude` DECIMAL(10,8) DEFAULT NULL,
        ADD `in_longitude` DECIMAL(11,8) DEFAULT NULL,
        ADD `out_latitude` DECIMAL(10,8) DEFAULT NULL,
        ADD `out_longitude` DECIMAL(11,8) DEFAULT NULL");
}

// =========================================================
// ACTION: LUNCH IN
// =========================================================
if ($action == 'lunch_in') {
    // 🔥 SMART COOLDOWN: Prevents 5-min duplicate abuse but returns existing image to prevent UI ghosting
    enforceSmartCooldown($conn, $salesman_id);

    // 1. Fetch Lunch Window Status from Firebase
    // 🛡️ SECURITY: Database Secret is required for server-side REST calls
    $auth_secret = "y9O4hN0n1Od4HuPf8co9uaRT2t750HUOYnhTaJJ3";
    $firebase_url = "https://admin-decd9-default-rtdb.asia-southeast1.firebasedatabase.app/settings/lunch_window.json?auth=" . $auth_secret;
    $ch = curl_init($firebase_url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 5);
    $resp = curl_exec($ch);

    $fb_data = json_decode($resp, true) ?: [];
    $is_manual_open = isset($fb_data['is_open']) ? (bool) $fb_data['is_open'] : false;
    $fb_start = $fb_data['start_time'] ?? '13:00';
    $fb_end = $fb_data['end_time'] ?? '16:00';

    // 2. Validate Lunch Window (Bypass if is_manual_open is true)
    if (!$is_manual_open) {
        $start_with_sec = $fb_start . ":00";
        $end_with_sec = $fb_end . ":00";

        if ($current_time_str < $start_with_sec) {
            echo json_encode([
                "status" => "error",
                "message" => "Lunch period has not started yet. Available from " . date('h:i A', strtotime($start_with_sec)) . "."
            ]);
            exit;
        }
        if ($current_time_str > $end_with_sec) {
            echo json_encode([
                "status" => "error",
                "message" => "Lunch period has ended. It was available until " . date('h:i A', strtotime($end_with_sec)) . "."
            ]);
            exit;
        }
    }

    // 2. Check if already punched in today
    $check_sql = "SELECT id, lunch_in_time, lunch_out_time FROM lunch_attendance 
                  WHERE salesman_id = '" . $conn->real_escape_string($salesman_id) . "' AND date = '$date'";
    $check_res = $conn->query($check_sql);

    if ($check_res && $check_res->num_rows > 0) {
        $existing = $check_res->fetch_assoc();
        if (empty($existing['lunch_out_time']) || $existing['lunch_out_time'] === null) {
            echo json_encode([
                "status" => "error",
                "message" => "You are already on lunch break! Please clock out first."
            ]);
            exit;
        } else {
            echo json_encode([
                "status" => "error",
                "message" => "Lunch already completed for today."
            ]);
            exit;
        }
    }

    // 3. Handle Selfie Image
    $base64_image = $json_data['selfie_url'] ?? $_POST['selfie_url'] ?? '';
    if (empty($base64_image)) {
        echo json_encode(["status" => "error", "message" => "Selfie photo is required to start lunch."]);
        exit;
    }
    $db_image_path = "";

    if (!empty($base64_image)) {
        $safe_showroom = preg_replace('/[^A-Za-z0-9\-]/', '_', $showroom_name);
        $safe_name = preg_replace('/[^A-Za-z0-9\-]/', '_', $salesman_name);

        // Directory: uploads/lunch/{showroom}/{date}/
        $upload_dir = "uploads/lunch/$safe_showroom/$date/";
        if (!is_dir($upload_dir)) {
            @mkdir($upload_dir, 0777, true);
        }

        if (strpos($base64_image, ',') !== false) {
            $parts = explode(',', $base64_image);
            $base64_image = $parts[1];
        }
        $image_data = base64_decode($base64_image);

        if ($image_data !== false) {
            $finfo = new finfo(FILEINFO_MIME_TYPE);
            $mime_type = $finfo->buffer($image_data);
            if ($mime_type == 'image/jpeg' || $mime_type == 'image/png') {
                // Apply Watermark: "LUNCH IN: hh:mm:ss AM/PM"
                $time_text = "LUNCH IN: $current_time_ampm";
                $image_data = applyLunchWatermark($image_data, $salesman_name, $showroom_name, $time_text);

                // Filename: salesmanid_salesmanname_yyyy-mm-dd_hh_mm_ss.jpg
                $filename = $salesman_id . "_" . $safe_name . "_" . date("Y-m-d_H_i_s") . ".jpg";
                $filepath = $upload_dir . $filename;

                if (@file_put_contents($filepath, $image_data)) {
                    $db_image_path = $filepath;
                }
            }
        }
    }

    // 4. Insert Record
    $esc_id = $conn->real_escape_string($salesman_id);
    $esc_name = $conn->real_escape_string($salesman_name);
    $esc_showroom = $conn->real_escape_string($showroom_name);
    $esc_image = $conn->real_escape_string($db_image_path);

    $in_lat = $json_data['latitude'] ?? $_POST['latitude'] ?? 'NULL';
    $in_lng = $json_data['longitude'] ?? $_POST['longitude'] ?? 'NULL';
    $esc_in_lat = ($in_lat !== 'NULL' && is_numeric($in_lat)) ? $in_lat : 'NULL';
    $esc_in_lng = ($in_lng !== 'NULL' && is_numeric($in_lng)) ? $in_lng : 'NULL';

    $insert_sql = "INSERT INTO lunch_attendance 
                   (salesman_id, salesman_name, showroom_name, date, lunch_in_time, lunch_in_selfie_url, in_latitude, in_longitude) 
                   VALUES ('$esc_id', '$esc_name', '$esc_showroom', '$date', '$timestamp', '$esc_image', $esc_in_lat, $esc_in_lng)";

    if ($conn->query($insert_sql) === TRUE) {
        // 🔥 UPDATE FIREBASE RTDB
        $rtdb_url = "https://admin-decd9-default-rtdb.asia-southeast1.firebasedatabase.app/salesmen_status/" . urlencode($salesman_id) . ".json?auth=y9O4hN0n1Od4HuPf8co9uaRT2t750HUOYnhTaJJ3";
        $rtdb_data = json_encode([
            "lunch_status" => "in_progress",
            "lunch_updated_at" => round(microtime(true) * 1000)
        ]);
        $ch_fb = curl_init();
        curl_setopt($ch_fb, CURLOPT_URL, $rtdb_url);
        curl_setopt($ch_fb, CURLOPT_CUSTOMREQUEST, "PATCH");
        curl_setopt($ch_fb, CURLOPT_POSTFIELDS, $rtdb_data);
        curl_setopt($ch_fb, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
        curl_setopt($ch_fb, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch_fb, CURLOPT_TIMEOUT, 5);
        curl_setopt($ch_fb, CURLOPT_SSL_VERIFYPEER, false);
        curl_exec($ch_fb);

        $final_url = $db_image_path ? sanitizeLunchUrl($base_url . $db_image_path) : null;
        echo json_encode([
            "status" => "success",
            "message" => "Lunch break started! Enjoy your meal 🍽️",
            "lunch_in_time" => $current_time_ampm,
            "image_url" => $final_url,
            "selfie_url" => $final_url,
            "lunch_in_selfie_url" => $final_url
        ]);
    } else {
        echo json_encode([
            "status" => "error",
            "message" => "Database error: " . $conn->error
        ]);
    }
    exit;
}

// =========================================================
// ACTION: LUNCH OUT
// =========================================================
if ($action == 'lunch_out') {
    // 🔥 SMART COOLDOWN: Prevents 5-min duplicate abuse but returns existing image to prevent UI ghosting
    enforceSmartCooldown($conn, $salesman_id);

    // 1. Find active lunch record (in today, no out yet)
    $check_sql = "SELECT id, lunch_in_time FROM lunch_attendance 
                  WHERE salesman_id = '" . $conn->real_escape_string($salesman_id) . "' 
                  AND date = '$date' 
                  AND lunch_in_time IS NOT NULL 
                  AND (lunch_out_time IS NULL OR lunch_out_time = '')";
    $check_res = $conn->query($check_sql);

    if (!$check_res || $check_res->num_rows == 0) {
        echo json_encode([
            "status" => "error",
            "message" => "No active lunch break found. Please clock in first."
        ]);
        exit;
    }

    $row = $check_res->fetch_assoc();
    $record_id = $row['id'];
    $lunch_in_ts = strtotime($row['lunch_in_time']);

    // 2. Calculate Duration
    $now_ts = time();
    $duration_seconds = $now_ts - $lunch_in_ts;
    $extra_break = 0;

    if ($duration_seconds > $LUNCH_MAX_DURATION) {
        $extra_break = $duration_seconds - $LUNCH_MAX_DURATION;
    }

    // 3. Handle Out Selfie
    $base64_image = $json_data['selfie_url'] ?? $_POST['selfie_url'] ?? '';
    if (empty($base64_image)) {
        echo json_encode(["status" => "error", "message" => "Selfie photo is required to end lunch."]);
        exit;
    }
    $db_image_path = "";

    if (!empty($base64_image)) {
        $safe_showroom = preg_replace('/[^A-Za-z0-9\-]/', '_', $showroom_name);
        $safe_name = preg_replace('/[^A-Za-z0-9\-]/', '_', $salesman_name);

        $upload_dir = "uploads/lunch/$safe_showroom/$date/";
        if (!is_dir($upload_dir)) {
            @mkdir($upload_dir, 0777, true);
        }

        if (strpos($base64_image, ',') !== false) {
            $parts = explode(',', $base64_image);
            $base64_image = $parts[1];
        }
        $image_data = base64_decode($base64_image);

        if ($image_data !== false) {
            $finfo = new finfo(FILEINFO_MIME_TYPE);
            $mime_type = $finfo->buffer($image_data);
            if ($mime_type == 'image/jpeg' || $mime_type == 'image/png') {
                $time_text = "LUNCH OUT: $current_time_ampm";
                $image_data = applyLunchWatermark($image_data, $salesman_name, $showroom_name, $time_text);

                $filename = $salesman_id . "_" . $safe_name . "_" . date("Y-m-d_H_i_s") . "_OUT.jpg";
                $filepath = $upload_dir . $filename;

                if (@file_put_contents($filepath, $image_data)) {
                    $db_image_path = $filepath;
                }
            }
        }
    }

    // 4. Update Record
    $esc_image = $conn->real_escape_string($db_image_path);

    $out_lat = $json_data['latitude'] ?? $_POST['latitude'] ?? 'NULL';
    $out_lng = $json_data['longitude'] ?? $_POST['longitude'] ?? 'NULL';
    $esc_out_lat = ($out_lat !== 'NULL' && is_numeric($out_lat)) ? $out_lat : 'NULL';
    $esc_out_lng = ($out_lng !== 'NULL' && is_numeric($out_lng)) ? $out_lng : 'NULL';

    $update_sql = "UPDATE lunch_attendance 
                   SET lunch_out_time = '$timestamp', 
                       lunch_out_selfie_url = '$esc_image',
                       duration_seconds = $duration_seconds,
                       extra_break_time = $extra_break,
                       out_latitude = $esc_out_lat,
                       out_longitude = $esc_out_lng
                   WHERE id = $record_id";

    if ($conn->query($update_sql) === TRUE) {
        // 🔥 UPDATE FIREBASE RTDB
        $rtdb_url = "https://admin-decd9-default-rtdb.asia-southeast1.firebasedatabase.app/salesmen_status/" . urlencode($salesman_id) . ".json?auth=y9O4hN0n1Od4HuPf8co9uaRT2t750HUOYnhTaJJ3";
        $rtdb_data = json_encode([
            "lunch_status" => "completed",
            "lunch_updated_at" => round(microtime(true) * 1000)
        ]);
        $ch_fb = curl_init();
        curl_setopt($ch_fb, CURLOPT_URL, $rtdb_url);
        curl_setopt($ch_fb, CURLOPT_CUSTOMREQUEST, "PATCH");
        curl_setopt($ch_fb, CURLOPT_POSTFIELDS, $rtdb_data);
        curl_setopt($ch_fb, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
        curl_setopt($ch_fb, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch_fb, CURLOPT_TIMEOUT, 5);
        curl_setopt($ch_fb, CURLOPT_SSL_VERIFYPEER, false);
        curl_exec($ch_fb);

        $duration_min = floor($duration_seconds / 60);
        $extra_min = floor($extra_break / 60);
        $extra_sec = $extra_break % 60;

        $msg = "Lunch break ended! Duration: {$duration_min} min.";
        if ($extra_break > 0) {
            $msg .= " ⚠️ Extra: +{$extra_min}m {$extra_sec}s beyond limit.";
        }

        $final_url = $db_image_path ? sanitizeLunchUrl($base_url . $db_image_path) : null;
        echo json_encode([
            "status" => "success",
            "message" => $msg,
            "lunch_out_time" => $current_time_ampm,
            "duration_seconds" => $duration_seconds,
            "extra_break_time" => $extra_break,
            "extra_break_display" => $extra_break > 0 ? "+{$extra_min}m" : null,
            "image_url" => $final_url,
            "selfie_url" => $final_url,
            "lunch_out_selfie_url" => $final_url
        ]);
    } else {
        echo json_encode([
            "status" => "error",
            "message" => "Database error: " . $conn->error
        ]);
    }
    exit;
}

// =========================================================
// ACTION: GET LUNCH STATUS (Today's status for Dashboard)
// =========================================================
if ($action == 'get_lunch_status') {

    $esc_id = $conn->real_escape_string($salesman_id);
    $sql = "SELECT * FROM lunch_attendance WHERE salesman_id = '$esc_id' AND date = '$date' LIMIT 1";
    $res = $conn->query($sql);

    if ($res && $res->num_rows > 0) {
        $row = $res->fetch_assoc();

        $lunch_status = 'not_started';
        $extra_display = null;

        if (!empty($row['lunch_in_time']) && (empty($row['lunch_out_time']) || $row['lunch_out_time'] === null)) {
            $lunch_status = 'in_progress';
        } elseif (!empty($row['lunch_in_time']) && !empty($row['lunch_out_time'])) {
            $lunch_status = 'completed';
            $extra = (int) $row['extra_break_time'];
            if ($extra > 0) {
                $extra_min = floor($extra / 60);
                $extra_sec = $extra % 60;
                $extra_display = "+{$extra_min}m";
                if ($extra_sec > 0) {
                    $extra_display .= " {$extra_sec}s";
                }
            }
        }

        // Fetch Firebase Settings for window display
        // 🛡️ SECURITY: Database Secret is required for server-side REST calls
        $auth_secret = "y9O4hN0n1Od4HuPf8co9uaRT2t750HUOYnhTaJJ3";
        $firebase_url = "https://admin-decd9-default-rtdb.asia-southeast1.firebasedatabase.app/settings/lunch_window.json?auth=" . $auth_secret;
        $ch = curl_init($firebase_url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 5);
        $resp = curl_exec($ch);

        $fb_data = json_decode($resp, true) ?: [];
        $fb_start = $fb_data['start_time'] ?? '13:00';
        $fb_end = $fb_data['end_time'] ?? '16:00';

        $in_display = !empty($row['lunch_in_time']) ? date('h:i:s A', strtotime($row['lunch_in_time'])) : null;
        $out_display = !empty($row['lunch_out_time']) ? date('h:i:s A', strtotime($row['lunch_out_time'])) : null;

        echo json_encode([
            "status" => "success",
            "data" => [
                "lunch_status" => $lunch_status,
                "lunch_in_time" => $in_display,
                "lunch_out_time" => $out_display,
                "lunch_in_selfie_url" => !empty($row['lunch_in_selfie_url']) ? sanitizeLunchUrl($base_url . $row['lunch_in_selfie_url']) : null,
                "lunch_out_selfie_url" => !empty($row['lunch_out_selfie_url']) ? sanitizeLunchUrl($base_url . $row['lunch_out_selfie_url']) : null,
                "duration_seconds" => (int) $row['duration_seconds'],
                "extra_break_time" => (int) $row['extra_break_time'],
                "extra_break_display" => $extra_display,
                "lunch_window_start" => date('h:i A', strtotime($fb_start)),
                "lunch_window_end" => date('h:i A', strtotime($fb_end)),
                "in_latitude" => $row['in_latitude'] ?? null,
                "in_longitude" => $row['in_longitude'] ?? null,
                "out_latitude" => $row['out_latitude'] ?? null,
                "out_longitude" => $row['out_longitude'] ?? null
            ]
        ]);
    } else {
        // No record today — check Firebase settings
        // 🛡️ SECURITY: Database Secret is required for server-side REST calls
        $auth_secret = "y9O4hN0n1Od4HuPf8co9uaRT2t750HUOYnhTaJJ3";
        $firebase_url = "https://admin-decd9-default-rtdb.asia-southeast1.firebasedatabase.app/settings/lunch_window.json?auth=" . $auth_secret;
        $ch = curl_init($firebase_url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 5);
        $resp = curl_exec($ch);

        $fb_data = json_decode($resp, true) ?: [];

        $is_manual_open = isset($fb_data['is_open']) ? (bool) $fb_data['is_open'] : false;
        $fb_start = $fb_data['start_time'] ?? '13:00';
        $fb_end = $fb_data['end_time'] ?? '16:00';

        $in_window = $is_manual_open;
        if (!$in_window) {
            $in_window = ($current_time_str >= $fb_start . ":00" && $current_time_str <= $fb_end . ":00");
        }

        echo json_encode([
            "status" => "success",
            "data" => [
                "lunch_status" => "not_started",
                "lunch_in_time" => null,
                "lunch_out_time" => null,
                "lunch_in_selfie_url" => null,
                "lunch_out_selfie_url" => null,
                "duration_seconds" => 0,
                "extra_break_time" => 0,
                "extra_break_display" => null,
                "lunch_window_start" => date('h:i A', strtotime($fb_start)),
                "lunch_window_end" => date('h:i A', strtotime($fb_end)),
                "in_window" => $in_window
            ]
        ]);
    }
    exit;
}

// =========================================================
// ACTION: GET LUNCH HISTORY (Last 40 days for History View)
// =========================================================
if ($action == 'get_lunch_history') {

    $esc_id = $conn->real_escape_string($salesman_id);

    // Check for month and year filters
    $filter_month = $json_data['month'] ?? $_POST['month'] ?? '';
    $filter_year = $json_data['year'] ?? $_POST['year'] ?? '';

    $where_clause = "salesman_id = '$esc_id'";

    if (!empty($filter_month) && !empty($filter_year)) {
        $esc_month = $conn->real_escape_string(str_pad($filter_month, 2, '0', STR_PAD_LEFT));
        $esc_year = $conn->real_escape_string($filter_year);
        $where_clause .= " AND date LIKE '$esc_year-$esc_month-%'";
        $limit_clause = ""; // No limit if filtering by month
    } else {
        $limit_clause = "LIMIT 40"; // Default limit if no filter
    }

    $sql = "SELECT * FROM lunch_attendance 
            WHERE $where_clause 
            ORDER BY date DESC 
            $limit_clause";
    $res = $conn->query($sql);

    $history = [];
    if ($res && $res->num_rows > 0) {
        while ($row = $res->fetch_assoc()) {
            $extra = (int) $row['extra_break_time'];
            $extra_display = null;
            if ($extra > 0) {
                $extra_min = floor($extra / 60);
                $extra_sec = $extra % 60;
                $extra_display = "+{$extra_min}m";
                if ($extra_sec > 0) {
                    $extra_display .= " {$extra_sec}s";
                }
            }

            $history[] = [
                "date" => $row['date'],
                "lunch_in_time" => !empty($row['lunch_in_time']) ? date('h:i:s A', strtotime($row['lunch_in_time'])) : null,
                "lunch_out_time" => !empty($row['lunch_out_time']) ? date('h:i:s A', strtotime($row['lunch_out_time'])) : null,
                "lunch_in_selfie_url" => !empty($row['lunch_in_selfie_url']) ? sanitizeLunchUrl($base_url . $row['lunch_in_selfie_url']) : null,
                "lunch_out_selfie_url" => !empty($row['lunch_out_selfie_url']) ? sanitizeLunchUrl($base_url . $row['lunch_out_selfie_url']) : null,
                "duration_seconds" => (int) $row['duration_seconds'],
                "extra_break_time" => $extra,
                "extra_break_display" => $extra_display,
                "in_latitude" => $row['in_latitude'] ?? null,
                "in_longitude" => $row['in_longitude'] ?? null,
                "out_latitude" => $row['out_latitude'] ?? null,
                "out_longitude" => $row['out_longitude'] ?? null
            ];
        }
    }

    echo json_encode([
        "status" => "success",
        "data" => $history
    ]);
    exit;
}

// =========================================================
// DEFAULT: INVALID ACTION
// =========================================================
echo json_encode([
    "status" => "error",
    "message" => "Invalid action: '$action'. Valid actions: lunch_in, lunch_out, get_lunch_status, get_lunch_history"
]);
?>
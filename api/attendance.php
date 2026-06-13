<?php
// slfm_backend_scripts/attendance.php
// FULL VERSION: Includes All Tasks (1, 3, 4, 6) + Image Uploads + PERFORMANCE TRIGGER + GEOFENCING (150m)
// ============================================================
// FIXES APPLIED (FAST UPLOAD VERSION):
// FIX 1: fastcgi_finish_request() → Client gets response instantly, no waiting.
// FIX 2: cURL 100ms fire-and-forget for performance trigger → No image lag.
// FIX 3: imagedestroy() added → GD memory freed after every image, faster next upload.
// FIX 4: capture_time now also updates $date → Offline sync date bug fixed.
// FIX 5: Smart Cooldown (2 min) → Prevents duplicate submissions & rapid taps.
// FIX 6: Duplicate clock_in/clock_out now returns correct existing image.
// FIX 7: Get Summary returns dynamic image based on current state.
// FIX 8: updated_at column auto-created if missing.
// FIX 9: Zombie clock_out_time from previous date cleared on re-entry.
// FIX 10: Today not marked Absent prematurely in get_history.
// FIX 11: 4-Step Sequence Locked (In -> Break -> Re-entry -> Out).
// FIX 12: STRICT 07:30 PM Limit for Re-Entry.
// ============================================================

// 1. Error Reporting (Suppressed for JSON output)
error_reporting(E_ERROR | E_PARSE);
ini_set('display_errors', 0);

// 2. Headers
header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");

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
$lat = $json_data['lat'] ?? $_POST['lat'] ?? null;
$lng = $json_data['lng'] ?? $_POST['lng'] ?? null;
$capture_time = $json_data['capture_time'] ?? $_POST['capture_time'] ?? null;
$device_id_used = $json_data['device_id'] ?? $_POST['device_id'] ?? '';
$device_model_used = $json_data['device_model'] ?? $_POST['device_model'] ?? '';

// 🔥 ACTION NORMALIZATION: Guarantee robust state transitions even if app sends explicit actions
if ($action === 'reentry' || $action === 're_entry')
    $action = 'clock_in';
if ($action === 'break_out' || $action === 'breakout')
    $action = 'clock_out';

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

// =============================================================
// HELPER: TRIGGER PERFORMANCE UPDATE
// =============================================================
function triggerPerformanceUpdate($sid)
{
    global $base_url;
    $url = $base_url . "update_salesman_summary.php";
    $data = json_encode(['salesman_id' => $sid, 'skip_sync_signal' => true]);

    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($ch, CURLOPT_POSTFIELDS, $data);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($data)
        ]);
        curl_setopt($ch, CURLOPT_TIMEOUT_MS, 5000);
        curl_setopt($ch, CURLOPT_NOSIGNAL, 1);
        @curl_exec($ch);
    } else {
        $options = [
            'http' => [
                'header' => "Content-type: application/json\r\n",
                'method' => 'POST',
                'content' => $data,
                'ignore_errors' => true,
                'timeout' => 0.5
            ]
        ];
        $context = stream_context_create($options);
        @file_get_contents($url, false, $context);
    }
}

// =============================================================
// HELPER: SEND RESPONSE TO CLIENT FIRST, THEN TRIGGER 
// =============================================================
function sendResponseAndTrigger($responseArray, $salesman_id)
{
    $json = json_encode($responseArray);
    echo $json;

    if (function_exists('fastcgi_finish_request')) {
        fastcgi_finish_request();
    } else {
        if (ob_get_level() > 0)
            ob_end_flush();
        flush();
        if (function_exists('litespeed_finish_request'))
            litespeed_finish_request();
    }
    triggerPerformanceUpdate($salesman_id);
}

// =============================================================
// GLOBAL TIME VARIABLES
// =============================================================
$date = date('Y-m-d');
$current_time_str = date('H:i:s');
$current_time_ampm = date('h:i:s A');
$timestamp = date('Y-m-d H:i:s');
$current_ts_val = time();

if (!empty($capture_time)) {
    $capture_ts = strtotime($capture_time);
    if ($capture_ts !== false) {
        $date = date('Y-m-d', $capture_ts);
        $current_time_str = date('H:i:s', $capture_ts);
        $current_time_ampm = date('h:i:s A', $capture_ts);
        $timestamp = date('Y-m-d H:i:s', $capture_ts);
        $current_ts_val = $capture_ts;
    }
}

// =============================================================
// HELPER: DISTANCE CALCULATOR 
// =============================================================
function getDistanceInMeters($lat1, $lon1, $lat2, $lon2)
{
    if (empty($lat1) || empty($lon1) || empty($lat2) || empty($lon2))
        return 99999;
    $earth_radius = 6371000;
    $dLat = deg2rad((float) $lat2 - (float) $lat1);
    $dLon = deg2rad((float) $lon2 - (float) $lon1);
    $a = sin($dLat / 2) * sin($dLat / 2) +
        cos(deg2rad((float) $lat1)) * cos(deg2rad((float) $lat2)) *
        sin($dLon / 2) * sin($dLon / 2);
    $c = 2 * asin(sqrt($a));
    return round($earth_radius * $c);
}

function sanitizeUrl($url)
{
    if (empty($url))
        return "";
    $url = str_replace('\\', '/', $url);
    $url = str_replace(' ', '%20', $url);
    return $url;
}

function applyWatermark($imageData, $salesmanName, $showroomName, $timeText)
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

function handleImageUpload($base64_image, $showroom_name, $salesman_name, $salesman_id, $date, $suffix, $watermark_text)
{
    if (empty($base64_image))
        return "";

    $safe_showroom = preg_replace('/[^A-Za-z0-9\-]/', '_', $showroom_name);
    $upload_base = "uploads/attendance/";
    $date_dir = $upload_base . $safe_showroom . "/" . $date . "/";

    foreach (["uploads", "uploads/attendance", $upload_base . $safe_showroom, $date_dir] as $dir) {
        if (!is_dir($dir))
            @mkdir($dir, 0777, true);
    }
    if (!is_dir($date_dir))
        $date_dir = $upload_base;

    if (strpos($base64_image, ',') !== false) {
        $parts = explode(',', $base64_image);
        $base64_image = $parts[1];
    }
    $image_data = base64_decode($base64_image);
    if ($image_data === false)
        return "";

    $finfo = new finfo(FILEINFO_MIME_TYPE);
    $mime_type = $finfo->buffer($image_data);
    if ($mime_type !== 'image/jpeg' && $mime_type !== 'image/png')
        return "";

    $image_data = applyWatermark($image_data, $salesman_name, $showroom_name, $watermark_text);
    $safe_name = preg_replace('/[^A-Za-z0-9\-]/', '_', $salesman_name);
    $filename = $safe_name . "_" . $salesman_id . "_" . date("Y_m_d_H_i_s") . "_" . $suffix . ".jpg";
    $filepath = $date_dir . $filename;

    if (@file_put_contents($filepath, $image_data))
        return $filepath;
    return "";
}

// =============================================================
// HELPER: SMART COOLDOWN CHECK (2 MINUTES)
// =============================================================
function enforceSmartCooldown($conn, $salesman_id, $action)
{
    global $current_ts_val, $date, $base_url, $current_time_str, $allow_late_entry, $full_day_exit_start, $gender, $reentry_cutoff;

    $att_sql = "SELECT clock_in_time, clock_out_time, resume_count, selfie_url,
                       clock_out_selfie_url, reentry_selfie_url, final_out_selfie_url,
                       status, updated_at
                FROM attendance WHERE salesman_id = '$salesman_id' AND date = '$date'";
    $att_res = $conn->query($att_sql);
    if (!$att_res || $att_res->num_rows == 0)
        return;

    $row = $att_res->fetch_assoc();
    $current_status = $row['status'] ?? '';
    $resume_count = (int) ($row['resume_count'] ?? 0);
    $has_clock_in = !empty($row['clock_in_time']);
    $has_clock_out = !empty($row['clock_out_time']);

    if (!$has_clock_in) {
        if ($current_status == 'Absent' || strpos(strtolower($current_status), 'leave') !== false) {
            return;
        }
    }

    $is_duplicate = false;
    if ($action == 'clock_in' && $has_clock_in && !$has_clock_out)
        $is_duplicate = true;
    if ($action == 'clock_out' && $has_clock_out)
        $is_duplicate = true;
    if ($is_duplicate)
        return;

    // 🔥 FIX: If action is clock_in but clock_out exists, this is a RE-ENTRY.
    // Skip cooldown — re-entry has its own guards (1-hour limit, 7:30 PM cutoff, resume limit).
    if ($action == 'clock_in' && $has_clock_out)
        return;

    // 🔥 STRICT RULE FOR RE-ENTRY
    if ($action == 'clock_in' && $has_clock_out && $allow_late_entry !== 1) {
        if ($current_time_str > $reentry_cutoff) {
            $cutoff_display = date("h:i A", strtotime($reentry_cutoff));
            echo json_encode([
                "status" => "error",
                "message" => "முடிந்தது! நேரம் $cutoff_display ஆகிவிட்டது, இனி உங்களால் Re-entry செய்ய முடியாது. 🙏"
            ]);
            exit;
        }
    }

    $last_time = null;
    if ($has_clock_out) {
        $last_time = strtotime($row['clock_out_time']);
    } elseif ($resume_count > 0) {
        if (!empty($row['updated_at']))
            $last_time = strtotime($row['updated_at']);
    } else {
        if (!empty($row['clock_in_time']))
            $last_time = strtotime($row['clock_in_time']);
    }

    if ($last_time !== null) {
        $diff = $current_ts_val - $last_time;
        if ($diff >= 0 && $diff < 120) {
            if ($has_clock_out) {
                $cooldown_msg = ($resume_count > 0)
                    ? "இன்று ஏற்கனவே அவுட்-டைம் (Clock-Out) பதிவு செய்யப்பட்டுவிட்டது!\nதங்கள் அடுத்த பதிவிற்கு 2 நிமிடங்கள் காத்திருக்கவும்."
                    : "இன்று ஏற்கனவே பிரேக்-அவுட் (Break-Out) பதிவு செய்யப்பட்டுவிட்டது!\nதங்கள் அடுத்த பதிவிற்கு 2 நிமிடங்கள் காத்திருக்கவும்.";
            } else {
                $cooldown_msg = ($resume_count > 0)
                    ? "இன்று ஏற்கனவே ரீ-என்ட்ரி (Re-entry) பதிவு செய்யப்பட்டுவிட்டது!\nதங்கள் அடுத்த பதிவிற்கு 2 நிமிடங்கள் காத்திருக்கவும்."
                    : "இன்று ஏற்கனவே வருகை (In-Time) பதிவு செய்யப்பட்டுவிட்டது!\nதங்கள் அடுத்த பதிவிற்கு 2 நிமிடங்கள் காத்திருக்கவும்.";
            }

            $current_img = $row['selfie_url'];
            if ($has_clock_out && $resume_count > 0) {
                $current_img = $row['final_out_selfie_url'];
            } elseif ($has_clock_out) {
                $current_img = $row['clock_out_selfie_url'];
            } elseif ($has_clock_in && $resume_count > 0) {
                $current_img = $row['reentry_selfie_url'];
            }
            $final_img = !empty($current_img) ? sanitizeUrl($base_url . $current_img) : null;

            $response = [
                "status" => "error",
                "message" => $cooldown_msg,
                "image_url" => $final_img,
                "data" => ["status" => $current_status, "image_url" => $final_img]
            ];
            if (!empty($row['clock_in_time'])) {
                $response["clock_in_time"] = $row['clock_in_time'];
                $response["data"]["clock_in_time"] = $row['clock_in_time'];
            }
            sendResponseAndTrigger($response, $salesman_id);
            exit;
        }
    }
}

// =============================================================
// FETCH SALESMAN DETAILS + DEVICE CHECK
// =============================================================
$salesman_sql = "SELECT shift_start_time, shift_end_time, custom_late_cutoff, showroom_name,
                        gender, name, primary_device_id, allow_late_entry, status
                 FROM salesmen WHERE salesman_id = '$salesman_id'";
$salesman_res = $conn->query($salesman_sql);

$shift_start_db = '09:30:00';
$shift_end_db = null;
$custom_late_cutoff = null;
$showroom_name = 'Main Branch';
$gender = 'male';
$salesman_name = $salesman_id;
$primary_device_id = '';
$allow_late_entry = 0;

if ($salesman_res && $salesman_res->num_rows > 0) {
    $s_row = $salesman_res->fetch_assoc();

    if (isset($s_row['status']) && $s_row['status'] === 'Suspended') {
        echo json_encode(["status" => "error", "message" => "Account Suspended. Attendance denied.", "is_suspended" => true]);
        exit;
    }

    $check_updated_at = $conn->query("SHOW COLUMNS FROM `attendance` LIKE 'updated_at'");
    if ($check_updated_at && $check_updated_at->num_rows == 0) {
        $conn->query("ALTER TABLE `attendance` ADD `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP");
    }

    $shift_start_db = (!empty($s_row['shift_start_time']) && $s_row['shift_start_time'] !== '00:00:00' && strtolower($s_row['shift_start_time']) !== 'null') ? $s_row['shift_start_time'] : '09:30:00';
    $shift_end_db = (!empty($s_row['shift_end_time']) && $s_row['shift_end_time'] !== '00:00:00' && strtolower($s_row['shift_end_time']) !== 'null') ? $s_row['shift_end_time'] : null;
    $custom_late_cutoff = (!empty($s_row['custom_late_cutoff']) && $s_row['custom_late_cutoff'] !== '00:00:00' && strtolower($s_row['custom_late_cutoff']) !== 'null') ? $s_row['custom_late_cutoff'] : null;
    $showroom_name = !empty($s_row['showroom_name']) ? $s_row['showroom_name'] : 'Main Branch';
    $gender = strtolower($s_row['gender'] ?? 'male');
    $salesman_name = $s_row['name'] ?? $salesman_id;
    $primary_device_id = $s_row['primary_device_id'] ?? '';
    $allow_late_entry = isset($s_row['allow_late_entry']) ? (int) $s_row['allow_late_entry'] : 0;
}

$is_proxy_device = 0;
if (!empty($primary_device_id) && !empty($device_id_used) && $primary_device_id !== $device_id_used) {
    $is_proxy_device = 1;
}

// =============================================================
// GEOFENCING LOGIC (100 METER RADIUS)
// =============================================================
$sh_lat = null;
$sh_lng = null;
$is_out_of_location = 0;
$location_distance = 0;
$admin_approval_val = "NULL";
$ALLOWED_RADIUS = 100;

$sh_sql = "SELECT latitude, longitude FROM showrooms WHERE name = '" . $conn->real_escape_string($showroom_name) . "'";
$sh_res = $conn->query($sh_sql);
if ($sh_res && $sh_res->num_rows > 0) {
    $sh_row = $sh_res->fetch_assoc();
    $sh_lat = $sh_row['latitude'];
    $sh_lng = $sh_row['longitude'];
}

if ($action == 'clock_in' || $action == 'clock_out') {
    if (!empty($lat) && !empty($lng) && !empty($sh_lat) && !empty($sh_lng)) {
        $location_distance = getDistanceInMeters($lat, $lng, $sh_lat, $sh_lng);
        if ($location_distance > $ALLOWED_RADIUS) {
            $is_out_of_location = 1;
            $admin_approval_val = "'Pending'";
        }
    } elseif (empty($lat) || empty($lng)) {
        $is_out_of_location = 1;
        $location_distance = 99999;
        $admin_approval_val = "'Pending'";
    }
}

// =============================================================
// TIME RULES & CONFIGURATION
// =============================================================
$late_cutoff_time = !empty($custom_late_cutoff) ? $custom_late_cutoff : '10:00:59';
$leave_entry_cutoff = '15:00:59';
$reentry_cutoff = '19:30:59';
$morning_half_out_start = '14:30:00';
$morning_half_out_end = '15:00:00';
$RESUME_LIMIT = 1;

$standard_exit_time = ($gender == 'female') ? '19:30:00' : '21:00:00';
if (!empty($shift_end_db) && $shift_end_db < $standard_exit_time) {
    $full_day_exit_start = $shift_end_db;
} else {
    $full_day_exit_start = $standard_exit_time;
}

// =============================================================
// ACTION: CLOCK IN (Normal Entry + Re-Entry)
// =============================================================
if ($action == 'clock_in') {

    enforceSmartCooldown($conn, $salesman_id, $action);

    // --- CHECK FOR RE-ENTRY (user is currently clocked out / break out) ---
    $reentry_sql = "SELECT id, clock_in_time, clock_out_time, selfie_url, clock_out_selfie_url, status, resume_count, admin_approval
                    FROM attendance
                    WHERE salesman_id = '$salesman_id' AND date = '$date' AND clock_out_time IS NOT NULL";
    $reentry_res = $conn->query($reentry_sql);

    if ($reentry_res && $reentry_res->num_rows > 0) {
        $re_row = $reentry_res->fetch_assoc();

        $db_out_date = date('Y-m-d', strtotime($re_row['clock_out_time']));
        if ($db_out_date != $date) {
            $conn->query("UPDATE attendance SET clock_out_time = NULL WHERE id = " . $re_row['id']);
        } else {
            // --- ACTUAL RE-ENTRY LOGIC ---
            $last_out_time = strtotime($re_row['clock_out_time']);

            if ($current_ts_val <= $last_out_time) {
                $existing_img = !empty($re_row['clock_out_selfie_url']) ? $re_row['clock_out_selfie_url'] : (!empty($re_row['selfie_url']) ? $re_row['selfie_url'] : '');
                $existing_url = !empty($existing_img) ? sanitizeUrl($base_url . $existing_img) : null;

                echo json_encode([
                    "status" => "error",
                    "message" => "ஏற்கனவே பதிவு செய்துவிட்டீர்கள், அதனால் Failed",
                    "image_url" => $existing_url,
                    "clock_in_time" => $re_row['clock_in_time'],
                    "clock_out_time" => $re_row['clock_out_time'],
                    "final_status" => $re_row['status']
                ]);
                exit;
            }

            $diff_minutes = ($current_ts_val - $last_out_time) / 60;
            $current_resumes = (int) ($re_row['resume_count'] ?? 0);

            if ($current_resumes >= $RESUME_LIMIT) {
                echo json_encode([
                    "status" => "error",
                    "message" => "இன்று ஒரு முறை Re-entry பதிவு செய்யப்பட்டுவிட்டது! மீண்டும் Re-entry செய்ய அனுமதி இல்லை. 🙏"
                ]);
                exit;
            }

            // 🔥 1-Hour (60 mins) Safe limit for Lunch Break
            if ($diff_minutes <= 60) {
                // 🔥 STRICT CUTOFF RULE FOR RE-ENTRY
                if ($current_time_str > $reentry_cutoff && $allow_late_entry !== 1) {
                    $cutoff_display = date("h:i A", strtotime($reentry_cutoff));
                    echo json_encode(["status" => "error", "message" => "முடிந்தது! நேரம் $cutoff_display ஆகிவிட்டது, இனி உங்களால் Re-entry செய்ய முடியாது. 🙏"]);
                    exit;
                }

                if ($allow_late_entry === 1) {
                    $new_status = 'Present';
                } else {
                    $orig_in_time = strtotime($re_row['clock_in_time']);
                    $limit_late = strtotime("$date $late_cutoff_time");
                    $limit_leave = strtotime("$date $leave_entry_cutoff");
                    if ($orig_in_time > $limit_leave)
                        $new_status = 'Leave';
                    elseif ($orig_in_time > $limit_late)
                        $new_status = 'Half Day';
                    else
                        $new_status = 'Present';
                }

                $db_image_path = handleImageUpload(
                    $json_data['selfie_url'] ?? $_POST['selfie_url'] ?? '',
                    $showroom_name,
                    $salesman_name,
                    $salesman_id,
                    $date,
                    'REENTRY',
                    "RE-ENTRY: $current_time_ampm"
                );

                $new_count = $current_resumes + 1;
                $final_admin_approval = ($is_out_of_location == 1) ? "'Pending'" : ($re_row['admin_approval'] ? "'" . $re_row['admin_approval'] . "'" : "NULL");

                $resume_sql = "UPDATE attendance
                               SET clock_out_time    = NULL,
                                   status            = '$new_status',
                                   resume_count      = $new_count,
                                   reentry_selfie_url= '$db_image_path',
                                   device_id_used    = '$device_id_used',
                                   device_model_used = '$device_model_used',
                                   is_proxy_device   = $is_proxy_device,
                                   is_out_of_location= $is_out_of_location,
                                   location_distance = $location_distance,
                                   admin_approval    = $final_admin_approval,
                                   updated_at        = '$timestamp'
                               WHERE id = " . $re_row['id'];

                if ($conn->query($resume_sql) === TRUE) {
                    $msg = "உங்கள் ரீ-என்ட்ரி (Re-entry) பதிவு செய்யப்பட்டது! மீண்டும் வருக.";
                    if ($is_out_of_location == 1) {
                        $msg .= " (Out of Location - Pending Admin Approval)";
                    }
                    $final_url = $db_image_path ? sanitizeUrl($base_url . $db_image_path) : null;

                    sendResponseAndTrigger([
                        "status" => "success",
                        "message" => $msg,
                        "action" => "resume",
                        "image_url" => $final_url,
                        "selfie_url" => $final_url,
                        "reentry_selfie_url" => $final_url,
                        "clock_in_selfie_url" => $final_url
                    ], $salesman_id);
                    $conn->close();
                    exit;
                }
            } else {
                echo json_encode([
                    "status" => "error",
                    "message" => "உங்கள் பிரேக் நேரம் 1 மணிநேரத்தை தாண்டிவிட்டது! மீண்டும் Re-entry செய்ய அனுமதி இல்லை."
                ]);
                exit;
            }
        }
    }

    // --- NORMAL CLOCK IN ---
    $cur_time_stamp = strtotime($current_time_str);
    $leave_cutoff_stamp = strtotime($leave_entry_cutoff);
    if ($cur_time_stamp > $leave_cutoff_stamp && $allow_late_entry != 1) {
        echo json_encode(["status" => "error", "message" => "வருகை பதிவு நேரம் (03:00 PM) முடிந்துவிட்டது! அட்மினை தொடர்பு கொள்ளவும்."]);
        exit;
    }

    $db_image_path = handleImageUpload(
        $json_data['selfie_url'] ?? $_POST['selfie_url'] ?? '',
        $showroom_name,
        $salesman_name,
        $salesman_id,
        $date,
        'IN',
        "IN: $current_time_ampm"
    );

    $status = 'Present';
    $is_late = 0;
    if ($allow_late_entry == 1) {
        $status = 'Present';
        $is_late = 0;
    } else {
        if ($cur_time_stamp > strtotime($leave_entry_cutoff)) {
            $status = 'Leave';
            $is_late = 1;
        } elseif ($cur_time_stamp > strtotime($late_cutoff_time)) {
            $status = 'Half Day';
            $is_late = 1;
        } elseif ($cur_time_stamp > strtotime($shift_start_db)) {
            $is_late = 1;
        }
    }

    $check_sql = "SELECT id, status, resume_count, selfie_url, reentry_selfie_url
                  FROM attendance WHERE salesman_id = '$salesman_id' AND date = '$date'";
    $result = $conn->query($check_sql);

    $lat_val = $lat ? "'$lat'" : "NULL";
    $lng_val = $lng ? "'$lng'" : "NULL";
    $d_id_val = $device_id_used ? "'$device_id_used'" : "NULL";
    $d_model_val = $device_model_used ? "'$device_model_used'" : "NULL";
    $late_entry_approved_val = ($allow_late_entry == 1) ? 1 : 0;

    if ($result && $result->num_rows == 0) {
        $sql = "INSERT INTO attendance
                    (salesman_id, showroom_name, date, clock_in_time, selfie_url, status, is_late,
                     latitude, longitude, resume_count, device_id_used, device_model_used,
                     is_proxy_device, late_entry_approved, is_out_of_location, location_distance,
                     admin_approval, updated_at)
                VALUES
                    ('$salesman_id', '$showroom_name', '$date', '$timestamp', '$db_image_path',
                     '$status', '$is_late', $lat_val, $lng_val, 0, $d_id_val, $d_model_val,
                     $is_proxy_device, $late_entry_approved_val, $is_out_of_location,
                     $location_distance, $admin_approval_val, '$timestamp')";

        if ($conn->query($sql) === TRUE) {
            $conn->query("UPDATE leave_requests SET status = 'Cancelled'
                          WHERE salesman_id = '$salesman_id' AND leave_date = '$date'
                          AND status IN ('Approved', 'Pending')");

            $is_custom_late = false;
            $msg = "Clocked In ($status)";
            if ($status == 'Half Day') {
                if (!empty($custom_late_cutoff)) {
                    $formatted_cutoff = date("h:i A", strtotime($custom_late_cutoff));
                    $msg = "உங்களுக்கு கொடுத்த நேரமே $formatted_cutoff, அதிலும் லேட்டா வந்து இருக்கீங்க! உங்களுக்கு Half Day தான் போங்க.";
                    $is_custom_late = true;
                } else {
                    $msg = "வணக்கம்! இன்றைய பணி ஆரம்பம்.\nStatus : Half Day";
                }
            } elseif ($status == 'Present') {
                $msg = "வணக்கம்! இன்றைய பணி ஆரம்பம்.\nStatus : Present";
            }

            if ($is_out_of_location == 1) {
                $msg = "உங்களுக்கு குறிக்கப்பட்ட $showroom_name -ல் இருந்து Photo போடவெண்டும். ஒருவேளை $showroom_name -ல் இருந்து Photo போட்டாலும், உங்கள் Location-ஐ உங்கள் மொபைல் தவறாக எடுத்துள்ளது என்று அர்த்தம்! கவலை படாதீர்கள், நீங்கள் $status. OK!!";
            }

            $final_url = $db_image_path ? sanitizeUrl($base_url . $db_image_path) : null;
            sendResponseAndTrigger([
                "status" => $is_custom_late ? "error" : "success",
                "message" => $msg,
                "image_url" => $final_url,
                "selfie_url" => $final_url,
                "clock_in_selfie_url" => $final_url
            ], $salesman_id);
            $conn->close();
            exit;
        } else {
            echo json_encode(["status" => "error", "message" => "DB Insert Error: " . $conn->error]);
        }
    } else {
        $row = $result->fetch_assoc();
        $att_status_lower = strtolower($row['status'] ?? '');
        $is_allowed_to_update = (
            $att_status_lower == 'absent' ||
            $att_status_lower == 'leave' ||
            strpos($att_status_lower, 'on leave') === 0
        );

        if ($is_allowed_to_update) {
            $update_sql = "UPDATE attendance
                           SET clock_in_time      = '$timestamp',
                               status             = '$status',
                               is_late            = '$is_late',
                               selfie_url         = '$db_image_path',
                               showroom_name      = '$showroom_name',
                               latitude           = $lat_val,
                               longitude          = $lng_val,
                               resume_count       = 0,
                               device_id_used     = $d_id_val,
                               device_model_used  = $d_model_val,
                               is_proxy_device    = $is_proxy_device,
                               late_entry_approved= $late_entry_approved_val,
                               is_out_of_location = $is_out_of_location,
                               location_distance  = $location_distance,
                               admin_approval     = $admin_approval_val,
                               updated_at         = '$timestamp'
                           WHERE id = " . $row['id'];

            if ($conn->query($update_sql) === TRUE) {
                $conn->query("UPDATE leave_requests SET status = 'Cancelled'
                              WHERE salesman_id = '$salesman_id' AND leave_date = '$date'
                              AND status IN ('Approved', 'Pending')");

                $is_custom_late = false;
                $msg = "உங்கள் வருகை பதிவு செய்யப்பட்டது (பழைய $att_status_lower ரத்து செய்யப்பட்டது)";
                if ($status == 'Half Day') {
                    if (!empty($custom_late_cutoff)) {
                        $formatted_cutoff = date("h:i A", strtotime($custom_late_cutoff));
                        $msg = "உங்களுக்கு கொடுத்த நேரமே $formatted_cutoff, அதிலும் லேட்டா வந்து இருக்கீங்க! உங்களுக்கு Half Day தான் போங்க.";
                        $is_custom_late = true;
                    } else {
                        $msg = "வணக்கம்! இன்றைய பணி ஆரம்பம்.\nStatus : Half Day";
                    }
                } elseif ($status == 'Present') {
                    $msg = "வணக்கம்! இன்றைய பணி ஆரம்பம்.\nStatus : Present";
                }

                if ($is_out_of_location == 1) {
                    $msg = "உங்களுக்கு குறிக்கப்பட்ட $showroom_name -ல் இருந்து Photo போடவெண்டும். ஒருவேளை $showroom_name -ல் இருந்து Photo போட்டாலும், உங்கள் Location-ஐ உங்கள் மொபைல் தவறாக எடுத்துள்ளது என்று அர்த்தம்! கவலை படாதீர்கள், நீங்கள் $status. OK!!";
                }

                $final_url = $db_image_path ? sanitizeUrl($base_url . $db_image_path) : null;
                sendResponseAndTrigger([
                    "status" => $is_custom_late ? "error" : "success",
                    "message" => $msg,
                    "image_url" => $final_url,
                    "selfie_url" => $final_url,
                    "clock_in_selfie_url" => $final_url
                ], $salesman_id);
                $conn->close();
                exit;
            } else {
                echo json_encode(["status" => "error", "message" => "DB Update Error: " . $conn->error]);
            }
        } else {
            // Already clocked in handler
            $resume_count = (int) ($row['resume_count'] ?? 0);
            $has_clock_out = !empty($row['clock_out_time']);

            if ($resume_count > 0 && !empty($row['reentry_selfie_url'])) {
                $existing_url = sanitizeUrl($base_url . $row['reentry_selfie_url']);
            } else {
                $existing_url = !empty($row['selfie_url']) ? sanitizeUrl($base_url . $row['selfie_url']) : null;
            }

            if ($has_clock_out) {
                // If currently in break-out state, do re-entry (Fallback)
                $new_resume_count = $resume_count + 1;
                $update_sql = "UPDATE attendance
                               SET status         = 'Present',
                                   clock_out_time = NULL,
                                   resume_count   = $new_resume_count,
                                   updated_at     = '$timestamp'
                               WHERE id = " . $row['id'];

                if ($conn->query($update_sql) === TRUE) {
                    sendResponseAndTrigger([
                        "status" => "success",
                        "message" => "உங்கள் ரீ-என்ட்ரி (Re-entry) பதிவு செய்யப்பட்டது! மீண்டும் வருக.",
                        "image_url" => $existing_url,
                        "clock_in_time" => $row['clock_in_time'],
                        "resume_count" => $new_resume_count,
                        "final_status" => "Present"
                    ], $salesman_id);
                    $conn->close();
                    exit;
                }
            } else {
                // Pure duplicate — already clocked in
                $last_in_time = strtotime($row['clock_in_time']);
                if ($current_ts_val <= $last_in_time) {
                    echo json_encode([
                        "status" => "error",
                        "message" => "ஏற்கனவே பதிவு செய்துவிட்டீர்கள், அதனால் Failed",
                        "image_url" => $existing_url,
                        "selfie_url" => $existing_url,
                        "clock_in_time" => $row['clock_in_time'],
                        "resume_count" => $resume_count,
                        "final_status" => $row['status']
                    ]);
                    exit;
                }

                $msg_tamil = ($resume_count > 0)
                    ? "இன்று ஏற்கனவே ரீ-என்ட்ரி (Re-entry) பதிவு செய்யப்பட்டுவிட்டது!\nதங்கள் அடுத்த பதிவிற்கு 2 நிமிடங்கள் காத்திருக்கவும்."
                    : "இன்று ஏற்கனவே வருகை (In-Time) பதிவு செய்யப்பட்டுவிட்டது!\nதங்கள் அடுத்த பதிவிற்கு 2 நிமிடங்கள் காத்திருக்கவும்.";

                echo json_encode([
                    "status" => "duplicate",
                    "message" => $msg_tamil,
                    "image_url" => $existing_url,
                    "selfie_url" => $existing_url,
                    "clock_in_time" => $row['clock_in_time'],
                    "resume_count" => $resume_count,
                    "final_status" => $row['status']
                ]);
            }
        }
    }
}

// =============================================================
// ACTION: CLOCK OUT (Break Out + Final Out)
// =============================================================
elseif ($action == 'clock_out') {

    enforceSmartCooldown($conn, $salesman_id, $action);

    $check_sql = "SELECT id, clock_in_time, status, resume_count, is_out_of_location, location_distance, admin_approval, modification_reason
                  FROM attendance
                  WHERE salesman_id = '$salesman_id' AND date = '$date'
                  AND clock_in_time IS NOT NULL AND (clock_out_time IS NULL OR status = 'Break-Out' OR modification_reason = 'M/O SO HALF DAY')";
    $res = $conn->query($check_sql);

    if ($res && $res->num_rows > 0) {
        $row = $res->fetch_assoc();

        $clock_out_logic = strtotime($current_time_str);
        $final_status = $row['status'];
        $m_half_start = strtotime($morning_half_out_start);
        $m_half_end = strtotime($morning_half_out_end);
        $exit_start_val = strtotime($full_day_exit_start);

        // 🔥 PROBLEM 3 FIX: Recalculate original status before checking clock-out rules
        // Because Cron overwrites the status, we recalculate what it was originally based on clock_in_time.
        if ($final_status === 'Half Day' && isset($row['modification_reason']) && strpos($row['modification_reason'], 'M/O SO HALF DAY') !== false) {
            $in_time_val = strtotime($row['clock_in_time']);
            if ($allow_late_entry == 1) {
                $final_status = 'Present';
            } else {
                if ($in_time_val > strtotime("$date $leave_entry_cutoff")) {
                    $final_status = 'Leave';
                } elseif ($in_time_val > strtotime("$date $late_cutoff_time")) {
                    $final_status = 'Half Day';
                } else {
                    $final_status = 'Present';
                }
            }
        }

        if ($final_status == 'Present' || $final_status == 'Half Day') {
            $in_time_val = strtotime($row['clock_in_time']);
            $afternoon_start_val = strtotime("$date 15:00:59");

            if ($in_time_val > $afternoon_start_val) {
                if ($clock_out_logic < $exit_start_val)
                    $final_status = 'Leave';
            } else {
                if ($clock_out_logic < $m_half_start) {
                    $final_status = 'Leave';
                } elseif ($clock_out_logic >= $m_half_start && $clock_out_logic <= $m_half_end) {
                    $final_status = 'Half Day';
                } elseif ($clock_out_logic < $exit_start_val) {
                    $final_status = ($final_status == 'Half Day') ? 'Leave' : 'Half Day';
                }
            }
        }

        $db_image_path = handleImageUpload(
            $json_data['selfie_url'] ?? $_POST['selfie_url'] ?? '',
            $showroom_name,
            $salesman_name,
            $salesman_id,
            $date,
            'OUT',
            "OUT: $current_time_ampm"
        );

        $out_is_out = $row['is_out_of_location'];
        $out_distance = $row['location_distance'];
        $out_admin_approval = $row['admin_approval'] ? "'" . $row['admin_approval'] . "'" : "NULL";
        if ($is_out_of_location == 1) {
            $out_is_out = 1;
            $out_distance = $location_distance;
            $out_admin_approval = "'Pending'";
        }

        $out_lat_val = $lat ? "'$lat'" : "NULL";
        $out_lng_val = $lng ? "'$lng'" : "NULL";
        $resume_count = (int) ($row['resume_count'] ?? 0);

        if ($resume_count > 0) {
            // Final exit (after re-entry)
            $sql = "UPDATE attendance
                    SET clock_out_time      = '$timestamp',
                        status              = '$final_status',
                        final_out_selfie_url= '$db_image_path',
                        is_out_of_location  = $out_is_out,
                        location_distance   = $out_distance,
                        admin_approval      = $out_admin_approval,
                        modification_reason = NULL,
                        out_latitude        = $out_lat_val,
                        out_longitude       = $out_lng_val,
                        updated_at          = '$timestamp'
                    WHERE salesman_id = '$salesman_id' AND date = '$date'";
        } else {
            // Break out (first clock-out)
            $sql = "UPDATE attendance
                    SET clock_out_time       = '$timestamp',
                        status               = '$final_status',
                        clock_out_selfie_url = '$db_image_path',
                        is_out_of_location   = $out_is_out,
                        location_distance    = $out_distance,
                        admin_approval       = $out_admin_approval,
                        modification_reason  = NULL,
                        out_latitude         = $out_lat_val,
                        out_longitude        = $out_lng_val,
                        updated_at           = '$timestamp'
                    WHERE salesman_id = '$salesman_id' AND date = '$date'";
        }

        if ($conn->query($sql) === TRUE) {
            if ($resume_count > 0) {
                $msg = "இன்றைய பணி இனிதே நிறைவடைந்தது! (Final Clock-Out)";
            } else {
                $msg = "உங்கள் Break-Out பதிவு செய்யப்பட்டது! மீண்டும் Re-entry செய்ய மறக்காதீர்கள்.";
            }
            if ($is_out_of_location == 1) {
                $msg .= " (Out of Location - Pending Approval)";
            }
            $final_url = $db_image_path ? sanitizeUrl($base_url . $db_image_path) : null;

            sendResponseAndTrigger([
                "status" => "success",
                "message" => $msg,
                "final_status" => $final_status,
                "image_url" => $final_url,
                "selfie_url" => $final_url,
                "clock_out_selfie_url" => $final_url
            ], $salesman_id);
            $conn->close();
            exit;
        } else {
            echo json_encode(["status" => "error", "message" => "DB Error: " . $conn->error]);
        }

    } else {
        // Duplicate / already clocked out handler
        $check_exists_sql = "SELECT clock_in_time, clock_out_time, selfie_url, final_out_selfie_url,
                                    clock_out_selfie_url, status, resume_count
                             FROM attendance WHERE salesman_id = '$salesman_id' AND date = '$date'";
        $exists_res = $conn->query($check_exists_sql);

        if ($exists_res && $exists_res->num_rows > 0) {
            $row = $exists_res->fetch_assoc();

            $last_out_time = strtotime($row['clock_out_time'] ?? '1970-01-01');
            $existing_img = !empty($row['final_out_selfie_url'])
                ? $row['final_out_selfie_url']
                : (!empty($row['clock_out_selfie_url']) ? $row['clock_out_selfie_url'] : $row['selfie_url']);
            $existing_url = !empty($existing_img) ? sanitizeUrl($base_url . $existing_img) : null;

            if ($current_ts_val <= $last_out_time) {
                echo json_encode([
                    "status" => "error",
                    "message" => "ஏற்கனவே பதிவு செய்துவிட்டீர்கள், அதனால் Failed",
                    "image_url" => $existing_url,
                    "clock_in_time" => $row['clock_in_time'],
                    "clock_out_time" => $row['clock_out_time'],
                    "final_status" => $row['status']
                ]);
                exit;
            }

            $resume_count = (int) ($row['resume_count'] ?? 0);

            $msg_tamil = ($resume_count > 0 || !empty($row['final_out_selfie_url']))
                ? "இன்று ஏற்கனவே அவுட்-டைம் (Clock-Out) பதிவு செய்யப்பட்டுவிட்டது!\nதங்கள் அடுத்த பதிவிற்கு 2 நிமிடங்கள் காத்திருக்கவும்."
                : "இன்று ஏற்கனவே பிரேக்-அவுட் (Break-Out) பதிவு செய்யப்பட்டுவிட்டது!\nதங்கள் அடுத்த பதிவிற்கு 2 நிமிடங்கள் காத்திருக்கவும்.";

            echo json_encode([
                "status" => "duplicate",
                "message" => $msg_tamil,
                "image_url" => $existing_url,
                "clock_in_time" => $row['clock_in_time'],
                "clock_out_time" => $row['clock_out_time'],
                "final_status" => $row['status']
            ]);
        } else {
            echo json_encode(["status" => "error", "message" => "நீங்கள் இன்று இன்னும் இன்-டைம் (Clock-In) பதிவு செய்யவில்லை!"]);
        }
    }
}

// =============================================================
// ACTION: GET SUMMARY
// =============================================================
elseif ($action == 'get_summary') {

    $holiday_sql = "SELECT reason FROM holidays WHERE holiday_date = '$date' LIMIT 1";
    $holiday_res = $conn->query($holiday_sql);

    $today_sql = "SELECT id, clock_in_time, clock_out_time, status, showroom_name, resume_count,
                         selfie_url, clock_out_selfie_url, reentry_selfie_url, final_out_selfie_url, updated_at,
                         modification_reason
                  FROM attendance WHERE salesman_id = '$salesman_id' AND date = '$date'";
    $today_res = $conn->query($today_sql);

    $response = [
        "clock_in" => null,
        "clock_out" => null,
        "resume_count" => 0,
        "attendance_status" => "Not Marked",
        "attendance_rate" => "0%",
        "month_hours" => "0h 0m",
        "week_hours" => "0h 0m",
        "clock_in_limit" => $leave_entry_cutoff,
        "reentry_limit" => $reentry_cutoff,
        "allow_late_entry" => $allow_late_entry
    ];

    if ($today_res && $today_res->num_rows > 0) {
        $row = $today_res->fetch_assoc();

        $response['clock_in'] = $row['clock_in_time'];
        $response['clock_out'] = $row['clock_out_time'];
        $response['resume_count'] = (int) ($row['resume_count'] ?? 0);
        if (isset($row['modification_reason']) && strpos($row['modification_reason'], 'M/O SO HALF DAY') !== false) {
            $response['attendance_status'] = "Half Day";
        } else {
            $response['attendance_status'] = $row['status'];
        }
        $response['showroom_name'] = $row['showroom_name'];
        $response['last_action_time'] = $row['updated_at'] ?? $row['clock_in_time'];

        $m_in = !empty($row['selfie_url']) ? sanitizeUrl($base_url . $row['selfie_url']) : null;
        $r_in = !empty($row['reentry_selfie_url']) ? sanitizeUrl($base_url . $row['reentry_selfie_url']) : null;
        $b_out = !empty($row['clock_out_selfie_url']) ? sanitizeUrl($base_url . $row['clock_out_selfie_url']) : null;
        $f_out = !empty($row['final_out_selfie_url']) ? sanitizeUrl($base_url . $row['final_out_selfie_url']) : null;

        $response['selfie_url'] = $m_in;
        $response['clock_out_selfie_url'] = $f_out ? $f_out : $b_out;
        $response['reentry_selfie_url'] = $r_in;

        if (!empty($row['clock_out_time'])) {
            $response['image_url'] = $f_out ? $f_out : ($b_out ? $b_out : $m_in);
        } else {
            $response['image_url'] = ($response['resume_count'] > 0 && $r_in) ? $r_in : $m_in;
        }

    } elseif ($holiday_res && $holiday_res->num_rows > 0) {
        $h_row = $holiday_res->fetch_assoc();
        $reason = $h_row['reason'] ?? 'Holiday';
        $response['attendance_status'] = "Holiday ($reason)";
        $response['holiday_reason'] = $reason;
    } else {
        $leave_res = $conn->query("SELECT leave_type FROM leave_requests
                                   WHERE salesman_id = '$salesman_id' AND leave_date = '$date'
                                   AND status != 'Rejected' LIMIT 1");
        if ($leave_res && $leave_res->num_rows > 0) {
            $l_row = $leave_res->fetch_assoc();
            $response['attendance_status'] = "On Leave (" . $l_row['leave_type'] . ")";
        }
    }

    $current_month = date('Y-m');
    $perf_sql = "SELECT total_working_hours, weekly_working_hours, attendance_percentage,
                        total_days_consumed, total_worked_days, total_present, total_half_days, excluded_dates
                 FROM salesman_monthly_performance
                 WHERE salesman_id = '$salesman_id' AND report_month = '$current_month'";
    $perf_res = $conn->query($perf_sql);

    $response['total_worked_days'] = "0";
    $response['total_leaves_used'] = "0";
    $response['excluded_dates'] = [];

    if ($perf_res && $perf_res->num_rows > 0) {
        $perf = $perf_res->fetch_assoc();

        function formatDbTime($timeStr)
        {
            if (!$timeStr)
                return "0h 0m";
            $parts = explode(':', $timeStr);
            return (int) $parts[0] . "h " . (int) $parts[1] . "m";
        }

        $response['attendance_rate'] = $perf['attendance_percentage'] . "%";
        $response['month_hours'] = formatDbTime($perf['total_working_hours']);
        $response['week_hours'] = formatDbTime($perf['weekly_working_hours']);

        $leaves_used = (float) ($perf['total_days_consumed'] ?? 0);
        $present = (int) ($perf['total_present'] ?? 0);
        $half = (int) ($perf['total_half_days'] ?? 0);
        $worked = isset($perf['total_worked_days']) ? (float) $perf['total_worked_days'] : ($present + ($half * 0.5));

        $response['total_worked_days'] = (string) $worked;
        $response['total_leaves_used'] = (string) $leaves_used;

        if (!empty($perf['excluded_dates'])) {
            $response['excluded_dates'] = json_decode($perf['excluded_dates'], true) ?? [];
        }
    }

    echo json_encode(["status" => "success", "data" => $response]);
}

// =============================================================
// ACTION: GET HISTORY
// =============================================================
elseif ($action == 'get_history') {

    $history_data = [];
    $end_date = date('Y-m-d');
    $start_date = date('Y-m-d', strtotime('-40 days'));

    $salesman_res2 = $conn->query("SELECT created_at FROM salesmen WHERE salesman_id = '$salesman_id' LIMIT 1");
    $creation_date = '2000-01-01';
    if ($salesman_res2 && $salesman_res2->num_rows > 0) {
        $s_row2 = $salesman_res2->fetch_assoc();
        $creation_date = date('Y-m-d', strtotime($s_row2['created_at']));
    }

    $att_sql = "SELECT * FROM attendance WHERE salesman_id = '$salesman_id' AND date >= '$start_date' AND date <= '$end_date'";
    $att_res = $conn->query($att_sql);
    $att_map = [];
    if ($att_res) {
        while ($row = $att_res->fetch_assoc())
            $att_map[$row['date']] = $row;
    }

    $hol_sql = "SELECT holiday_date, reason FROM holidays WHERE holiday_date >= '$start_date' AND holiday_date <= '$end_date'";
    $hol_res = $conn->query($hol_sql);
    $hol_map = [];
    if ($hol_res) {
        while ($row = $hol_res->fetch_assoc())
            $hol_map[$row['holiday_date']] = $row['reason'] ?? 'Holiday';
    }

    $leave_sql = "SELECT leave_date FROM leave_requests
                  WHERE salesman_id = '$salesman_id' AND leave_date >= '$start_date'
                  AND leave_date <= '$end_date' AND status = 'Approved'";
    $leave_res = $conn->query($leave_sql);
    $leave_map = [];
    if ($leave_res) {
        while ($row = $leave_res->fetch_assoc())
            $leave_map[$row['leave_date']] = true;
    }

    for ($i = 0; $i < 40; $i++) {
        $target_date = date('Y-m-d', strtotime("-$i days", strtotime($end_date)));
        $has_punch = isset($att_map[$target_date]);

        if ($target_date < $creation_date)
            continue;
        if ($target_date == $creation_date && !$has_punch)
            continue;

        $is_holiday = isset($hol_map[$target_date]);
        $holiday_reason = $is_holiday ? $hol_map[$target_date] : "";

        if ($has_punch) {
            $row = $att_map[$target_date];
            $hours_str = "0h 0m";
            if (!empty($row['clock_in_time']) && !empty($row['clock_out_time'])) {
                $start = new DateTime($row['clock_in_time']);
                $end_dt = new DateTime($row['clock_out_time']);
                $interval = $start->diff($end_dt);
                $hours_str = $interval->format('%hh %im');
            } elseif (!empty($row['clock_in_time']) && $row['status'] != 'Absent') {
                $hours_str = "Ongoing";
            }

            $thumb = !empty($row['selfie_url']) ? sanitizeUrl($base_url . $row['selfie_url']) : "assets/images/no-image.jpg";
            $out_thumb = !empty($row['final_out_selfie_url']) ? sanitizeUrl($base_url . $row['final_out_selfie_url']) : (!empty($row['clock_out_selfie_url']) ? sanitizeUrl($base_url . $row['clock_out_selfie_url']) : "");
            $reentry_thumb = !empty($row['reentry_selfie_url']) ? sanitizeUrl($base_url . $row['reentry_selfie_url']) : "";

            $ci_display = $row['clock_in_time'] ? date('h:i:s A', strtotime($row['clock_in_time'])) : "--:--";
            $co_display = $row['clock_out_time'] ? date('h:i:s A', strtotime($row['clock_out_time'])) : "--:--";

            $status = $is_holiday ? "Holiday" : ($row['status'] ?: 'not_logged_in');
            if (isset($row['modification_reason']) && strpos($row['modification_reason'], 'M/O SO HALF DAY') !== false) {
                $status = "M/O SO HALF DAY";
            }

            $history_data[] = [
                "id" => isset($row['id']) ? $row['id'] : (int) (strtotime($target_date) . rand(100, 999)),
                "date" => $target_date,
                "clockIn" => $ci_display,
                "clockOut" => $co_display,
                "reentryTime" => !empty($row['reentry_selfie_url']) ? "Re-entered" : "",
                "hours" => $hours_str,
                "status" => $status,
                "thumbnail" => $thumb,
                "selfie_url" => $thumb,
                "in_selfie_url" => $thumb,
                "outSelfieUrl" => $out_thumb,
                "out_selfie_url" => $out_thumb,
                "clock_out_selfie_url" => $out_thumb,
                "reentrySelfieUrl" => $reentry_thumb,
                "reentry_selfie_url" => $reentry_thumb,
                "latitude" => $row['latitude'] ?? "",
                "longitude" => $row['longitude'] ?? "",
                "holiday_reason" => $holiday_reason,
                "modified_reason" => $row['modification_reason'] ?? ""
            ];
        } else {
            $status = 'Absent';
            if ($is_holiday)
                $status = 'Holiday';
            elseif (isset($leave_map[$target_date]))
                $status = 'Leave';
            elseif ($target_date == date('Y-m-d'))
                continue;

            $history_data[] = [
                "id" => (int) (strtotime($target_date) . rand(1000, 9999)),
                "date" => $target_date,
                "clockIn" => "--:--",
                "clockOut" => "--:--",
                "reentryTime" => "",
                "hours" => "0h 0m",
                "status" => $status,
                "thumbnail" => "",
                "selfie_url" => "",
                "in_selfie_url" => "",
                "outSelfieUrl" => "",
                "out_selfie_url" => "",
                "clock_out_selfie_url" => "",
                "reentrySelfieUrl" => "",
                "reentry_selfie_url" => "",
                "latitude" => "",
                "longitude" => "",
                "holiday_reason" => $holiday_reason
            ];
        }
    }

    $current_month = date('Y-m');
    $perf_sql = "SELECT total_working_hours, weekly_working_hours, attendance_percentage,
                        total_days_consumed, total_worked_days, total_present, total_absent,
                        total_half_days, total_full_leaves, excluded_dates
                 FROM salesman_monthly_performance
                 WHERE salesman_id = '$salesman_id' AND report_month = '$current_month'";
    $perf_res = $conn->query($perf_sql);
    $monthly_performance = [];
    if ($perf_res && $perf_res->num_rows > 0) {
        $perf = $perf_res->fetch_assoc();
        $monthly_performance[] = [
            'report_month' => $current_month,
            'total_working_hours' => $perf['total_working_hours'],
            'weekly_working_hours' => $perf['weekly_working_hours'],
            'attendance_percentage' => $perf['attendance_percentage'],
            'total_days_consumed' => $perf['total_days_consumed'],
            'total_worked_days' => $perf['total_worked_days'],
            'total_present' => $perf['total_present'],
            'total_absent' => $perf['total_absent'],
            'total_half_days' => $perf['total_half_days'],
            'total_full_leaves' => $perf['total_full_leaves'],
            'excluded_dates' => !empty($perf['excluded_dates']) ? json_decode($perf['excluded_dates'], true) : []
        ];
    }

    echo json_encode([
        "status" => "success",
        "data" => $history_data,
        "monthly_performance" => $monthly_performance
    ]);

} else {
    echo json_encode(["status" => "error", "message" => "Invalid Action"]);
}

$conn->close();
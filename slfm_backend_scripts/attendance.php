<?php
// slfm_backend_scripts/attendance.php
// FULL VERSION: Includes All Tasks (1, 3, 4, 6) + Image Uploads + PERFORMANCE TRIGGER + GEOFENCING (150m)
// UPDATES: 
// 1. Database Storage: FIXED to use 24-Hour Format (H:i:s).
// 2. Performance Trigger: Calls update_performance.php after every status change.
// 3. Dynamic Shift Logic: Added custom_late_cutoff and shift_end_time overrides directly.
// 4. Removed 1-Hour Leave Penalty: Status remains unchanged if re-entry is not done within 1 hour.

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
// Location Input
$lat = $json_data['lat'] ?? $_POST['lat'] ?? null;
$lng = $json_data['lng'] ?? $_POST['lng'] ?? null;
$capture_time = $json_data['capture_time'] ?? $_POST['capture_time'] ?? null;
// 📱 DEVICE INPUT (NEW)
$device_id_used = $json_data['device_id'] ?? $_POST['device_id'] ?? '';
$device_model_used = $json_data['device_model'] ?? $_POST['device_model'] ?? '';
// Base URL for Images
$protocol = isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? "https" : "http";
$host = $_SERVER['HTTP_HOST'];
$script_dir = dirname($_SERVER['PHP_SELF']);
$script_dir = trim($script_dir, '/\\');
// FIX: Ensure forward slashes in URL (Windows Fix)
$script_dir = str_replace('\\', '/', $script_dir);
$base_url = "$protocol://$host/$script_dir/";

// Validate ID
if (empty($salesman_id)) {
    echo json_encode(["status" => "error", "message" => "Salesman ID is required"]);
    exit;
}

// ---------------------------------------------------------
// HELPER: TRIGGER PERFORMANCE UPDATE 🚀
// ---------------------------------------------------------
function triggerPerformanceUpdate($sid)
{
    global $base_url;
    // Construct URL to the calculator script
    $url = $base_url . "update_salesman_summary.php";

    // Prepare Data
    $data = json_encode(['salesman_id' => $sid]);

    // Send Input via POST (Fire and forget style with short timeout)
    $options = [
        'http' => [
            'header' => "Content-type: application/json\r\n",
            'method' => 'POST',
            'content' => $data,
            'ignore_errors' => true,
            'timeout' => 1 // Don't wait long for response
        ]
    ];
    $context = stream_context_create($options);
    @file_get_contents($url, false, $context);
}

// Global Time Variables
$date = date('Y-m-d');
// --- CRITICAL TIME SETTINGS (FIXED) ---
// 1. Internal Logic needs 24H (H:i:s) for comparisons
$current_time_str = date('H:i:s');
// 2. Display & Watermark needs 12H with AM/PM (h:i:s A)
$current_time_ampm = date('h:i:s A');
// 3. DATABASE STORAGE needs 24H (H:i:s)
$timestamp = date('Y-m-d H:i:s');
$current_ts_val = time();

if (!empty($capture_time)) {
    // Override times with capture_time for offline sync
    $capture_ts = strtotime($capture_time);
    if ($capture_ts !== false) {
        $current_time_str = date('H:i:s', $capture_ts);
        $current_time_ampm = date('h:i:s A', $capture_ts);
        $timestamp = date('Y-m-d H:i:s', $capture_ts);
        // CRITICAL RULE: The actual server logic should map exactly to the provided capture time
        $current_ts_val = $capture_ts;
    }
}

// ---------------------------------------------------------
// HELPER: DISTANCE CALCULATOR (GEOFENCING) 🌍
// ---------------------------------------------------------
function getDistanceInMeters($lat1, $lon1, $lat2, $lon2)
{
    if (empty($lat1) || empty($lon1) || empty($lat2) || empty($lon2))
        return 99999;
    $earth_radius = 6371000; // Earth radius in meters
    $dLat = deg2rad((float) $lat2 - (float) $lat1);
    $dLon = deg2rad((float) $lon2 - (float) $lon1);
    $a = sin($dLat / 2) * sin($dLat / 2) + cos(deg2rad((float) $lat1)) * cos(deg2rad((float) $lat2)) * sin($dLon / 2) * sin($dLon / 2);
    $c = 2 * asin(sqrt($a));
    return round($earth_radius * $c); // Returns distance in meters
}

// ---------------------------------------------------------
// FETCH SALESMAN DETAILS (Gender, Shift, Name) + DEVICE CHECK
// ---------------------------------------------------------
// Added custom_late_cutoff and shift_end_time to SELECT query
$salesman_sql = "SELECT shift_start_time, shift_end_time, custom_late_cutoff, showroom_name, gender, name, primary_device_id, allow_late_entry 
                 FROM salesmen WHERE salesman_id = '$salesman_id'";
$salesman_res = $conn->query($salesman_sql);

// Defaults
$shift_start_db = '09:30:00';
$shift_end_db = null;
$custom_late_cutoff = null;
$showroom_name = 'Main Branch';
$gender = 'male';
$salesman_name = $salesman_id;
$primary_device_id = ''; // Default empty

if ($salesman_res && $salesman_res->num_rows > 0) {
    $s_row = $salesman_res->fetch_assoc();
    $shift_start_db = $s_row['shift_start_time'] ?? '09:30:00';
    $shift_end_db = $s_row['shift_end_time'] ?? null;
    $custom_late_cutoff = $s_row['custom_late_cutoff'] ?? null;
    $showroom_name = $s_row['showroom_name'] ?? 'Main Branch';
    $gender = strtolower($s_row['gender'] ?? 'male');
    $salesman_name = $s_row['name'] ?? $salesman_id;
    $primary_device_id = $s_row['primary_device_id'] ?? '';
}
// 📱 PROXY CHECK LOGIC
$is_proxy_device = 0;
if (!empty($primary_device_id) && !empty($device_id_used)) {
    if ($primary_device_id !== $device_id_used) {
        $is_proxy_device = 1; // Flagged!
    }
}

// TASK 2: MANUAL OVERRIDE PERMISSION
$allow_late_entry = isset($s_row['allow_late_entry']) ? (int) $s_row['allow_late_entry'] : 0;

// ---------------------------------------------------------
// 🌍 GEOFENCING LOGIC (150 METER CHECK)
// ---------------------------------------------------------
$sh_lat = null;
$sh_lng = null;
$is_out_of_location = 0;
$location_distance = 0;
$admin_approval_val = "NULL";

$ALLOWED_RADIUS = 100; // 150 Meters allow pandrom accuracy issue kaga

// Fetch Showroom Location from new table
$sh_sql = "SELECT latitude, longitude FROM showrooms WHERE name = '" . $conn->real_escape_string($showroom_name) . "'";
$sh_res = $conn->query($sh_sql);
if ($sh_res && $sh_res->num_rows > 0) {
    $sh_row = $sh_res->fetch_assoc();
    $sh_lat = $sh_row['latitude'];
    $sh_lng = $sh_row['longitude'];
}

// Only check if lat/lng are provided and action is clock in/out
if ($action == 'clock_in' || $action == 'clock_out') {
    if (!empty($lat) && !empty($lng) && !empty($sh_lat) && !empty($sh_lng)) {
        $location_distance = getDistanceInMeters($lat, $lng, $sh_lat, $sh_lng);
        if ($location_distance > $ALLOWED_RADIUS) {
            $is_out_of_location = 1;
            $admin_approval_val = "'Pending'"; // Push to Admin Approval!
        }
    } elseif (empty($lat) || empty($lng)) {
        // If user didn't send GPS at all, flag it as out of location
        $is_out_of_location = 1;
        $location_distance = 99999;
        $admin_approval_val = "'Pending'";
    }
}

// ---------------------------------------------------------
// TIME RULES & CONFIGURATION
// ---------------------------------------------------------
// Task 1: Entry Cutoffs (DYNAMIC OVERRIDE)
$late_cutoff_time = !empty($custom_late_cutoff) ? $custom_late_cutoff : '10:00:59'; // Custom or Default Half Day starts
$leave_entry_cutoff = '15:00:59'; // 03:00 PM -> Leave starts (AND BLOCK if no permission)
// Task 3: Morning Half Day Exit Window
$morning_half_out_start = '14:30:00'; // 02:30 PM
$morning_half_out_end = '15:00:00'; // 03:00 PM

// Task 4: Full Day "Safe Exit" Window (DYNAMIC SHIFT OVERRIDE) 🚪
$standard_exit_time = ($gender == 'female') ? '20:00:00' : '21:00:00';
if (!empty($shift_end_db) && $shift_end_db < $standard_exit_time) {
    $full_day_exit_start = $shift_end_db;
} else {
    $full_day_exit_start = $standard_exit_time;
}

// Task 6: Resume Limit (Prevent Loophole)
$RESUME_LIMIT = 1; // Maximum times a user can re-enter per day

// ---------------------------------------------------------
// HELPER: SANITIZE URL (Fix Spaces & Slashes)
// ---------------------------------------------------------
function sanitizeUrl($url)
{
    if (empty($url))
        return "";
    $url = str_replace('\\', '/', $url); // Fix backslashes
    $url = str_replace(' ', '%20', $url); // Encode spaces
    return $url;
}
// ---------------------------------------------------------
// IMAGE WATERMARK FUNCTION
// ---------------------------------------------------------
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
        $font = 4;

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
        imagedestroy($im);
        return $data;
    }
    return $imageData;
}
// ---------------------------------------------------------
// ACTION: CLOCK IN (Includes Normal Entry & Re-Entry)
// ---------------------------------------------------------
if ($action == 'clock_in') {

    // Check if user is "Currently Clocked Out" (Potential Re-entry)
    $reentry_sql = "SELECT id, clock_in_time, clock_out_time, selfie_url, clock_out_selfie_url, status, resume_count, admin_approval 
                        FROM attendance 
                        WHERE salesman_id = '$salesman_id' AND date = '$date' AND clock_out_time IS NOT NULL";
    $reentry_res = $conn->query($reentry_sql);
    if ($reentry_res && $reentry_res->num_rows > 0) {
        // --- RE-ENTRY LOGIC STARTS HERE ---
        $re_row = $reentry_res->fetch_assoc();

        // strtotime works correctly with 24H format
        $last_out_time = strtotime($re_row['clock_out_time']);

        // FIX 11: If the incoming capture_time is BEFORE or EQUAL to the existing clock_out_time,
        // this is an old offline retry — NOT a genuine re-entry. Return duplicate to protect the record.
        if ($current_ts_val <= $last_out_time) {
            $existing_img = !empty($re_row['clock_out_selfie_url'])
                ? $re_row['clock_out_selfie_url']
                : (!empty($re_row['selfie_url']) ? $re_row['selfie_url'] : '');
            $existing_url = !empty($existing_img) ? sanitizeUrl($base_url . $existing_img) : null;

            echo json_encode([
                "status" => "duplicate",
                "message" => "இன்று ஏற்கனவே வருகை (In-Time) மற்றும் அவுட்-டைம் (Clock-Out) பதிவு செய்யப்பட்டுவிட்டது!",
                "image_url" => $existing_url,
                "clock_in_time" => $re_row['clock_in_time'],
                "clock_out_time" => $re_row['clock_out_time'],
                "final_status" => $re_row['status']
            ]);
            exit;
        }

        $diff_minutes = ($current_ts_val - $last_out_time) / 60;

        $current_resumes = isset($re_row['resume_count']) ? (int) $re_row['resume_count'] : 0;
        // Condition: Within 1 Hour (60 mins)
        if ($diff_minutes <= 60) {

            // 🛑 RULE: NO RE-ENTRY AFTER 6:00 PM
            if ($current_time_str > '18:00:00') {
                // Check if Manual Override Enabled
                if ($allow_late_entry !== 1) {
                    echo json_encode(["status" => "error", "message" => "முடிந்தது! இன்று In time மற்றும் Out time போட்டு விட்டீர்கள்! நாளை மீண்டும் முயற்சிக்கவும். 🙏"]);
                    exit;
                }
                // If allowed, proceed logic...
            }

            // CHECK 1: Resume Limit (Strict Block)
            if ($current_resumes >= $RESUME_LIMIT) {
                echo json_encode([
                    "status" => "error",
                    "message" => "Quota Exceeded: You have verified Break Re-entry ($RESUME_LIMIT) times today. Cannot enter again."
                ]);
                exit;
            }

            // CHECK 2: Recalculate Status based on ORIGINAL In-Time (Or Override)
            if ($allow_late_entry === 1) {
                $new_status = 'Present'; // Override to Present
            } else {
                $orig_in_time = strtotime($re_row['clock_in_time']);
                $limit_late = strtotime("$date $late_cutoff_time");
                $limit_leave = strtotime("$date $leave_entry_cutoff");
                $new_status = 'Present'; // Default
                if ($orig_in_time > $limit_leave) {
                    $new_status = 'Leave';
                } elseif ($orig_in_time > $limit_late) {
                    $new_status = 'Half Day';
                } else {
                    $new_status = 'Present';
                }
            }

            // CHECK 3: Handle Re-entry Image Upload
            $db_image_path = "";
            $base64_image = $json_data['selfie_url'] ?? $_POST['selfie_url'] ?? '';

            if (!empty($base64_image)) {
                $safe_showroom_name = preg_replace('/[^A-Za-z0-9\-]/', '_', $showroom_name);

                if (!is_dir("uploads")) {
                    @mkdir("uploads", 0777, true);
                }
                if (!is_dir("uploads/attendance")) {
                    @mkdir("uploads/attendance", 0777, true);
                }
                $upload_base_dir = "uploads/attendance/";
                $branch_dir = $upload_base_dir . $safe_showroom_name . "/";
                $date_dir = $branch_dir . $date . "/";
                if (!is_dir($date_dir)) {
                    if (!@mkdir($date_dir, 0777, true)) {
                        $date_dir = $upload_base_dir;
                    }
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
                        // RE-ENTRY Watermark
                        $time_text = "RE-ENTRY: $current_time_ampm";
                        $image_data = applyWatermark($image_data, $salesman_name, $showroom_name, $time_text);
                        $safe_name = preg_replace('/[^A-Za-z0-9\-]/', '_', $salesman_name);
                        $filename = $safe_name . "_" . $salesman_id . "_" . date("Y_m_d_H_i_s") . "_REENTRY.jpg";
                        $filepath = $date_dir . $filename;
                        if (@file_put_contents($filepath, $image_data)) {
                            $db_image_path = $filepath;
                        }
                    }
                }
            }
            // EXECUTE RESUME UPDATE
            $new_count = $current_resumes + 1;

            // Retain old admin approval UNLESS they are out of location right now
            $final_admin_approval = ($is_out_of_location == 1) ? "'Pending'" : ($re_row['admin_approval'] ? "'" . $re_row['admin_approval'] . "'" : "NULL");

            $resume_sql = "UPDATE attendance 
                               SET clock_out_time = NULL, 
                                   status = '$new_status', 
                                   resume_count = $new_count, 
                                   reentry_selfie_url = '$db_image_path',
                                   device_id_used = '$device_id_used',
                                   device_model_used = '$device_model_used',
                                   is_proxy_device = $is_proxy_device,
                                   is_out_of_location = $is_out_of_location,
                                   location_distance = $location_distance,
                                   admin_approval = $final_admin_approval
                               WHERE id = " . $re_row['id'];

            if ($conn->query($resume_sql) === TRUE) {
                // 🚀 TRIGGER
                triggerPerformanceUpdate($salesman_id);

                $msg = ($is_out_of_location == 1) ? "Resumed Work (Out of Location - Pending Admin Approval)." : "Resumed Work ($new_count/$RESUME_LIMIT). Status: $new_status.";

                echo json_encode([
                    "status" => "success",
                    "message" => $msg,
                    "action" => "resume",
                    "image_url" => $db_image_path ? sanitizeUrl($base_url . $db_image_path) : null
                ]);
                exit;
            }
        } else {
            // Task 6 Penalty: Gap > 1 Hour
            // 🔥 User Request Update: Do not change to Leave. Just block re-entry and keep old status.

            echo json_encode([
                "status" => "error",
                "message" => "Break exceeded 1 Hour. Re-entry not allowed, but your existing status is maintained."
            ]);
            exit;
        }
    }

    // --- NORMAL CLOCK IN (New Entry for the Day) ---

    // 🔥 TASK 1 & 2: BLOCK IF LATE (Unless Override)
    $cur_time_stamp = strtotime($current_time_str);
    $leave_cutoff_stamp = strtotime($leave_entry_cutoff);

    if ($cur_time_stamp > $leave_cutoff_stamp) {
        // It is after 3:00 PM
        if ($allow_late_entry != 1) {
            // 🛑 BLOCK
            echo json_encode([
                "status" => "error",
                "message" => "Login Time Ended (3:00 PM). Quota Finished. Contact Admin."
            ]);
            exit;
        }
    }

    $base64_image = $json_data['selfie_url'] ?? $_POST['selfie_url'] ?? '';
    $db_image_path = "";

    // Image Handling
    if (!empty($base64_image)) {
        $safe_showroom_name = preg_replace('/[^A-Za-z0-9\-]/', '_', $showroom_name);

        if (!is_dir("uploads")) {
            @mkdir("uploads", 0777, true);
        }
        if (!is_dir("uploads/attendance")) {
            @mkdir("uploads/attendance", 0777, true);
        }
        $upload_base_dir = "uploads/attendance/";
        $branch_dir = $upload_base_dir . $safe_showroom_name . "/";
        $date_dir = $branch_dir . $date . "/";
        if (!is_dir($date_dir)) {
            if (!@mkdir($date_dir, 0777, true)) {
                $date_dir = $upload_base_dir;
            }
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
                $time_text = "IN: $current_time_ampm";
                $image_data = applyWatermark($image_data, $salesman_name, $showroom_name, $time_text);
                $safe_name = preg_replace('/[^A-Za-z0-9\-]/', '_', $salesman_name);
                $filename = $safe_name . "_" . $salesman_id . "_" . date("Y_m_d_H_i_s") . "_IN.jpg";
                $filepath = $date_dir . $filename;
                if (@file_put_contents($filepath, $image_data)) {
                    $db_image_path = $filepath;
                }
            }
        }
    }

    // Logic: Determine Initial Status
    $status = 'Present';
    $is_late = 0;

    // Override Check
    if ($allow_late_entry == 1) {
        $status = 'Present'; // Force Present if override
        $is_late = 0; // Not counted as Late in system (or maybe 1 if owner wants record? User said "Present").
        // User said "athu present ha irukkalam".
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

    // Database Insert/Update
    $check_sql = "SELECT id, status FROM attendance WHERE salesman_id = '$salesman_id' AND date = '$date'";
    $result = $conn->query($check_sql);

    $lat_val = $lat ? "'$lat'" : "NULL";
    $lng_val = $lng ? "'$lng'" : "NULL";
    $d_id_val = $device_id_used ? "'$device_id_used'" : "NULL";
    $d_model_val = $device_model_used ? "'$device_model_used'" : "NULL";
    // 🔒 Tag this record if admin gave late-entry permission
    $late_entry_approved_val = ($allow_late_entry == 1) ? 1 : 0;

    if ($result && $result->num_rows == 0) {
        $sql = "INSERT INTO attendance (salesman_id, showroom_name, date, clock_in_time, selfie_url, status, is_late, latitude, longitude, resume_count, device_id_used, device_model_used, is_proxy_device, late_entry_approved, is_out_of_location, location_distance, admin_approval) 
                    VALUES ('$salesman_id', '$showroom_name', '$date', '$timestamp', '$db_image_path', '$status', '$is_late', $lat_val, $lng_val, 0, $d_id_val, $d_model_val, $is_proxy_device, $late_entry_approved_val, $is_out_of_location, $location_distance, $admin_approval_val)";

        if ($conn->query($sql) === TRUE) {
            // 🔥 FIX 1: Auto-cancel today's leave when salesman clocks in
            // If a leave was applied but salesman actually comes in, cancel it so
            // leave count is not wrongly debited.
            $conn->query("UPDATE leave_requests 
                          SET status = 'Cancelled' 
                          WHERE salesman_id = '$salesman_id' 
                          AND leave_date = '$date' 
                          AND status IN ('Approved', 'Pending')");

            $msg_out_loc_new = "உங்களுக்கு குறிக்கப்பட்ட $showroom_name -ல் இருந்து Photo போடவெண்டும். ஒருவேளை $showroom_name -ல் இருந்து Photo போட்டாலும், உங்கள் Location-ஐ உங்கள் மொபைல் தவறாக எடுத்துள்ளது என்று அர்த்தம்! கவலை படாதீர்கள், நீங்கள் $status. OK!!";

            $msg = ($is_out_of_location == 1) ? $msg_out_loc_new : "Clocked In ($status)";

            echo json_encode([
                "status" => "success",
                "message" => $msg,
                "image_url" => $db_image_path ? sanitizeUrl($base_url . $db_image_path) : null
            ]);
        } else {
            echo json_encode(["status" => "error", "message" => "DB Insert Error: " . $conn->error]);
        }
    } else {
        $row = $result->fetch_assoc();
        $att_status_lower = strtolower($row['status'] ?? '');
        $is_allowed_to_update = ($att_status_lower == 'absent' ||
            $att_status_lower == 'leave' ||
            strpos($att_status_lower, 'on leave') === 0);

        if ($is_allowed_to_update) {
            $update_sql = "UPDATE attendance 
                               SET clock_in_time = '$timestamp', status = '$status', is_late = '$is_late', 
                                   selfie_url = '$db_image_path', showroom_name = '$showroom_name',
                                   latitude = $lat_val, longitude = $lng_val, resume_count = 0,
                                   device_id_used = $d_id_val, device_model_used = $d_model_val, is_proxy_device = $is_proxy_device,
                                   late_entry_approved = $late_entry_approved_val,
                                   is_out_of_location = $is_out_of_location,
                                   location_distance = $location_distance,
                                   admin_approval = $admin_approval_val
                               WHERE id = " . $row['id'];

            if ($conn->query($update_sql) === TRUE) {
                // 🔥 FIX 1: Also cancel today's leave when updating an absent/leave attendance record
                $conn->query("UPDATE leave_requests 
                              SET status = 'Cancelled' 
                              WHERE salesman_id = '$salesman_id' 
                              AND leave_date = '$date' 
                              AND status IN ('Approved', 'Pending')");

                $msg_out_loc = "உங்களுக்கு குறிக்கப்பட்ட $showroom_name -ல் இருந்து Photo போடவெண்டும். ஒருவேளை $showroom_name -ல் இருந்து Photo போட்டாலும், உங்கள் Location-ஐ உங்கள் மொபைல் தவறாக எடுத்துள்ளது என்று அர்த்தம்! கவலை படாதீர்கள், நீங்கள் $status. OK!!";

                $msg = ($is_out_of_location == 1) ? $msg_out_loc : "உங்கள் வருகை பதிவு செய்யப்பட்டது (பழைய $att_status_lower ரத்து செய்யப்பட்டது)";

                echo json_encode([
                    "status" => "success",
                    "message" => $msg,
                    "image_url" => $db_image_path ? sanitizeUrl($base_url . $db_image_path) : null
                ]);
            } else {
                echo json_encode(["status" => "error", "message" => "DB Update Error: " . $conn->error]);
            }
        } else {
            echo json_encode(["status" => "error", "message" => "Already Clocked In today! Current status: " . $row['status']]);
        }
    }
}
// ---------------------------------------------------------
// ACTION: CLOCK OUT
// ---------------------------------------------------------
elseif ($action == 'clock_out') {
    $check_sql = "SELECT clock_in_time, status, resume_count, is_out_of_location, location_distance, admin_approval FROM attendance WHERE salesman_id = '$salesman_id' AND date = '$date' AND clock_out_time IS NULL";
    $res = $conn->query($check_sql);
    if ($res && $res->num_rows > 0) {
        $row = $res->fetch_assoc();

        // Calculate End Status
        $clock_out_logic = strtotime($current_time_str);
        $final_status = $row['status'];

        $m_half_start = strtotime($morning_half_out_start);
        $m_half_end = strtotime($morning_half_out_end);
        $exit_start_val = strtotime($full_day_exit_start);

        if ($final_status == 'Present' || $final_status == 'Half Day') {

            // Get Clock In Time
            $in_time_val = strtotime($row['clock_in_time']);
            $afternoon_start_val = strtotime("$date 15:00:59");

            // --- SCENARIO A: AFTERNOON START (Came after 3 PM) ---
            if ($in_time_val > $afternoon_start_val) {
                // Rule: Must stay until End Time (9 PM / 8 PM)
                if ($clock_out_logic < $exit_start_val) {
                    $final_status = 'Leave'; // 🛑 Too short duration for Afternoon Shift
                }
                // Else: If they stayed till 9 PM, they keep their status (Present/Half Day)
            }
            // --- SCENARIO B: MORNING START (Came before 3 PM) ---
            else {
                // Case 1: Early Exit (Before 2:30 PM) -> Leave
                if ($clock_out_logic < $m_half_start) {
                    $final_status = 'Leave';
                }
                // Case 2: Mid-Day Exit (2:30 PM - 3:00 PM) -> Half Day
                elseif ($clock_out_logic >= $m_half_start && $clock_out_logic <= $m_half_end) {
                    $final_status = 'Half Day';
                }
                // Case 3: Early Evening Exit (Before Gender Safe Time)
                elseif ($clock_out_logic < $exit_start_val) {
                    // Logic Update:
                    // If started as Present -> Downgrade to Half Day
                    // If started as Half Day -> Downgrade to Leave (As per user request)
                    if ($final_status == 'Half Day') {
                        $final_status = 'Leave';
                    } else {
                        $final_status = 'Half Day';
                    }
                }
                // Case 4: After Safe Time -> Status Remains (Present is Present)
            }
        }
        // --- CLOCK OUT IMAGE UPLOAD ---
        $db_image_path = "";
        $base64_image = $json_data['selfie_url'] ?? $_POST['selfie_url'] ?? '';

        if (!empty($base64_image)) {
            $safe_showroom_name = preg_replace('/[^A-Za-z0-9\-]/', '_', $showroom_name);
            if (!is_dir("uploads")) {
                @mkdir("uploads", 0777, true);
            }
            if (!is_dir("uploads/attendance")) {
                @mkdir("uploads/attendance", 0777, true);
            }
            $upload_base_dir = "uploads/attendance/";
            $branch_dir = $upload_base_dir . $safe_showroom_name . "/";
            $date_dir = $branch_dir . $date . "/";
            if (!is_dir($date_dir)) {
                if (!@mkdir($date_dir, 0777, true)) {
                    $date_dir = $upload_base_dir;
                }
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
                    $time_text = "OUT: $current_time_ampm";
                    $image_data = applyWatermark($image_data, $salesman_name, $showroom_name, $time_text);
                    $safe_name = preg_replace('/[^A-Za-z0-9\-]/', '_', $salesman_name);
                    $filename = $safe_name . "_" . $salesman_id . "_" . date("Y_m_d_H_i_s") . "_OUT.jpg";
                    $filepath = $date_dir . $filename;
                    if (@file_put_contents($filepath, $image_data)) {
                        $db_image_path = $filepath;
                    }
                }
            }
        }

        // 🌍 Check if OUT punch is outside Geofence
        $out_is_out = $row['is_out_of_location']; // keep previous value by default
        $out_distance = $row['location_distance'];
        $out_admin_approval = $row['admin_approval'] ? "'" . $row['admin_approval'] . "'" : "NULL";

        if ($is_out_of_location == 1) {
            $out_is_out = 1; // Mark as out
            $out_distance = $location_distance; // Update with new far distance
            $out_admin_approval = "'Pending'"; // Force to pending if they clocked out from home!
        }

        // 🔥 Out-Time location values
        $out_lat_val = $lat ? "'$lat'" : "NULL";
        $out_lng_val = $lng ? "'$lng'" : "NULL";

        // DB Update
        $resume_count = isset($row['resume_count']) ? (int) $row['resume_count'] : 0;

        if ($resume_count > 0) {
            // This is Final Exit (after re-entry)
            $sql = "UPDATE attendance 
                    SET clock_out_time = '$timestamp', 
                        status = '$final_status', 
                        final_out_selfie_url = '$db_image_path',
                        is_out_of_location = $out_is_out,
                        location_distance = $out_distance,
                        admin_approval = $out_admin_approval,
                        out_latitude = $out_lat_val,
                        out_longitude = $out_lng_val
                    WHERE salesman_id = '$salesman_id' AND date = '$date'";
        } else {
            // This is Break Out (First time clock out)
            $sql = "UPDATE attendance 
                    SET clock_out_time = '$timestamp', 
                        status = '$final_status', 
                        clock_out_selfie_url = '$db_image_path',
                        is_out_of_location = $out_is_out,
                        location_distance = $out_distance,
                        admin_approval = $out_admin_approval,
                        out_latitude = $out_lat_val,
                        out_longitude = $out_lng_val
                    WHERE salesman_id = '$salesman_id' AND date = '$date'";
        }

        if ($conn->query($sql) === TRUE) {
            // 🚀 TRIGGER
            triggerPerformanceUpdate($salesman_id);

            $msg = ($is_out_of_location == 1) ? "Clocked Out (Out of Location - Pending Approval)" : "Clocked Out. Status: $final_status";

            echo json_encode([
                "status" => "success",
                "message" => $msg,
                "final_status" => $final_status,
                "image_url" => $db_image_path ? sanitizeUrl($base_url . $db_image_path) : null
            ]);
        } else {
            echo json_encode(["status" => "error", "message" => "DB Error: " . $conn->error]);
        }
    } else {
        echo json_encode(["status" => "error", "message" => "You haven't clocked in today or already clocked out!"]);
    }
}
// ---------------------------------------------------------
// ACTION: GET SUMMARY & HISTORY
// ---------------------------------------------------------
elseif ($action == 'get_summary' || $action == 'get_history') {

    if ($action == 'get_summary') {
        // 🎉 CHECK IF TODAY IS A HOLIDAY FIRST
        $holiday_sql = "SELECT reason FROM holidays WHERE holiday_date = '$date' LIMIT 1";
        $holiday_res = $conn->query($holiday_sql);

        $today_sql = "SELECT id, clock_in_time, clock_out_time, status, showroom_name, resume_count, selfie_url, clock_out_selfie_url, reentry_selfie_url, final_out_selfie_url FROM attendance WHERE salesman_id = '$salesman_id' AND date = '$date'";
        $today_res = $conn->query($today_sql);

        $response = [
            "clock_in" => null,
            "clock_out" => null,
            "resume_count" => 0,
            "attendance_status" => "Not Marked",
            "attendance_rate" => "0%",
            "month_hours" => "0h 0m",
            "week_hours" => "0h 0m"
        ];

        // 🎉 IF TODAY IS HOLIDAY, OVERRIDE STATUS
        if ($holiday_res && $holiday_res->num_rows > 0) {
            $h_row = $holiday_res->fetch_assoc();
            $reason = $h_row['reason'] ?? 'Holiday';
            $response['attendance_status'] = "Holiday ($reason)";
            $response['holiday_reason'] = $reason;
        } elseif ($today_res && $today_res->num_rows > 0) {
            $row = $today_res->fetch_assoc();

            // --- AUTO-UPDATE Check ---
            // 🔥 REMOVED auto-leave penalty for exceeding 1 hour break. Existing status remains unchanged!

            $response['clock_in'] = $row['clock_in_time'];
            $response['clock_out'] = $row['clock_out_time'];
            $response['resume_count'] = (int) ($row['resume_count'] ?? 0);
            $response['attendance_status'] = $row['status'];
            $response['showroom_name'] = $row['showroom_name'];
            $response['selfie_url'] = !empty($row['selfie_url']) ? sanitizeUrl($base_url . $row['selfie_url']) : null;
            $response['clock_out_selfie_url'] = !empty($row['final_out_selfie_url']) ? sanitizeUrl($base_url . $row['final_out_selfie_url']) : (!empty($row['clock_out_selfie_url']) ? sanitizeUrl($base_url . $row['clock_out_selfie_url']) : null);
            $response['reentry_selfie_url'] = !empty($row['reentry_selfie_url']) ? sanitizeUrl($base_url . $row['reentry_selfie_url']) : null;
        } else {
            // Check Leave Request
            $leave_res = $conn->query("SELECT leave_type FROM leave_requests WHERE salesman_id = '$salesman_id' AND leave_date = '$date' AND status != 'Rejected' LIMIT 1");
            if ($leave_res && $leave_res->num_rows > 0) {
                $l_row = $leave_res->fetch_assoc();
                $response['attendance_status'] = "On Leave (" . $l_row['leave_type'] . ")";
            }
        }
        // 🔥 FETCH PERFORMANCE FROM summary table
        $current_month = date('Y-m');
        // UPDATED: Select more columns (total_worked_days, excluded_dates)
        $perf_sql = "SELECT total_working_hours, weekly_working_hours, attendance_percentage, total_days_consumed, total_worked_days, total_present, total_half_days, excluded_dates FROM salesman_monthly_performance WHERE salesman_id = '$salesman_id' AND report_month = '$current_month'";
        $perf_res = $conn->query($perf_sql);

        // Defaults
        $response['total_worked_days'] = "0";
        $response['total_leaves_used'] = "0";
        $response['excluded_dates'] = []; // 🔥 Default Empty List

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

            // 🆕 New Metrics
            $leaves_used = (float) ($perf['total_days_consumed'] ?? 0);
            $present = (int) ($perf['total_present'] ?? 0);
            $half = (int) ($perf['total_half_days'] ?? 0);

            // Use stored Total Worked Days if available, else calculate fallback
            $worked = isset($perf['total_worked_days']) ? (float) $perf['total_worked_days'] : ($present + ($half * 0.5));

            $response['total_worked_days'] = (string) $worked;
            $response['total_leaves_used'] = (string) $leaves_used;

            // 🔥 Parse Excluded Dates
            if (!empty($perf['excluded_dates'])) {
                $response['excluded_dates'] = json_decode($perf['excluded_dates'], true) ?? [];
            }
        }
        echo json_encode(["status" => "success", "data" => $response]);
    }

    if ($action == 'get_history') {
        $history_data = [];
        $end_date = date('Y-m-d');
        $start_date = date('Y-m-d', strtotime('-40 days'));

        // 1. Fetch Attendance
        $att_sql = "SELECT * FROM attendance WHERE salesman_id = '$salesman_id' AND date >= '$start_date' AND date <= '$end_date'";
        $att_res = $conn->query($att_sql);
        $att_map = [];
        if ($att_res) {
            while ($row = $att_res->fetch_assoc()) {
                $att_map[$row['date']] = $row;
            }
        }

        // 2. Fetch Holidays
        $hol_sql = "SELECT holiday_date, reason FROM holidays WHERE holiday_date >= '$start_date' AND holiday_date <= '$end_date'";
        $hol_res = $conn->query($hol_sql);
        $hol_map = [];
        if ($hol_res) {
            while ($row = $hol_res->fetch_assoc()) {
                $hol_map[$row['holiday_date']] = $row['reason'] ?? 'Holiday';
            }
        }

        // 3. Fetch Approved Leaves
        $leave_sql = "SELECT leave_date FROM leave_requests WHERE salesman_id = '$salesman_id' AND leave_date >= '$start_date' AND leave_date <= '$end_date' AND status = 'Approved'";
        $leave_res = $conn->query($leave_sql);
        $leave_map = [];
        if ($leave_res) {
            while ($row = $leave_res->fetch_assoc()) {
                $leave_map[$row['leave_date']] = true;
            }
        }

        // Loop through the last 30 days
        for ($i = 0; $i < 40; $i++) {
            $target_date = date('Y-m-d', strtotime("-$i days", strtotime($end_date)));

            $is_holiday = isset($hol_map[$target_date]);
            $holiday_reason = $is_holiday ? $hol_map[$target_date] : "";

            if (isset($att_map[$target_date])) {
                $row = $att_map[$target_date];
                $hours_str = "0h 0m";
                if (!empty($row['clock_in_time']) && !empty($row['clock_out_time'])) {
                    $start = new DateTime($row['clock_in_time']);
                    $end = new DateTime($row['clock_out_time']);
                    $interval = $start->diff($end);
                    $hours_str = $interval->format('%hh %im');
                } elseif (!empty($row['clock_in_time']) && $row['status'] != 'Absent') {
                    $hours_str = "Ongoing";
                }

                $thumb = !empty($row['selfie_url']) ? sanitizeUrl($base_url . $row['selfie_url']) : "assets/images/no-image.jpg";
                $out_thumb = !empty($row['final_out_selfie_url']) ? sanitizeUrl($base_url . $row['final_out_selfie_url']) : (!empty($row['clock_out_selfie_url']) ? sanitizeUrl($base_url . $row['clock_out_selfie_url']) : "");
                $reentry_thumb = !empty($row['reentry_selfie_url']) ? sanitizeUrl($base_url . $row['reentry_selfie_url']) : "";

                $ci_display = $row['clock_in_time'] ? date('h:i:s A', strtotime($row['clock_in_time'])) : "--:--";
                $co_display = $row['clock_out_time'] ? date('h:i:s A', strtotime($row['clock_out_time'])) : "--:--";

                if ($is_holiday) {
                    $status = "Holiday";
                } else {
                    $status = $row['status'];
                    if (empty($status))
                        $status = 'not_logged_in';
                }

                // Add an explicit 'id' ensuring Flutter SQLite doesn't crash on insert
                $history_data[] = [
                    "id" => isset($row['id']) ? $row['id'] : (int) (strtotime($target_date) . rand(100, 999)),
                    "date" => $target_date,
                    "clockIn" => $ci_display,
                    "clockOut" => $co_display,
                    "reentryTime" => !empty($row['reentry_selfie_url']) && !empty($row['clock_out_time']) ? date('h:i:s A', strtotime($row['clock_in_time']) + 3600) : "",
                    "hours" => $hours_str,
                    "status" => $status,
                    "thumbnail" => $thumb,
                    "outSelfieUrl" => $out_thumb,
                    "reentrySelfieUrl" => $reentry_thumb,
                    "latitude" => $row['latitude'] ?? "",
                    "longitude" => $row['longitude'] ?? "",
                    "holiday_reason" => $holiday_reason
                ];
            } else {
                $status = 'Absent';
                if ($is_holiday) {
                    $status = 'Holiday';
                } elseif (isset($leave_map[$target_date])) {
                    $status = 'Leave';
                } elseif ($target_date == date('Y-m-d')) {
                    // 🔥 EXTREMELY CRITICAL FIX: DO NOT prematurely mark today as Absent just because there is no punch!
                    // The day is still ongoing. Just skip adding today to history array until they punch.
                    continue;
                }

                // Add an explicit 'id' fallback for dates without records
                $history_data[] = [
                    "id" => (int) (strtotime($target_date) . rand(1000, 9999)),
                    "date" => $target_date,
                    "clockIn" => "--:--",
                    "clockOut" => "--:--",
                    "reentryTime" => "",
                    "hours" => "0h 0m",
                    "status" => $status,
                    "thumbnail" => "",
                    "outSelfieUrl" => "",
                    "reentrySelfieUrl" => "",
                    "latitude" => "",
                    "longitude" => "",
                    "holiday_reason" => $holiday_reason
                ];
            }
        }
        echo json_encode(["status" => "success", "data" => $history_data]);
    }
} else {
    echo json_encode(["status" => "error", "message" => "Invalid Action"]);
}
$conn->close();
?>
<?php
// api/cron_lunch_window.php
// This script is meant to be run via a cron job every minute.
// It checks the current time and updates the Firebase Realtime Database
// to open or lock the lunch window.

error_reporting(E_ALL);
ini_set('display_errors', 1);

date_default_timezone_set('Asia/Kolkata');

// Firebase RTDB URL for the whole object
$BASE_URL = "https://admin-decd9-default-rtdb.asia-southeast1.firebasedatabase.app/settings/lunch_window.json";

// 1. Fetch current settings to check mode
$ch = curl_init($BASE_URL);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
$response = curl_exec($ch);
curl_close($ch);

$settings = json_decode($response, true);
$mode = $settings['mode'] ?? 'auto';

if ($mode === 'manual') {
    exit(json_encode(["status" => "ignored", "message" => "Manual mode active. Unlimited open maintained."]));
}

// 2. Auto mode logic: Lock between 1 PM and 4 PM
$LUNCH_START = '13:00:00'; // 1:00 PM
$LUNCH_END   = '16:00:00'; // 4:00 PM

$current_time = date('H:i:s');
// is_open is TRUE (Unlocked) if current time is between 1 PM and 4 PM
$is_open = ($current_time >= $LUNCH_START && $current_time <= $LUNCH_END) ? true : false;

// 3. Update Firebase only if state needs to change
if ($settings['is_open'] !== $is_open) {
    $ch = curl_init($BASE_URL);
    curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "PATCH");
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode(["is_open" => $is_open]));
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
    $response = curl_exec($ch);
    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($http_code >= 200 && $http_code < 300) {
        echo json_encode(["status" => "success", "message" => "Auto-updated lunch window.", "is_open" => $is_open]);
    } else {
        echo json_encode(["status" => "error", "message" => "Failed to update Firebase."]);
    }
} else {
    echo json_encode(["status" => "success", "message" => "Already in correct state.", "is_open" => $is_open]);
}
?>

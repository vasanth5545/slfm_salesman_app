<?php
// billing_counter/admin_location.php
// FIXED: Ensures proper Lat/Lng retrieval for Map

date_default_timezone_set('Asia/Kolkata');
header("Content-Type: application/json");
require '../db_connect.php';

// Sync MySQL Timezone (CRITICAL for tracking trigger)
$conn->query("SET time_zone = '+05:30'");

$action = $_POST['action'] ?? '';
$now_time = date('Y-m-d H:i:s'); 

// ---------------------------------------------------------
// 1. GET ALL LOCATIONS
// ---------------------------------------------------------
if ($action == 'get_all_locations') {
    
    $showroom = $_POST['showroom'] ?? ''; // 🔥 Capture Showroom

    // Added 'gps_status'
    $sql = "SELECT id, salesman_id, name, showroom_name, 
            current_lat, current_lng, last_location_update, last_sync, 
            is_tracking, tracking_expiry, gps_status 
            FROM salesmen 
            WHERE status = 'Active'";
    
    // 🔥 Apply Showroom Filter (Loose Matching)
    if (!empty($showroom)) {
        $safe_showroom = $conn->real_escape_string($showroom);
        // Use TRIM and LIKE to avoid mismatch due to spaces
        $sql .= " AND TRIM(showroom_name) LIKE TRIM('$safe_showroom')";
    }
            
    $result = $conn->query($sql);
    $salesmen = [];

    if ($result) {
        while($row = $result->fetch_assoc()) {
            
            // Time calculation for Online/Offline
            $last_sync_dt = new DateTime($row['last_sync'] ?? 'now');
            $now_dt = new DateTime("now"); 
            $diff_seconds = $now_dt->getTimestamp() - $last_sync_dt->getTimestamp();
            
            // 5 Mins Timeout logic
            $is_online = $diff_seconds < 300; 

            // Tracking Active check
            $expiry_str = $row['tracking_expiry'] ?? '2000-01-01 00:00:00';
            $is_tracking_active = ($row['is_tracking'] == 1) && ($expiry_str > $now_time);

            $salesmen[] = [
                'salesman_id' => $row['salesman_id'],
                'name' => $row['name'],
                'showroom_name' => $row['showroom_name'] ?? 'Main Branch',
                // Floatval ensures we don't get strings or nulls
                'lat' => floatval($row['current_lat']),
                'lng' => floatval($row['current_lng']),
                'last_update' => $row['last_location_update'], 
                'is_online' => $is_online,
                'is_tracking' => $is_tracking_active,
                'gps_status' => $row['gps_status'] ?? 'ON' 
            ];
        }
    }

    echo json_encode(["status" => "success", "data" => $salesmen]);
}
// ---------------------------------------------------------
// 2. TRIGGER TRACKING (Fixes "Click to Track" issue)
// ---------------------------------------------------------
else if ($action == 'toggle_tracking') {
    $salesman_id = $_POST['salesman_id'] ?? '';
    $status = $_POST['status'] ?? '0';

    if (empty($salesman_id)) {
        echo json_encode(["status" => "error", "message" => "Salesman ID required"]);
        exit;
    }

    if ($status == '1') {
        // Enable for 5 Minutes
        $expiry_time = date('Y-m-d H:i:s', strtotime('+5 minutes'));
        $sql = "UPDATE salesmen SET is_tracking = 1, tracking_expiry = ? WHERE salesman_id = ?";
        $stmt = $conn->prepare($sql);
        $stmt->bind_param("ss", $expiry_time, $salesman_id);
    } else {
        // Disable
        $sql = "UPDATE salesmen SET is_tracking = 0 WHERE salesman_id = ?";
        $stmt = $conn->prepare($sql);
        $stmt->bind_param("s", $salesman_id);
    }

    if ($stmt->execute()) {
        // 🔥 INSTANT FIX: Fetch the current location immediately to send back
        $loc_sql = "SELECT current_lat, current_lng, gps_status FROM salesmen WHERE salesman_id = '$salesman_id'";
        $loc_res = $conn->query($loc_sql);
        $loc_data = $loc_res->fetch_assoc();

        echo json_encode([
            "status" => "success", 
            "message" => "Tracking Updated",
            // Return location data instantly
            "lat" => $loc_data['current_lat'],
            "lng" => $loc_data['current_lng'],
            "gps_status" => $loc_data['gps_status']
        ]);
    } else {
        echo json_encode(["status" => "error", "message" => "DB Error"]);
    }
} 
?>

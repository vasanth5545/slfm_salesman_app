<?php
// slfm_api/location_update.php
// FIXED: Debugging Added & Decimal Precision Fixed

date_default_timezone_set('Asia/Kolkata');
header("Content-Type: application/json");

// Error Reporting ON (For Debugging)
ini_set('display_errors', 0);
ini_set('log_errors', 1);
error_reporting(E_ALL);

require 'db_connect.php';

// Sync MySQL Timezone
$conn->query("SET time_zone = '+05:30'");

// ---------------------------------------------------------
// 🔥 DEBUGGING LOG (Creates a file named 'gps_debug.txt')
// ---------------------------------------------------------
// $log_data = "---------------------------------\n";
// $log_data .= "Time: " . date('Y-m-d H:i:s') . "\n";
// $log_data .= "POST Data: " . print_r($_POST, true) . "\n";
// file_put_contents('gps_debug.txt', $log_data, FILE_APPEND);
// ---------------------------------------------------------
$action = $_POST['action'] ?? '';
$salesman_id = trim($_POST['salesman_id'] ?? '');

if (empty($salesman_id)) {
    echo json_encode(["status" => "error", "message" => "Salesman ID Missing"]);
    exit;
}

$now_time = date('Y-m-d H:i:s');

// ---------------------------------------------------------
// 1. UPDATE LOCATION
// ---------------------------------------------------------
if ($action == 'update_location') {
    // 🔥 FIX: Don't use floatval(), take as STRING to save precision
    $lat = $_POST['lat'] ?? '0';
    $lng = $_POST['lng'] ?? '0';

    // Strict Check: If values are 0 or empty string
    if ($lat == '0' || $lng == '0' || empty($lat) || empty($lng)) {
        // Just update heartbeat
        $conn->query("UPDATE salesmen SET last_sync = '$now_time' WHERE salesman_id = '$salesman_id'");
        echo json_encode(["status" => "error", "message" => "GPS Coordinates are 0 (Ignored)"]);
        exit;
    }

    // A. UPDATE SALESMEN TABLE
    // Uses "sssss" to treat Lat/Lng as Strings (Best for DECIMAL columns)
    $sql_live = "UPDATE salesmen SET 
            current_lat = ?, 
            current_lng = ?, 
            last_location_update = ?,
            last_sync = ?,
            gps_status = 'ON' 
            WHERE salesman_id = ?";
            
    $stmt_live = $conn->prepare($sql_live);
    
    // Bind Params: lat(s), lng(s), time(s), time(s), id(s)
    $stmt_live->bind_param("sssss", $lat, $lng, $now_time, $now_time, $salesman_id);
    
    if ($stmt_live->execute()) {
        if ($stmt_live->affected_rows > 0) {
            echo json_encode(["status" => "success", "message" => "Live Location Updated"]);
        } else {
            // Rows matched but no change (Salesman standing in same place)
            echo json_encode(["status" => "success", "message" => "Location Same (Updated Sync Time)"]);
        }
    } else {
        // Print SQL Error for debugging
        echo json_encode(["status" => "error", "message" => "SQL Error: " . $stmt_live->error]);
    }
    $stmt_live->close();
}

// ---------------------------------------------------------
// 2. CHECK STATUS
// ---------------------------------------------------------
else if ($action == 'check_status') {
    
    // Heartbeat Update
    $heartbeat_sql = "UPDATE salesmen SET last_sync = ? WHERE salesman_id = ?";
    $hb_stmt = $conn->prepare($heartbeat_sql);
    $hb_stmt->bind_param("ss", $now_time, $salesman_id);
    $hb_stmt->execute();

    // Check Status
    $sql = "SELECT is_tracking, tracking_expiry FROM salesmen WHERE salesman_id = ?";
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("s", $salesman_id);
    $stmt->execute();
    $result = $stmt->get_result();

    if ($row = $result->fetch_assoc()) {
        $is_tracking = $row['is_tracking'];
        $expiry = $row['tracking_expiry'];

        if (empty($expiry)) {
            $expiry = '2000-01-01 00:00:00';
        }

        if ($is_tracking == 1 && $expiry < $now_time) {
            // Expired -> Turn OFF
            $conn->query("UPDATE salesmen SET is_tracking = 0 WHERE salesman_id = '$salesman_id'");
            echo json_encode(["status" => "success", "tracking_enabled" => false, "msg" => "Expired"]);
        } else {
            echo json_encode([
                "status" => "success", 
                "tracking_enabled" => ($is_tracking == 1)
            ]);
        }
    } else {
        echo json_encode(["status" => "error", "message" => "Salesman Not Found"]);
    }
} 

// ---------------------------------------------------------
// 3. GPS STATUS ALERT
// ---------------------------------------------------------
else if ($action == 'gps_status_alert') {
    $gps_status = $_POST['gps_status'] ?? 'ON';
    
    $sql = "UPDATE salesmen SET gps_status = ? WHERE salesman_id = ?";
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("ss", $gps_status, $salesman_id);
    
    if ($stmt->execute()) {
        echo json_encode(["status" => "success", "message" => "GPS Status Updated"]);
    } else {
        echo json_encode(["status" => "error", "message" => "DB Error"]);
    }
}

else {
    echo json_encode(["status" => "error", "message" => "Invalid Action"]);
}

$conn->close();
?>

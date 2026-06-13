<?php
// billing_counter/walking_stats.php
// Returns Salesman-wise Walking Customer Stats & Details
// FIXED: Generates FULL URL for bill_photo so Billing App can open it directly.
// TIMEZONE FIX: Enforced Asia/Kolkata

header("Content-Type: application/json");

// 🔥 CRITICAL: Set Timezone to Kolkata
date_default_timezone_set('Asia/Kolkata');

require '../db_connect.php';

$action = $_POST['action'] ?? '';

// --- HELPER: Get Dynamic Base URL ---
// This automatically detects http/https and the folder path (slfm_api)
function getBaseUrl() {
    $protocol = isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? "https" : "http";
    $host = $_SERVER['HTTP_HOST'];
    // Current script is in /slfm_api/billing_counter/
    // dirname($_SERVER['PHP_SELF']) -> /slfm_api/billing_counter
    // dirname(...) again -> /slfm_api
    $project_root = dirname(dirname($_SERVER['PHP_SELF']));
    
    // Ensure properly formatted URL with trailing slash
    return "$protocol://$host" . rtrim($project_root, '/\\') . "/";
}

// 1. GET SALESMAN STATS (Overview)
if ($action == 'get_summary') {
    // Shows Salesman Name, Pending Count, Billed Count AND Last Sync
    $sql = "SELECT 
                s.salesman_id, 
                s.name, 
                s.showroom_name,
                s.last_sync, 
                COUNT(CASE WHEN w.status = 'Pending' THEN 1 END) as pending_count,
                COUNT(CASE WHEN w.status = 'Billed' THEN 1 END) as billed_count
            FROM salesmen s
            LEFT JOIN walking_customers w ON s.salesman_id = w.salesman_id
            WHERE s.status = 'Active'
            GROUP BY s.salesman_id
            ORDER BY pending_count DESC";

    $result = $conn->query($sql);
    $data = [];
    if ($result) {
        while($row = $result->fetch_assoc()) {
            $data[] = $row;
        }
    }
    echo json_encode(["status" => "success", "data" => $data]);
}

// 2. GET CUSTOMER LIST FOR A SALESMAN (FIXED PHOTO URL)
elseif ($action == 'get_customers') {
    $salesman_id = $_POST['salesman_id'] ?? '';
    
    if(empty($salesman_id)) {
        echo json_encode(["status" => "error", "message" => "ID Required"]);
        exit;
    }

    $safe_id = $conn->real_escape_string($salesman_id);
    $base_url = getBaseUrl(); // Get dynamic base URL

    $sql = "SELECT * FROM walking_customers 
            WHERE salesman_id = '$safe_id' 
            ORDER BY created_at DESC LIMIT 50";
            
    $result = $conn->query($sql);
    $data = [];
    if ($result) {
        while($row = $result->fetch_assoc()) {
            
            // 🔥 FIX: Convert Relative Path to Full URL
            if (!empty($row['bill_photo'])) {
                // If the path already has 'http', keep it. Otherwise, prepend Base URL.
                if (strpos($row['bill_photo'], 'http') !== 0) {
                    // Example: http://host/slfm_api/ + uploads/bills/abc.jpg
                    $full_url = $base_url . ltrim($row['bill_photo'], '/');
                    
                    // OVERWRITE the 'bill_photo' key because Flutter uses this first
                    $row['bill_photo'] = $full_url;
                    $row['bill_photo_url'] = $full_url; // Backup key
                }
            }

            // Optional: Format dates for easier consumption?
            // The frontend usually parses them, but we can ensure they are sent correctly.
            
            $data[] = $row;
        }
    }
    echo json_encode(["status" => "success", "data" => $data]);
}
?>

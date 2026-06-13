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
    $showroom = $_POST['showroom'] ?? ''; // 🔥 Capture Showroom parameter

    // 🔥 Apply Showroom Filter if provided
    $showroom_filter = "";
    if (!empty($showroom)) {
        $safe_showroom = $conn->real_escape_string($showroom);
        $showroom_filter = " AND TRIM(s.showroom_name) LIKE TRIM('$safe_showroom')";
    }

    // 🔥 Apply Location Filter if provided
    $location = $_POST['location'] ?? '';
    $location_filter = "";
    if (!empty($location) && $location != 'All') {
        $safe_location = $conn->real_escape_string($location);
        $location_filter = " AND w.location = '$safe_location'";
    }

    $sql = "SELECT 
                s.salesman_id, 
                s.name, 
                s.showroom_name,
                s.last_sync, 
                COUNT(CASE WHEN w.status = 'Pending' $location_filter THEN 1 END) as pending_count,
                COUNT(CASE WHEN w.status = 'Billed' $location_filter THEN 1 END) as billed_count
            FROM salesmen s
            LEFT JOIN walking_customers w ON s.salesman_id = w.salesman_id
            WHERE s.status = 'Active' $showroom_filter
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
            WHERE salesman_id = '$safe_id'";

    // 🔥 Apply Location Filter if provided
    $location = $_POST['location'] ?? '';
    if (!empty($location) && $location != 'All') {
        $safe_location = $conn->real_escape_string($location);
        // Assuming column name is 'location' or 'area'. 
        // User asked for "location filter", so 'location' is most likely.
        // If it's 'area', this needs to be changed.
        $sql .= " AND location = '$safe_location'"; 
    }

    $sql .= " ORDER BY created_at DESC LIMIT 50";
            
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
// 3. GET UNIQUE LOCATIONS FOR FILTER
elseif ($action == 'get_salesman_locations') {
    $salesman_id = $_POST['salesman_id'] ?? '';
    if(empty($salesman_id)) {
        echo json_encode(["status" => "error", "message" => "ID Required"]);
        exit;
    }
    $safe_id = $conn->real_escape_string($salesman_id);
    
    // Check if 'location' column exists or use 'area' if widely used. 
    // Assuming 'location' based on user request.
    $sql = "SELECT DISTINCT location FROM walking_customers WHERE salesman_id = '$safe_id' AND location IS NOT NULL AND location != '' ORDER BY location ASC";
    $result = $conn->query($sql);
    
    $locations = [];
    if ($result) {
        while($row = $result->fetch_assoc()) {
            $locations[] = $row['location'];
        }
    }
    echo json_encode(["status" => "success", "data" => $locations]);
}

// 4. GET ALL UNIQUE LOCATIONS FOR A SHOWROOM (Main Filter)
elseif ($action == 'get_all_locations') {
    $showroom = $_POST['showroom'] ?? '';
    
    $sql = "SELECT DISTINCT w.location 
            FROM walking_customers w
            JOIN salesmen s ON w.salesman_id = s.salesman_id
            WHERE w.location IS NOT NULL AND w.location != ''";
    
    if (!empty($showroom)) {
        $safe_showroom = $conn->real_escape_string($showroom);
        $sql .= " AND TRIM(s.showroom_name) LIKE TRIM('$safe_showroom')";
    }

    $sql .= " ORDER BY w.location ASC";
    $result = $conn->query($sql);
    
    $locations = [];
    if ($result) {
        while($row = $result->fetch_assoc()) {
            $locations[] = $row['location'];
        }
    }
    echo json_encode(["status" => "success", "data" => $locations]);
}
?>

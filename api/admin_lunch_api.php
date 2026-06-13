<?php
// api/admin_lunch_api.php
// 👨‍💼 ADMIN LUNCH MANAGEMENT API: CRUD operations for lunch attendance

error_reporting(E_ERROR | E_PARSE);
ini_set('display_errors', 0);

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

date_default_timezone_set('Asia/Kolkata');

require_once __DIR__ . '/db_connect.php';

$json_data = json_decode(file_get_contents('php://input'), true) ?: [];
$action = $json_data['action'] ?? $_POST['action'] ?? $_GET['action'] ?? '';

// Base URL for Images
$protocol = isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? "https" : "http";
$host = $_SERVER['HTTP_HOST'];
$script_dir = dirname($_SERVER['PHP_SELF']);
$script_dir = trim($script_dir, '/\\');
$script_dir = str_replace('\\', '/', $script_dir);
$base_url = "$protocol://$host/$script_dir/";

if ($action == 'fetch_records') {
    $start_date = $json_data['start_date'] ?? $_POST['start_date'] ?? date('Y-m-d');
    $end_date = $json_data['end_date'] ?? $_POST['end_date'] ?? date('Y-m-d');

    $esc_start = $conn->real_escape_string($start_date);
    $esc_end = $conn->real_escape_string($end_date);

    // Using salesmen as the base table to show everyone, even if no lunch record exists
    $sql = "SELECT s.salesman_id, s.name as salesman_name, s.showroom_name, s.phone as salesman_phone, s.role,
                   la.id, la.date, la.lunch_in_time, la.lunch_out_time, la.lunch_in_selfie_url, la.lunch_out_selfie_url, 
                   la.duration_seconds, la.in_latitude, la.in_longitude, la.out_latitude, la.out_longitude,
                   COALESCE(att.status, IF(lr.id IS NOT NULL, 'Leave', NULL)) as attendance_status
            FROM salesmen s
            LEFT JOIN lunch_attendance la ON s.salesman_id = la.salesman_id COLLATE utf8mb4_general_ci 
                 AND la.date BETWEEN '$esc_start' AND '$esc_end'
            LEFT JOIN attendance att ON s.salesman_id = att.salesman_id COLLATE utf8mb4_general_ci
                 AND att.date = COALESCE(la.date, '$esc_start')
            LEFT JOIN leave_requests lr ON s.salesman_id = lr.salesman_id COLLATE utf8mb4_general_ci
                 AND lr.leave_date = COALESCE(la.date, '$esc_start') AND lr.status = 'Approved'
            WHERE s.status = 'Active'
            ORDER BY la.date DESC, la.lunch_in_time DESC, s.name ASC";

    try {
        // Fetch showrooms with coordinates for distance calculation
        $showrooms_res = $conn->query("SELECT name, latitude, longitude FROM showrooms");
        $showrooms_data = [];
        if ($showrooms_res) {
            while ($s = $showrooms_res->fetch_assoc()) { $showrooms_data[] = $s; }
        }

        $res = $conn->query($sql);
        $data = [];

        if ($res) {
            while ($row = $res->fetch_assoc()) {
                // Prepend base URL to images if they exist
                if (!empty($row['lunch_in_selfie_url'])) {
                    $row['lunch_in_selfie_url'] = $base_url . $row['lunch_in_selfie_url'];
                }
                if (!empty($row['lunch_out_selfie_url'])) {
                    $row['lunch_out_selfie_url'] = $base_url . $row['lunch_out_selfie_url'];
                }
                $data[] = $row;
            }
            if (ob_get_length())
                ob_clean();
            echo json_encode(["status" => "success", "data" => $data, "showrooms" => $showrooms_data]);
        } else {
            throw new Exception($conn->error);
        }
    } catch (Exception $e) {
        if (ob_get_length())
            ob_clean();
        echo json_encode(["status" => "error", "message" => "SQL Error: " . $e->getMessage()]);
    }
} elseif ($action == 'update_record') {
    $id = $json_data['id'] ?? $_POST['id'] ?? '';
    $date = $json_data['date'] ?? $_POST['date'] ?? '';
    $lunch_in = $json_data['lunch_in_time'] ?? $_POST['lunch_in_time'] ?? null;
    $lunch_out = $json_data['lunch_out_time'] ?? $_POST['lunch_out_time'] ?? null;

    if (empty($id)) {
        echo json_encode(["status" => "error", "message" => "Record ID required"]);
        exit;
    }

    $esc_id = $conn->real_escape_string($id);
    $esc_date = $conn->real_escape_string($date);
    $esc_in = $lunch_in ? "'" . $conn->real_escape_string($lunch_in) . "'" : "NULL";
    $esc_out = $lunch_out ? "'" . $conn->real_escape_string($lunch_out) . "'" : "NULL";

    // Recalculate duration if both times exist
    $duration_seconds = 0;
    if ($lunch_in && $lunch_out) {
        $duration_seconds = strtotime($lunch_out) - strtotime($lunch_in);
        if ($duration_seconds < 0)
            $duration_seconds = 0;
    }

    $sql_sm = "SELECT salesman_id FROM lunch_attendance WHERE id = '$esc_id'";
    $res_sm = $conn->query($sql_sm);
    $salesman_id = '';
    if ($res_sm && $res_sm->num_rows > 0) {
        $row_sm = $res_sm->fetch_assoc();
        $salesman_id = $row_sm['salesman_id'];
    }

    $sql = "UPDATE lunch_attendance SET 
            date = '$esc_date', 
            lunch_in_time = $esc_in, 
            lunch_out_time = $esc_out,
            duration_seconds = $duration_seconds";

    // Handle File Uploads
    $upload_dir = __DIR__ . '/../uploads/';
    if (!is_dir($upload_dir)) {
        mkdir($upload_dir, 0777, true);
    }

    $lunch_in_server_url = $json_data['lunch_in_server_url'] ?? $_POST['lunch_in_server_url'] ?? '';
    if (!empty($lunch_in_server_url)) {
        $esc_path = $conn->real_escape_string($lunch_in_server_url);
        $sql .= ", lunch_in_selfie_url = '$esc_path'";
    } elseif (isset($_FILES['lunch_in_selfie']) && $_FILES['lunch_in_selfie']['error'] == UPLOAD_ERR_OK) {
        $ext = pathinfo($_FILES['lunch_in_selfie']['name'], PATHINFO_EXTENSION);
        $filename = 'lunch_in_' . uniqid() . '.' . $ext;
        if (move_uploaded_file($_FILES['lunch_in_selfie']['tmp_name'], $upload_dir . $filename)) {
            $db_path = 'uploads/' . $filename;
            $sql .= ", lunch_in_selfie_url = '$db_path'";
        }
    }

    $lunch_out_server_url = $json_data['lunch_out_server_url'] ?? $_POST['lunch_out_server_url'] ?? '';
    if (!empty($lunch_out_server_url)) {
        $esc_path = $conn->real_escape_string($lunch_out_server_url);
        $sql .= ", lunch_out_selfie_url = '$esc_path'";
    } elseif (isset($_FILES['lunch_out_selfie']) && $_FILES['lunch_out_selfie']['error'] == UPLOAD_ERR_OK) {
        $ext = pathinfo($_FILES['lunch_out_selfie']['name'], PATHINFO_EXTENSION);
        $filename = 'lunch_out_' . uniqid() . '.' . $ext;
        if (move_uploaded_file($_FILES['lunch_out_selfie']['tmp_name'], $upload_dir . $filename)) {
            $db_path = 'uploads/' . $filename;
            $sql .= ", lunch_out_selfie_url = '$db_path'";
        }
    }

    $sql .= " WHERE id = '$esc_id'";

    if ($conn->query($sql)) {
        if (!empty($salesman_id)) {
            // 🛡️ SECURITY: Database Secret is required for server-side REST calls
            $auth_secret = "y9O4hN0n1Od4HuPf8co9uaRT2t750HUOYnhTaJJ3";
            $firebase_url = "https://admin-decd9-default-rtdb.asia-southeast1.firebasedatabase.app/salesmen_status/$salesman_id.json?auth=" . $auth_secret;
            $fb_data = json_encode([
                "lunch_sync_timestamp" => round(microtime(true) * 1000)
            ]);
            $ch = curl_init($firebase_url);
            curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "PATCH");
            curl_setopt($ch, CURLOPT_POSTFIELDS, $fb_data);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
            curl_exec($ch);

        }
        echo json_encode(["status" => "success", "message" => "Record updated"]);
    } else {
        echo json_encode(["status" => "error", "message" => "DB Error: " . $conn->error]);
    }
} elseif ($action == 'delete_record') {
    $id = $json_data['id'] ?? '';
    if (empty($id)) {
        echo json_encode(["status" => "error", "message" => "Record ID required"]);
        exit;
    }

    $esc_id = $conn->real_escape_string($id);

    // 1. Fetch record to get image paths and salesman_id
    $sql = "SELECT salesman_id, lunch_in_selfie_url, lunch_out_selfie_url FROM lunch_attendance WHERE id = '$esc_id'";
    $res = $conn->query($sql);
    $salesman_id = '';
    if ($res && $res->num_rows > 0) {
        $row = $res->fetch_assoc();
        $salesman_id = $row['salesman_id'];

        // 2. Delete images from server
        if (!empty($row['lunch_in_selfie_url']) && file_exists(__DIR__ . '/../' . $row['lunch_in_selfie_url'])) {
            @unlink(__DIR__ . '/../' . $row['lunch_in_selfie_url']);
        }
        if (!empty($row['lunch_out_selfie_url']) && file_exists(__DIR__ . '/../' . $row['lunch_out_selfie_url'])) {
            @unlink(__DIR__ . '/../' . $row['lunch_out_selfie_url']);
        }
    }

    // 3. Delete from DB
    $sql = "DELETE FROM lunch_attendance WHERE id = '$esc_id'";
    if ($conn->query($sql)) {
        // Sync to Firebase to notify the mobile app
        if (!empty($salesman_id)) {
            // 🛡️ SECURITY: Database Secret is required for server-side REST calls
            $auth_secret = "y9O4hN0n1Od4HuPf8co9uaRT2t750HUOYnhTaJJ3";
            $firebase_url = "https://admin-decd9-default-rtdb.asia-southeast1.firebasedatabase.app/salesmen_status/$salesman_id.json?auth=" . $auth_secret;
            $fb_data = json_encode([
                "lunch_sync_timestamp" => round(microtime(true) * 1000)
            ]);
            $ch = curl_init($firebase_url);
            curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "PATCH");
            curl_setopt($ch, CURLOPT_POSTFIELDS, $fb_data);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
            curl_exec($ch);

        }
        echo json_encode(["status" => "success", "message" => "Record and images deleted"]);
    } else {
        echo json_encode(["status" => "error", "message" => "DB Error: " . $conn->error]);
    }
} elseif ($action == 'toggle_window') {
    $is_open = $json_data['is_open'] ?? false;
    $mode = $is_open ? 'manual' : 'auto';

    // Dynamic status for Auto mode
    if ($mode === 'auto') {
        // Fetch current schedule from Firebase to instantly determine if it should be open
        // 🛡️ SECURITY: Database Secret is required for server-side REST calls when rules are locked
        $auth_secret = "y9O4hN0n1Od4HuPf8co9uaRT2t750HUOYnhTaJJ3";
        $firebase_url = "https://admin-decd9-default-rtdb.asia-southeast1.firebasedatabase.app/settings/lunch_window.json?auth=" . $auth_secret;
        $ch_get = curl_init($firebase_url);
        curl_setopt($ch_get, CURLOPT_RETURNTRANSFER, true);
        $resp = curl_exec($ch_get);

        $fb_data = json_decode($resp, true) ?: [];
        $start_time = $fb_data['start_time'] ?? '13:00';
        $end_time = $fb_data['end_time'] ?? '16:00';

        $current_time = date('H:i');
        if ($start_time < $end_time) {
            $is_open = ($current_time >= $start_time && $current_time < $end_time);
        } else {
            $is_open = ($current_time >= $start_time || $current_time < $end_time);
        }
    }

    // Firebase REST URL
    // 🛡️ SECURITY: Database Secret is required for server-side REST calls when rules are locked
    $auth_secret = "y9O4hN0n1Od4HuPf8co9uaRT2t750HUOYnhTaJJ3";
    $firebase_url = "https://admin-decd9-default-rtdb.asia-southeast1.firebasedatabase.app/settings/lunch_window.json?auth=" . $auth_secret;

    $data = json_encode([
        "is_open" => (bool) $is_open,
        "mode" => $mode,
        "last_updated" => date('Y-m-d H:i:s'),
        "updated_by" => "admin_panel"
    ]);

    $ch = curl_init($firebase_url);
    curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "PATCH");
    curl_setopt($ch, CURLOPT_POSTFIELDS, $data);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);

    $response = curl_exec($ch);
    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);


    if ($http_code == 200) {
        echo json_encode(["status" => "success", "message" => "Mode changed to " . $mode, "mode" => $mode]);
    } else {
        echo json_encode(["status" => "error", "message" => "Firebase Error: " . $http_code]);
    }
} elseif ($action == 'update_schedule') {
    $start_time = $json_data['start_time'] ?? '13:00';
    $end_time = $json_data['end_time'] ?? '16:00';

    $current_time = date('H:i');
    if ($start_time < $end_time) {
        $is_open = ($current_time >= $start_time && $current_time < $end_time);
    } else {
        $is_open = ($current_time >= $start_time || $current_time < $end_time);
    }

    // 🛡️ SECURITY: Database Secret is required for server-side REST calls when rules are locked
    $auth_secret = "y9O4hN0n1Od4HuPf8co9uaRT2t750HUOYnhTaJJ3";
    $firebase_url = "https://admin-decd9-default-rtdb.asia-southeast1.firebasedatabase.app/settings/lunch_window.json?auth=" . $auth_secret;

    // Switch to auto mode when schedule is updated
    $data = json_encode([
        "start_time" => $start_time,
        "end_time" => $end_time,
        "mode" => "auto",
        "is_open" => (bool) $is_open,
        "last_updated" => date('Y-m-d H:i:s'),
        "updated_by" => "admin_panel"
    ]);

    $ch = curl_init($firebase_url);
    curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "PATCH");
    curl_setopt($ch, CURLOPT_POSTFIELDS, $data);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);

    $response = curl_exec($ch);
    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);


    if ($http_code == 200) {
        echo json_encode(["status" => "success", "message" => "Schedule updated to $start_time - $end_time", "is_open" => $is_open]);
    } else {
        echo json_encode(["status" => "error", "message" => "Firebase Error: " . $http_code]);
    }
} elseif ($action == 'get_recent_uploads') {
    $showroom_filter = $json_data['showroom'] ?? '';
    $date_filter = $json_data['date'] ?? ''; 

    $safe_showroom_filter = '';
    if (!empty($showroom_filter)) {
        $safe_showroom_filter = preg_replace('/[^A-Za-z0-9\-]/', '_', $showroom_filter);
    }

    // Map existing URLs to their IN/OUT type
    $db_images = [];
    $stmt = $conn->prepare("SELECT lunch_in_selfie_url, lunch_out_selfie_url FROM lunch_attendance ORDER BY id DESC LIMIT 1000");
    if ($stmt) {
        $stmt->execute();
        $res = $stmt->get_result();
        while ($row = $res->fetch_assoc()) {
            if (!empty($row['lunch_in_selfie_url'])) {
                $db_images[$row['lunch_in_selfie_url']] = 'IN';
            }
            if (!empty($row['lunch_out_selfie_url'])) {
                $db_images[$row['lunch_out_selfie_url']] = 'OUT';
            }
        }
        $stmt->close();
    }

    // Look in api/uploads (where lunch.php actually saves them)
    $upload_dir = __DIR__ . '/uploads/';
    $files = [];
    if (is_dir($upload_dir)) {
        // The root directory for calculating relative path should be the 'api' folder
        $root_dir = realpath(__DIR__);
        $iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($upload_dir, RecursiveDirectoryIterator::SKIP_DOTS));
        foreach ($iterator as $fileinfo) {
            if ($fileinfo->isFile()) {
                $ext = strtolower($fileinfo->getExtension());
                if (in_array($ext, ['jpg', 'jpeg', 'png', 'gif', 'webp'])) {
                    $real_path = $fileinfo->getRealPath();
                    // Make the path relative to the 'api' directory, e.g. "uploads/lunch/..."
                    $relative_path = str_replace('\\', '/', str_replace($root_dir, '', $real_path));
                    $relative_path = ltrim($relative_path, '/');

                    if (!empty($safe_showroom_filter) && strpos($relative_path, "lunch/$safe_showroom_filter/") === false) {
                        continue;
                    }

                    $type = isset($db_images[$relative_path]) ? $db_images[$relative_path] : '';
                    
                    $files[] = [
                        'url' => $relative_path, // This matches what is stored in the database
                        'full_url' => $base_url . $relative_path, // Base url is .../api/
                        'time' => $fileinfo->getMTime(),
                        'type' => $type
                    ];
                }
            }
        }
    }
    usort($files, function($a, $b) {
        return $b['time'] - $a['time']; // Sort descending
    });
    $files = array_slice($files, 0, 60); // Limit to 60 recent files
    echo json_encode(["status" => "success", "data" => $files]);
} else {
    echo json_encode(["status" => "error", "message" => "Invalid action"]);
}

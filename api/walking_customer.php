<?php
// FILE: slfm_api/walking_customer.php
// SECURITY UPDATE: Added Image Mime Check & Explode Fix
// OPTIMIZATION: Added Image Compression (HD Quality, Low Size)
// TIMEZONE FIX: Enforced Asia/Kolkata for all timestamp operations

error_reporting(0);
ini_set('display_errors', 0);

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");

// 🔥 CRITICAL: Set Timezone to Kolkata
date_default_timezone_set('Asia/Kolkata');

require 'db_connect.php';
// 🔥 CRITICAL: Prevent MySQL from shifting timestamps when fetching
$conn->query("SET time_zone = '+00:00'");

$json_data = json_decode(file_get_contents('php://input'), true);
$action = $json_data['action'] ?? $_POST['action'] ?? '';

// --- HELPER: Sync to Firebase RTDB ---
function sendSyncSignal($sid) {
    if (empty($sid)) return;
    $rtdb_url = "https://admin-decd9-default-rtdb.asia-southeast1.firebasedatabase.app";
    $rtdb_secret = "y9O4hN0n1Od4HuPf8co9uaRT2t750HUOYnhTaJJ3";
    $sync_data = ['data_sync_timestamp' => (int)round(microtime(true) * 1000)];
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $rtdb_url . "/sync/" . $sid . ".json?auth=" . $rtdb_secret);
    curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "PATCH");
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($sync_data));
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_exec($ch);
}

// --- HELPER: Image Compression Function ---
function compressImage($source, $destination, $quality)
{
    $info = getimagesize($source);
    if ($info['mime'] == 'image/jpeg')
        $image = imagecreatefromjpeg($source);
    elseif ($info['mime'] == 'image/png')
        $image = imagecreatefrompng($source);
    else
        return false;

    // Save compressed image
    imagejpeg($image, $destination, $quality);
    return true;
}

// --- HELPER: Format Date without Timezone Shifting ---
function formatIST($mysql_date)
{
    if (empty($mysql_date) || $mysql_date === '0000-00-00 00:00:00' || $mysql_date === 'NULL' || $mysql_date === '0000-00-00') return '-';
    // Input format expected: "YYYY-MM-DD HH:MM:SS"
    $parts = explode(' ', $mysql_date);
    if (count($parts) < 2) {
        // Handle date only format "YYYY-MM-DD"
        $date_parts = explode('-', $parts[0]);
        if (count($date_parts) === 3) {
            $months = ["01"=>"Jan","02"=>"Feb","03"=>"Mar","04"=>"Apr","05"=>"May","06"=>"Jun","07"=>"Jul","08"=>"Aug","09"=>"Sep","10"=>"Oct","11"=>"Nov","12"=>"Dec"];
            return $date_parts[2] . " " . ($months[$date_parts[1]] ?? $date_parts[1]);
        }
        return $mysql_date;
    }

    $date_parts = explode('-', $parts[0]);
    $time_parts = explode(':', $parts[1]);

    if (count($date_parts) < 3 || count($time_parts) < 2) return $mysql_date;

    $year = $date_parts[0];
    $month = $date_parts[1];
    $day = $date_parts[2];
    $hour = (int)$time_parts[0];
    $min = $time_parts[1];

    $ampm = $hour >= 12 ? 'PM' : 'AM';
    $h12 = $hour % 12;
    if ($h12 == 0) $h12 = 12;
    $h12_str = str_pad($h12, 2, '0', STR_PAD_LEFT);

    $months = [
        "01" => "Jan", "02" => "Feb", "03" => "Mar", "04" => "Apr", "05" => "May", "06" => "Jun",
        "07" => "Jul", "08" => "Aug", "09" => "Sep", "10" => "Oct", "11" => "Nov", "12" => "Dec"
    ];
    $month_str = $months[$month] ?? $month;

    return "$h12_str:$min $ampm, $day $month_str";
}

function getKolkataTime()
{
    $dt = new DateTime('now', new DateTimeZone('Asia/Kolkata'));
    return $dt->format('Y-m-d H:i:s');
}

// --- 6. GET DASHBOARD STATS ---
if ($action == 'get_stats') {
    $salesman_id = $json_data['salesman_id'] ?? '';

    if (empty($salesman_id)) {
        echo json_encode(["status" => "error", "message" => "Salesman ID Required"]);
        exit;
    }

    $safe_id = $conn->real_escape_string($salesman_id);

    $pending_sql = "SELECT COUNT(*) as count FROM walking_customers WHERE salesman_id = '$safe_id' AND status = 'Pending'";
    $pending_res = $conn->query($pending_sql);
    $pending_count = $pending_res ? $pending_res->fetch_assoc()['count'] : 0;

    $billed_sql = "SELECT COUNT(*) as count FROM walking_customers WHERE salesman_id = '$safe_id' AND status = 'Billed'";
    $billed_res = $conn->query($billed_sql);
    $billed_count = $billed_res ? $billed_res->fetch_assoc()['count'] : 0;

    echo json_encode([
        "status" => "success",
        "data" => ["pending" => (int) $pending_count, "billed" => (int) $billed_count]
    ]);
    exit;
}

// --- 1. ADD WALKING ---
if ($action == 'add_walking') {
    $salesman_id = $json_data['salesman_id'] ?? '';
    $name = $json_data['customer_name'] ?? '';
    $phone = $json_data['phone'] ?? '';
    $product = $json_data['product_interest'] ?? '';

    if (empty($salesman_id) || empty($name)) {
        echo json_encode(["status" => "error", "message" => "Name is required"]);
        exit;
    }

    $safe_id = $conn->real_escape_string($salesman_id);
    $safe_name = $conn->real_escape_string($name);
    $safe_phone = $conn->real_escape_string($phone);
    $safe_product = $conn->real_escape_string($product);

    // 🔥 NEW: Fetch salesman's showroom to save with the record
    $showroom = "Main Branch";
    $s_res = $conn->query("SELECT showroom_name FROM salesmen WHERE salesman_id = '$safe_id'");
    if ($s_res && $row = $s_res->fetch_assoc()) {
        $showroom = $row['showroom_name'];
    }

    // 🔥 TIMEZONE FIX: Use PHP generated time instead of MySQL NOW() to be 100% sure
    $created_at = getKolkataTime();

    $sql = "INSERT INTO walking_customers (salesman_id, showroom_name, customer_name, phone, product_interest, created_at) 
            VALUES ('$safe_id', '".$conn->real_escape_string($showroom)."', '$safe_name', '$safe_phone', '$safe_product', '$created_at')";

    if ($conn->query($sql) === TRUE) {
        sendSyncSignal($safe_id);
        echo json_encode(["status" => "success", "message" => "Saved Successfully"]);
    } else {
        echo json_encode(["status" => "error", "message" => "DB Error: " . $conn->error]);
    }
}

// --- 2. GET MY WALKINGS ---
elseif ($action == 'get_my_walkings') {
    $salesman_id = $json_data['salesman_id'] ?? '';
    $safe_id = $conn->real_escape_string($salesman_id);

    $sql = "SELECT w.id, w.salesman_id, w.showroom_name, w.customer_name, w.phone, w.product_interest, 
                   DATE_FORMAT(w.created_at, '%Y-%m-%d %H:%i:%s') as created_at,
                   DATE_FORMAT(w.billed_at, '%Y-%m-%d %H:%i:%s') as billed_at,
                   w.status, w.bill_photo, w.feedback_text, w.feedback_by,
                   DATE_FORMAT(w.feedback_date, '%Y-%m-%d %H:%i:%s') as feedback_date,
                   s.name as salesman_real_name 
            FROM walking_customers w 
            LEFT JOIN salesmen s ON w.salesman_id = s.salesman_id
            WHERE w.salesman_id = '$safe_id' 
            ORDER BY w.created_at DESC LIMIT 100";

    $result = $conn->query($sql);

    $data = [];
    if ($result) {
        while ($row = $result->fetch_assoc()) {
            $row['created_date_fmt'] = formatIST($row['created_at']);
            $row['billed_date_fmt'] = !empty($row['billed_at']) ? formatIST($row['billed_at']) : "Not Billed";
            $data[] = $row;
        }
        echo json_encode(["status" => "success", "data" => $data]);
    } else {
        echo json_encode(["status" => "error", "message" => "Fetch Failed"]);
    }
}

// --- 3. GET ALL WALKINGS (Admin) ---
elseif ($action == 'get_walkings' || $action == 'get_all_walkings') {
    $showroom_filter = $conn->real_escape_string($json_data['showroom'] ?? '');
    $status_filter = $conn->real_escape_string($json_data['status'] ?? '');
    $month_filter = $conn->real_escape_string($json_data['month'] ?? '');
    $year_filter = $conn->real_escape_string($json_data['year'] ?? '');
    
    $where_clauses = [];
    if(!empty($showroom_filter)) $where_clauses[] = "w.showroom_name = '$showroom_filter'";
    if(!empty($status_filter)) $where_clauses[] = "w.status = '$status_filter'";
    if(!empty($month_filter)) $where_clauses[] = "MONTH(w.created_at) = '$month_filter'";
    if(!empty($year_filter)) $where_clauses[] = "YEAR(w.created_at) = '$year_filter'";
    if(!empty($json_data['day'])) {
        $day_filter = $conn->real_escape_string($json_data['day']);
        $where_clauses[] = "DAY(w.created_at) = '$day_filter'";
    }
    
    // 🔥 Role Filtering: Only Salesman and Promoter
    $where_clauses[] = "(s.role IS NULL OR LOWER(s.role) IN ('salesman', 'promoter'))";
    
    $where_sql = !empty($where_clauses) ? " WHERE ".implode(" AND ", $where_clauses) : "";

    $sql = "SELECT w.id, w.salesman_id, w.showroom_name, w.customer_name, w.phone, w.product_interest, 
                   DATE_FORMAT(w.created_at, '%Y-%m-%d %H:%i:%s') as created_at,
                   DATE_FORMAT(w.billed_at, '%Y-%m-%d %H:%i:%s') as billed_at,
                   w.status, w.bill_photo, w.feedback_text, w.feedback_by,
                   DATE_FORMAT(w.feedback_date, '%Y-%m-%d %H:%i:%s') as feedback_date,
                   s.showroom_name as s_showroom, s.name as salesman_real_name 
            FROM walking_customers w 
            LEFT JOIN salesmen s ON w.salesman_id = s.salesman_id 
            $where_sql
            ORDER BY w.created_at DESC";
    if (empty($month_filter)) {
        $sql .= " LIMIT 200";
    }

    $result = $conn->query($sql);
    $data = [];

    if ($result) {
        while ($row = $result->fetch_assoc()) {
            $sName = !empty($row['salesman_real_name']) ? $row['salesman_real_name'] : 'Unknown Salesman';
            $pPhone = $row['phone'];
            $feedbackText = $row['feedback_text'];
            
            // 🔥 REMOVED SECURE_HIDDEN FOR ADMIN EXPORT
            // if (!empty($feedbackText)) {
            //     $pPhone = (strlen($pPhone) > 3) ? "*******" . substr($pPhone, -3) : "Hidden";
            //     $feedbackText = "SECURE_HIDDEN";
            // }

            // Use billed_at as feedback_date if feedback_date is empty
            $actual_feedback_date = (!empty($row['feedback_date']) && $row['feedback_date'] !== '0000-00-00 00:00:00') 
                                    ? $row['feedback_date'] 
                                    : $row['billed_at'];

            $data[] = [
                "id" => $row['id'],
                "customer_name" => $row['customer_name'],
                "phone" => $row['phone'],
                "product_interest" => $row['product_interest'],
                "created_at" => $row['created_at'],
                "billed_at" => $row['billed_at'],
                "salesman_id" => $row['salesman_id'],
                "salesman_name" => $sName,
                "showroom_name" => $row['showroom_name'] ?? $row['s_showroom'] ?? 'Main Branch',
                "status" => $row['status'],
                "bill_photo" => $row['bill_photo'],
                "feedback_text" => $row['feedback_text'],
                "feedback_by" => $row['feedback_by'],
                "feedback_date" => $actual_feedback_date
            ];
        }
        $all_salesmen = [];
        $sales_sql = "SELECT salesman_id, name, showroom_name FROM salesmen WHERE status = 'Active' AND LOWER(role) IN ('salesman', 'promoter')";
        if(!empty($showroom_filter)) {
            $sales_sql .= " AND showroom_name = '$showroom_filter'";
        }
        $sales_res = $conn->query($sales_sql);
        if($sales_res) {
            while($srow = $sales_res->fetch_assoc()) {
                $all_salesmen[] = $srow;
            }
        }

        echo json_encode([
            "status" => "success", 
            "data" => $data,
            "all_salesmen" => $all_salesmen
        ]);
    } else {
        echo json_encode(["status" => "error", "message" => "Fetch failed"]);
    }
}

// --- 4. UPLOAD BILL (🔥 SECURED & COMPRESSED) ---
elseif ($action == 'upload_bill') {
    $id = $json_data['id'] ?? '';
    // Support both 'bill_image' and 'image' keys just in case
    $base64_image = $json_data['bill_image'] ?? $json_data['image'] ?? '';

    if (empty($id) || empty($base64_image)) {
        echo json_encode(["status" => "error", "message" => "Bill Photo Required"]);
        exit;
    }

    $upload_dir = 'uploads/bills/';
    if (!is_dir($upload_dir)) {
        mkdir($upload_dir, 0777, true);
    }

    $safe_id = $conn->real_escape_string($id);

    // 🔥 TIMEZONE FIX: Use PHP generated time for filename and DB
    $timestamp = getKolkataTime();
    $dt_file = new DateTime('now', new DateTimeZone('Asia/Kolkata'));
    $file_timestamp = $dt_file->format('Y_m_d_H_i_s'); // Safe for filename

    $filename = "BILL_" . $safe_id . "_" . $file_timestamp . ".jpg";
    $filepath = $upload_dir . $filename;

    // 🔥 FIX 1: Parsing Base64 correctly
    if (strpos($base64_image, ',') !== false) {
        $parts = explode(',', $base64_image);
        $base64_image = $parts[1];
    }

    $decoded_data = base64_decode($base64_image);

    if ($decoded_data === false) {
        echo json_encode(["status" => "error", "message" => "Invalid Image Data"]);
        exit;
    }

    // 🔥 FIX 2: Security Check
    $finfo = new finfo(FILEINFO_MIME_TYPE);
    $mime_type = $finfo->buffer($decoded_data);

    if ($mime_type != 'image/jpeg' && $mime_type != 'image/png') {
        echo json_encode(["status" => "error", "message" => "Security Alert: Invalid Image Format"]);
        exit;
    }

    // 🔥 FIX 3: COMPRESSION LOGIC
    // Save temporarily
    file_put_contents($filepath, $decoded_data);

    // Compress (Quality: 60 - Reduces size by ~70%, keeps HD look)
    compressImage($filepath, $filepath, 60);

    // Update DB with explicit timestamp
    $sql = "UPDATE walking_customers 
            SET bill_photo = '$filepath', 
                status = 'Billed', 
                billed_at = '$timestamp' 
            WHERE id = '$safe_id'";

    if ($conn->query($sql) === TRUE) {
        $sid_res = $conn->query("SELECT salesman_id FROM walking_customers WHERE id = '$safe_id'");
        $sid = ($sid_res && $row = $sid_res->fetch_assoc()) ? $row['salesman_id'] : '';
        sendSyncSignal($sid);
        echo json_encode(["status" => "success", "message" => "Bill Uploaded (Compressed) Successfully"]);
    } else {
        echo json_encode(["status" => "error", "message" => "DB Update Failed"]);
    }
}

// --- 5. ADD FEEDBACK ---
elseif ($action == 'add_feedback') {
    $id = $json_data['id'] ?? '';
    $feedback_text = $json_data['feedback_text'] ?? '';
    $salesman_name = $json_data['salesman_name'] ?? 'Unknown';

    if (empty($id) || empty($feedback_text)) {
        echo json_encode(["status" => "error", "message" => "Feedback cannot be empty"]);
        exit;
    }

    $safe_id = $conn->real_escape_string($id);
    $safe_feedback = $conn->real_escape_string($feedback_text);
    $safe_by = $conn->real_escape_string($salesman_name);

    // 🔥 TIMEZONE FIX
    $timestamp = getKolkataTime();

    $sql = "UPDATE walking_customers 
            SET feedback_text = '$safe_feedback', 
                feedback_by = '$safe_by', 
                feedback_date = '$timestamp' 
            WHERE id = '$safe_id'";

    if ($conn->query($sql) === TRUE) {
        $sid_res = $conn->query("SELECT salesman_id FROM walking_customers WHERE id = '$safe_id'");
        $sid = ($sid_res && $row = $sid_res->fetch_assoc()) ? $row['salesman_id'] : '';
        sendSyncSignal($sid);
        echo json_encode(["status" => "success", "message" => "Feedback Added"]);
    } else {
        echo json_encode(["status" => "error", "message" => "Error adding feedback"]);
    }
}

// --- 7. DELETE (Immediately reflected via Firebase) ---
elseif ($action == 'delete_walking_customer') {
    $id = (int)($json_data['id'] ?? '');
    $sid_res = $conn->query("SELECT salesman_id FROM walking_customers WHERE id = $id");
    $sid = ($sid_res && $row = $sid_res->fetch_assoc()) ? $row['salesman_id'] : '';
    if ($conn->query("DELETE FROM walking_customers WHERE id = $id")) {
        sendSyncSignal($sid);
        echo json_encode(["status" => "success", "message" => "Deleted"]);
    } else { echo json_encode(["status" => "error", "message" => "Delete failed"]); }
}

// --- 6. UPDATE WALKING ---
elseif ($action == 'update_walking') {
    $id = $json_data['id'] ?? '';
    $name = $json_data['customer_name'] ?? '';
    $phone = $json_data['phone'] ?? '';
    $product = $json_data['product_interest'] ?? '';

    $safe_id = $conn->real_escape_string($id);
    $safe_name = $conn->real_escape_string($name);
    $safe_phone = $conn->real_escape_string($phone);
    $safe_product = $conn->real_escape_string($product);

    $sql = "UPDATE walking_customers 
            SET customer_name = '$safe_name', phone = '$safe_phone', product_interest = '$safe_product' 
            WHERE id = '$safe_id'";

    if ($conn->query($sql) === TRUE) {
        $sid_res = $conn->query("SELECT salesman_id FROM walking_customers WHERE id = '$safe_id'");
        $sid = ($sid_res && $row = $sid_res->fetch_assoc()) ? $row['salesman_id'] : '';
        sendSyncSignal($sid);
        echo json_encode(["status" => "success", "message" => "Updated"]);
    } else {
        echo json_encode(["status" => "error", "message" => "Update Failed"]);
    }
}

// --- 8. GET CONVERSION LEADERBOARD ---
elseif ($action == 'get_walking_leaderboard') {
    $sql = "SELECT s.salesman_id, s.name, s.showroom_name, s.profile_photo, s.avatar_animal,
                   COUNT(CASE WHEN w.status = 'Billed' THEN 1 END) as billed_count,
                   COUNT(CASE WHEN w.status = 'Pending' THEN 1 END) as pending_count,
                   COUNT(w.id) as total_count,
                   MIN(CASE WHEN w.status = 'Billed' THEN w.billed_at ELSE NULL END) AS last_billed_at
            FROM salesmen s
            LEFT JOIN walking_customers w ON s.salesman_id = w.salesman_id
            WHERE s.status = 'Active' AND LOWER(s.role) IN ('salesman', 'promoter')
            AND LOWER(s.showroom_name) != 'kutty chutty'
            AND LOWER(s.showroom_name) != 'office'
            GROUP BY s.salesman_id
            ORDER BY billed_count DESC, last_billed_at ASC, total_count DESC, s.name ASC";
    $res = $conn->query($sql);
    $data = [];
    if ($res) {
        while ($row = $res->fetch_assoc()) {
            $row['conversion_rate'] = $row['total_count'] > 0 ? round(($row['billed_count'] / $row['total_count']) * 100, 1) : 0;
            $data[] = $row;
        }
        echo json_encode(["status" => "success", "data" => $data]);
    } else { echo json_encode(["status" => "error", "message" => "Leaderboard failed"]); }
}

$conn->close();
?>
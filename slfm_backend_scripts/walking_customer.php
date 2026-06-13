<?php
// FILE: slfm_api/walking_customer.php
// SECURITY UPDATE: Added Image Mime Check & Explode Fix
// OPTIMIZATION: Added Image Compression (HD Quality, Low Size)
// TIMEZONE FIX: Enforced Asia/Kolkata for all timestamp operations

error_reporting(0); 
ini_set('display_errors', 0);

header("Content-Type: application/json");

// 🔥 CRITICAL: Set Timezone to Kolkata
date_default_timezone_set('Asia/Kolkata');

require 'db_connect.php';

$json_data = json_decode(file_get_contents('php://input'), true);
$action = $json_data['action'] ?? $_POST['action'] ?? '';

// --- HELPER: Image Compression Function ---
function compressImage($source, $destination, $quality) {
    $info = getimagesize($source);
    if ($info['mime'] == 'image/jpeg') 
        $image = imagecreatefromjpeg($source);
    elseif ($info['mime'] == 'image/png') 
        $image = imagecreatefrompng($source);
    else 
        return false;

    // Save compressed image
    imagejpeg($image, $destination, $quality);
    imagedestroy($image);
    return true;
}

// --- HELPER: Get Current Timestamp in Kolkata Time ---
function getKolkataTime() {
    return date('Y-m-d H:i:s');
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
        "data" => ["pending" => (int)$pending_count, "billed" => (int)$billed_count]
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

    // 🔥 TIMEZONE FIX: Use PHP generated time instead of MySQL NOW() to be 100% sure
    $created_at = getKolkataTime();

    $sql = "INSERT INTO walking_customers (salesman_id, customer_name, phone, product_interest, created_at) 
            VALUES ('$safe_id', '$safe_name', '$safe_phone', '$safe_product', '$created_at')";
    
    if ($conn->query($sql) === TRUE) {
        echo json_encode(["status" => "success", "message" => "Saved Successfully"]);
    } else {
        echo json_encode(["status" => "error", "message" => "DB Error: " . $conn->error]);
    }
}

// --- 2. GET MY WALKINGS ---
elseif ($action == 'get_my_walkings') {
    $salesman_id = $json_data['salesman_id'] ?? '';
    $safe_id = $conn->real_escape_string($salesman_id);

    $sql = "SELECT w.*, s.name as salesman_real_name 
            FROM walking_customers w 
            LEFT JOIN salesmen s ON w.salesman_id = s.salesman_id
            WHERE w.salesman_id = '$safe_id' 
            ORDER BY w.created_at DESC LIMIT 100";
            
    $result = $conn->query($sql);
    
    $data = [];
    if ($result) {
        while ($row = $result->fetch_assoc()) {
            $row['created_date_fmt'] = date('h:i A, d M', strtotime($row['created_at']));
            $row['billed_date_fmt'] = !empty($row['billed_at']) ? date('h:i A, d M', strtotime($row['billed_at'])) : "Not Billed";
            $data[] = $row; 
        }
        echo json_encode(["status" => "success", "data" => $data]);
    } else {
        echo json_encode(["status" => "error", "message" => "Fetch Failed"]);
    }
}

// --- 3. GET ALL WALKINGS (Admin) ---
elseif ($action == 'get_walkings' || $action == 'get_all_walkings') {
    $sql = "SELECT w.*, s.showroom_name, s.name as salesman_real_name 
            FROM walking_customers w 
            LEFT JOIN salesmen s ON w.salesman_id = s.salesman_id 
            ORDER BY w.created_at DESC LIMIT 50";

    $result = $conn->query($sql);
    $data = [];

    if ($result) {
        while ($row = $result->fetch_assoc()) {
            $sName = !empty($row['salesman_real_name']) ? $row['salesman_real_name'] : 'Unknown Salesman';
            $phone = $row['phone'];
            $feedbackText = $row['feedback_text'];
            
            if (!empty($feedbackText)) {
                $phone = (strlen($phone) > 3) ? "*******" . substr($phone, -3) : "Hidden";
                $feedbackText = "SECURE_HIDDEN"; 
            }

            $data[] = [
                "id" => $row['id'],
                "customer_name" => $row['customer_name'],
                "phone" => $phone,
                "product_interest" => $row['product_interest'],
                "date" => date('h:i A, d M', strtotime($row['created_at'])), 
                "salesman_id" => $row['salesman_id'],
                "salesman_name" => $sName,
                "showroom" => $row['showroom_name'] ?? 'Main Branch',
                "feedback_text" => $feedbackText, 
                "feedback_by" => $row['feedback_by'],      
                "feedback_date" => $row['feedback_date'] ? date('d M, h:i A', strtotime($row['feedback_date'])) : null
            ];
        }
        echo json_encode(["status" => "success", "data" => $data]);
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
    $file_timestamp = date('Y_m_d_H_i_s'); // Safe for filename
    
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

    if(empty($id) || empty($feedback_text)) {
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
        echo json_encode(["status" => "success", "message" => "Feedback Added"]);
    } else {
        echo json_encode(["status" => "error", "message" => "Error adding feedback"]);
    }
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
        echo json_encode(["status" => "success", "message" => "Updated"]);
    } else {
        echo json_encode(["status" => "error", "message" => "Update Failed"]);
    }
}

$conn->close();
?>

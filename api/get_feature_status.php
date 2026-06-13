<?php
// get_feature_status.php
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
include 'db_connect.php';

// 1. Get Showroom Parameter
$showroom = isset($_GET['showroom']) ? $conn->real_escape_string($_GET['showroom']) : 'All Showrooms';

// 2. Default Values (Admin ON/OFF வேலை செய்ய Default-ஐ True ஆக வைக்கிறோம்)
$response = [
    'walking_customer' => true,
    'walking_customer_visible' => true,
    'damage_report' => true,
    'damage_report_visible' => true,
    'podium_visible' => true,
    'leaderboard_visible' => true,
    'service_widget_visible' => true, // 🔥 Service Widget-ஐ True ஆக்கி, கீழே Role-ல் மற்றவர்களுக்கு Hide செய்கிறோம்.
    'maintenance_mode' => 0,
    'maintenance_message' => "Maintenance work in progress.",
    'status_color' => 'green',
    'eye_button_visible' => true,
    'mobile_easy_view' => true,
    'is_leaderboard_participant' => true
];

// 3. EXCLUSION LOGIC (Hide Leaderboard for Specific Showrooms)
$showroom_lower = strtolower(trim($showroom));
$excluded_showrooms = ['kutty chutty', 'office'];
if (in_array($showroom_lower, $excluded_showrooms) || strpos($showroom_lower, 'godown') !== false) {
    $response['is_leaderboard_participant'] = false;
}

// 4. Fetch Features (Global first, Specific overrides it)
// 🔥 FIX: DESC puts 'All Showrooms' (1) first, and Specific (0) last.
$sql_features = "SELECT feature_name, is_active, showroom_name FROM feature_control 
                 WHERE LOWER(TRIM(showroom_name)) = '$showroom_lower' 
                 OR showroom_name = 'All Showrooms'
                 ORDER BY (showroom_name = 'All Showrooms') DESC";

$result_features = $conn->query($sql_features);

if ($result_features && $result_features->num_rows > 0) {
    while ($row = $result_features->fetch_assoc()) {
        $fname = trim($row['feature_name']);
        $active = ($row['is_active'] == 1);

        // Map feature names to response keys
        if (in_array($fname, ['walking_customer', 'walking_customer_visible', 'walking_module'])) {
            $response['walking_customer'] = $active;
            $response['walking_customer_visible'] = $active;
        }
        if (in_array($fname, ['damage_report', 'damage_report_visible', 'damage_fab', 'damage_module'])) {
            $response['damage_report'] = $active;
            $response['damage_report_visible'] = $active;
        }
        if (in_array($fname, ['podium_visible', 'top_3_podium', 'podium_module'])) {
            $response['podium_visible'] = $active;
        }
        if (in_array($fname, ['leaderboard_visible', 'leaderboard_module'])) {
            $response['leaderboard_visible'] = $active;
        }

        // Other specific flags
        if (isset($response[$fname])) {
            $response[$fname] = $active;
        }
    }
}

// 5. Fetch Maintenance & Status
$sql_settings = "SELECT setting_key, setting_value FROM app_settings";
$result_settings = $conn->query($sql_settings);

if ($result_settings && $result_settings->num_rows > 0) {
    while ($row = $result_settings->fetch_assoc()) {
        if ($row['setting_key'] == 'maintenance_mode') {
            $response['maintenance_mode'] = (int) $row['setting_value'];
        }
        if ($row['setting_key'] == 'maintenance_message') {
            $response['maintenance_message'] = $row['setting_value'];
        }
        if ($row['setting_key'] == 'status_color') {
            $response['status_color'] = $row['setting_value'];
        }
    }
}

// 6. Role-Based Feature Overrides (Ultimate Filter based on Role)
$role = isset($_GET['role']) ? strtolower(trim($_GET['role'])) : '';
$salesman_id = isset($_GET['salesman_id']) ? $conn->real_escape_string($_GET['salesman_id']) : '';

// பழைய App 'user_id' என அனுப்பினால்...
if (empty($salesman_id) && isset($_GET['user_id'])) {
    $salesman_id = $conn->real_escape_string($_GET['user_id']);
}

// App-ல் இருந்து role வராத போது, DB-ல் இருந்து salesman_id மூலம் role-ஐ எடுக்கிறோம்.
if (empty($role) && !empty($salesman_id)) {
    $sql_role = "SELECT role FROM salesmen WHERE id = '$salesman_id' OR salesman_id = '$salesman_id' LIMIT 1";
    $res_role = $conn->query($sql_role);
    
    if (!$res_role || $res_role->num_rows == 0) {
         $sql_role = "SELECT role FROM users WHERE id = '$salesman_id' LIMIT 1";
         $res_role = $conn->query($sql_role);
    }

    if ($res_role && $res_role->num_rows > 0) {
        $row_role = $res_role->fetch_assoc();
        if (!empty($row_role['role'])) {
            $role = strtolower(trim($row_role['role']));
        }
    }
}

// Fallback protection
if (empty($role)) {
    $role = 'salesman';
}

$is_sales = (strpos($role, 'salesman') !== false || strpos($role, 'promoter') !== false);
$is_service = (strpos($role, 'service') !== false);

// 🔥 ROLE FILTER & ADMIN TOGGLE LOGIC:
if ($is_sales) {
    // Group 1: Salesman & Promoter
    // இவர்களுக்கு Podium, Leaderboard, Walking-ஐ Admin Panel முடிவு செய்யும் (So DB values stays).
    // Service widget இவர்களுக்கு எப்போதுமே தேவையில்லை, அதனால் அதை மட்டும் Hide செய்கிறோம்.
    $response['service_widget_visible'] = false;
    
} elseif ($is_service) {
    // Group 2: Service
    // இவர்களுக்கு Service Widget-ஐ Admin Panel முடிவு செய்யும் (So DB value stays).
    // Sales widgets இவர்களுக்கு எப்போதுமே தேவையில்லை, அதனால் அவற்றை Hide செய்கிறோம்.
    $response['podium_visible'] = false;
    $response['leaderboard_visible'] = false;
    $response['walking_customer'] = false;
    $response['walking_customer_visible'] = false;
    $response['is_leaderboard_participant'] = false;
    
} else {
    // Group 3: Manager, Supervisor, Office staff, Billing, Driver, Godown staff etc.
    // இவர்களுக்கு Attendance/Lunch தவிர வேறு எந்த Widget-ம் காட்டக்கூடாது.
    // அதனால் அனைத்தையும் Hide செய்கிறோம்.
    $response['podium_visible'] = false;
    $response['leaderboard_visible'] = false;
    $response['walking_customer'] = false;
    $response['walking_customer_visible'] = false;
    $response['service_widget_visible'] = false;
    $response['is_leaderboard_participant'] = false;
}

// 7. Return Final JSON
echo json_encode(['status' => 'success', 'data' => $response]);
?>
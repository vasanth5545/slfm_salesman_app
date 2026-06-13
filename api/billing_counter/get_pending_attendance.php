<?php
// slfm_api/billing_counter/get_pending_attendance.php
// Enable CORS and Error Reporting
ini_set('display_errors', 0);
error_reporting(E_ALL);

// 🔥 FIX: Block prashnangale thadayan CORS headers cherthu
header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

date_default_timezone_set('Asia/Kolkata');

// 1. DB Connection
$db_found = false;
$possible_paths = [
    __DIR__ . '/../db_connect.php',
    __DIR__ . '/db_connect.php'
];
foreach ($possible_paths as $path) {
    if (file_exists($path)) {
        require $path;
        $db_found = true;
        break;
    }
}
if (!$db_found) {
    http_response_code(500);
    echo json_encode(["status" => "error", "message" => "Critical: db_connect.php not found."]);
    exit;
}

// 🔥 FIX: Input surakshithamayi vayikkunnu (Supports both form-data and raw JSON payload)
$json_data = json_decode(file_get_contents('php://input'), true);

$raw_showroom = $_POST['showroom'] ?? $json_data['showroom'] ?? $_REQUEST['showroom'] ?? '';
$showroom = $conn->real_escape_string($raw_showroom);

// 🔥 FIX: Frontend-il ninnu staff_id surakshithamayi vangakkunnu
$raw_staff_id = $_POST['staff_id'] ?? $json_data['staff_id'] ?? $_REQUEST['staff_id'] ?? '';
$staff_id = $conn->real_escape_string($raw_staff_id);

// 🔥 FIX: Staff ID upayogichu Role kandupidikkunnu
$can_approve = false;

if (!empty($staff_id)) {
    $role_sql = "SELECT role FROM billing_staff WHERE staff_id = '$staff_id'";
    $role_res = $conn->query($role_sql);
    if ($role_res && $role_res->num_rows > 0) {
        $role_row = $role_res->fetch_assoc();
        $user_role = strtolower(trim($role_row['role'])); // trim() added for safety

        // Admin allengil Owner anengil mathrame Approve cheyyan kazhiyu
        if ($user_role === 'admin' || $user_role === 'owner') {
            $can_approve = true;
        }
    }
} else {
    // 🔥 FALLBACK: Oruvela Frontend-il ninnu staff_id API-yil vannillel,
    // Admin login cheyyumbol Showroom shoonnyamayi (Empty) irikkum. 
    // Athu vachu thalkalikamayi Admin-nu button kanikkunnu.
    if ($showroom === '') {
        $can_approve = true;
    }
}

// 2. Base URL Construction
$protocol = isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? "https" : "http";
$host = $_SERVER['HTTP_HOST'];
$script_dir = dirname($_SERVER['PHP_SELF']);
$script_dir = trim($script_dir, '/\\');
$base_url = "$protocol://$host/$script_dir/";

if (strpos($script_dir, 'billing_counter') !== false) {
    $base_url = str_replace('billing_counter', '', $base_url);
    $base_url = rtrim($base_url, '/');
    $base_url .= '/';
}

// 3. Helper Function for Image URLs
if (!function_exists('processUrl')) {
    function processUrl($url, $base_url)
    {
        if (!isset($url) || trim($url) === '')
            return null;
        $url = trim($url);
        if (strtolower($url) === 'null')
            return null;
        if (strpos($url, 'http') === 0)
            return $url;
        $clean_path = ltrim($url, '/');
        return $base_url . $clean_path;
    }
}

// 4. Calculate Date Range (Past 7 Days)
$today = date('Y-m-d');
$sevenDaysAgo = date('Y-m-d', strtotime('-7 days'));

// 5. Query for Potential Pending Approvals
// 🔥 FIX: ORDER BY changed to sort Pending on top and approved/rejected at the bottom
$sql = "SELECT 
            s.salesman_id, s.name, s.phone, s.role, s.showroom_name, s.gender, s.promoters, 
            a.clock_in_time, a.clock_out_time, 
            a.selfie_url, a.clock_out_selfie_url, a.reentry_selfie_url,
            a.status as att_status, a.is_late, a.id as attendance_id, a.admin_approval,
            a.is_out_of_location, a.location_distance, a.is_seen_by_admin,
            a.latitude, a.longitude, a.out_latitude, a.out_longitude,
            l.leave_type
        FROM salesmen s
        JOIN attendance a ON s.salesman_id = a.salesman_id
        LEFT JOIN leave_requests l ON s.salesman_id = l.salesman_id AND l.leave_date = a.date
        WHERE a.date BETWEEN '$sevenDaysAgo' AND '$today'
          AND a.clock_out_time IS NOT NULL
          " . (!empty($showroom) ? " AND s.showroom_name = '$showroom' " : "") . "
        ORDER BY 
            CASE 
                WHEN a.admin_approval = 'Pending' OR a.admin_approval IS NULL OR a.admin_approval = '' THEN 0 
                ELSE 1 
            END ASC,
            a.clock_out_time DESC";

$result = $conn->query($sql);
$pending_approvals = [];

if ($result) {
    while ($row = $result->fetch_assoc()) {

        $clockOutTimestamp = strtotime($row['clock_out_time']);
        $hour = (int) date('H', $clockOutTimestamp);

        $gender = strtolower($row['gender'] ?? 'male');
        $maxHour = ($gender === 'female') ? 20 : 21;

        $timeStr = date('H:i', $clockOutTimestamp);
        $is_early_out = ($timeStr >= '19:30' && $hour < $maxHour);
        $is_out_of_location_pending = ($row['is_out_of_location'] == 1 && $row['admin_approval'] === 'Pending');
        $is_already_actioned = (!empty($row['admin_approval']) && $row['admin_approval'] !== 'Pending');

        if ($is_early_out || $is_out_of_location_pending || $is_already_actioned) {

            $status = strtolower($row['att_status']);
            $valid_statuses = ['present', 'late', 'half day', 'leave'];

            if (in_array($status, $valid_statuses) || ($is_already_actioned && $status == 'leave') || $is_out_of_location_pending) {

                $selfieFullUrl = processUrl($row['selfie_url'], $base_url);
                $outSelfieFullUrl = processUrl($row['clock_out_selfie_url'], $base_url);
                $reentrySelfieFullUrl = processUrl($row['reentry_selfie_url'], $base_url);

                $displayStatus = $row['att_status'];
                if (empty($status) || $status == 'not_logged_in')
                    $displayStatus = 'Not In';

                $isLate = 0;
                $lateMinutes = 0;
                if (!empty($row['clock_in_time'])) {
                    $clockInTs = strtotime($row['clock_in_time']);
                    $dateStr = date('Y-m-d', $clockInTs);
                    $time930 = strtotime("$dateStr 09:30:00");
                    if ($clockInTs > $time930) {
                        $isLate = 1;
                        $lateMinutes = round(($clockInTs - $time930) / 60);
                    }
                }

                $outOfLocAlert = "";
                if ($row['is_out_of_location'] == 1) {
                    $dist = $row['location_distance'];
                    $outOfLocAlert = "Out of Showroom (" . $dist . "m Away)";
                }

                $adminAppr = $row['admin_approval'];
                if ($adminAppr === 'Pending')
                    $adminAppr = null;

                $pending_approvals[] = [
                    "id" => $row['salesman_id'],
                    "employeeId" => $row['salesman_id'],
                    "name" => $row['name'],
                    "phone" => $row['phone'] ?? null,
                    "role" => $row['role'] ?? 'Salesman',
                    "gender" => $row['gender'] ?? 'Male',
                    "showroom_name" => $row['showroom_name'] ?? 'Main Branch',
                    "promoters" => $row['promoters'] ?? null,
                    "profilePhoto" => null,
                    "status" => $status,
                    "displayStatus" => $displayStatus,
                    "inTime" => date('h:i A', strtotime($row['clock_in_time'])),
                    "outTime" => date('h:i A', strtotime($row['clock_out_time'])),
                    "timestamp" => strtotime($row['clock_out_time']) * 1000,

                    "isLate" => $isLate == 1,
                    "lateMinutes" => $lateMinutes,
                    "leaveStatus" => $row['leave_type'],
                    "adminApproval" => $adminAppr,
                    "attendanceId" => $row['attendance_id'],

                    // 🔥 NEW: admin_approval shoonnyamayirikkanam pinne Admin/Owner aayirikkanam
                    "showApprovalButtons" => (empty($adminAppr) && $can_approve),

                    "outOfLocationAlert" => $outOfLocAlert,
                    "isSeen" => $row['is_seen_by_admin'] == 1,

                    "latitude" => $row['latitude'] ?? null,
                    "longitude" => $row['longitude'] ?? null,
                    "outLatitude" => $row['out_latitude'] ?? null,
                    "outLongitude" => $row['out_longitude'] ?? null,

                    "selfieUrl" => $selfieFullUrl,
                    "outSelfieUrl" => $outSelfieFullUrl,
                    "reentrySelfieUrl" => $reentrySelfieFullUrl,
                    "out_selfie_url" => $outSelfieFullUrl,
                    "reentry_selfie_url" => $reentrySelfieFullUrl,
                    "date" => date('d M Y', strtotime($row['clock_out_time']))
                ];
            }
        }
    }

    $true_pending_count = 0;
    foreach ($pending_approvals as $item) {
        if (empty($item['adminApproval']) && !$item['isSeen']) {
            $true_pending_count++;
        }
    }

    echo json_encode([
        "status" => "success",
        "data" => $pending_approvals,
        "count" => $true_pending_count
    ]);

} else {
    echo json_encode(["status" => "error", "message" => "DB Error: " . $conn->error]);
}

$conn->close();
?>
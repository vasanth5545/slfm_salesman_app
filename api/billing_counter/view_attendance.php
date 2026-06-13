<?php
// slfm_api/billing_counter/view_attendance.php
// 1. Error Handling
ini_set('display_errors', 0);
error_reporting(E_ALL);
header("Content-Type: application/json");
date_default_timezone_set('Asia/Kolkata');

// 2. DB Connection
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

$date = isset($_POST['date']) ? $conn->real_escape_string($_POST['date']) : date('Y-m-d');
$showroom = isset($_POST['showroom']) ? $conn->real_escape_string($_POST['showroom']) : ''; // 🔥 Showroom Filter

// 🎉 CHECK IF SELECTED DATE IS A HOLIDAY
$is_holiday = false;
$holiday_reason = '';
$holiday_check_sql = "SELECT reason FROM holidays WHERE holiday_date = '$date' LIMIT 1";
$holiday_check_res = $conn->query($holiday_check_sql);
if ($holiday_check_res && $holiday_check_res->num_rows > 0) {
    $h_row = $holiday_check_res->fetch_assoc();
    $is_holiday = true;
    $holiday_reason = $h_row['reason'] ?? 'Holiday';
}

// 3. Base URL
$protocol = isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? "https" : "http";
$host = $_SERVER['HTTP_HOST'];
$script_dir = dirname($_SERVER['PHP_SELF']);
$script_dir = trim($script_dir, '/\\');
$base_url = "$protocol://$host/$script_dir/";

// Adjust Base URL if inside billing_counter folder
if (strpos($script_dir, 'billing_counter') !== false) {
    $base_url = str_replace('billing_counter', '', $base_url);
    // Remove trailing slash if double, then ensure one trailing slash
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

        // Return null for string literal 'null' just in case
        if (strtolower($url) === 'null')
            return null;

        if (strpos($url, 'http') === 0) {
            return $url;
        }
        $clean_path = ltrim($url, '/');
        return $base_url . $clean_path;
    }
}

// 🎨 ROLE COLOR HELPER
// Returns a hex color string for each role.
// Empty string = Flutter uses its default theme color.
// Future-ல் color மாற்ற: இங்கே மட்டும் edit பண்ணா போதும்!
if (!function_exists('getRoleColor')) {
    function getRoleColor($role)
    {
        switch (strtolower(trim($role ?? ''))) {
            case 'promoter':
                return '#9C27B0'; // Purple
            default:
                return '';         // Default (Flutter theme color)
        }
    }
}

// 4. Query
$sql = "SELECT 
            s.salesman_id, 
            s.name, 
            s.phone,
            s.role,
            s.showroom_name,
            s.gender, 
            s.promoters, 
            s.shift_start_time,
            s.custom_late_cutoff,
            a.clock_in_time, 
            a.clock_out_time, 
            a.selfie_url, 
            a.clock_out_selfie_url,
            a.reentry_selfie_url,
            a.final_out_selfie_url,
            a.status as att_status,
            a.is_late,
            a.id as attendance_id,
            a.admin_approval,
            a.late_entry_approved,
            a.latitude,
            a.longitude,
            a.out_latitude,   /* 🔥 Puthusa add cheythathu */
            a.out_longitude,  /* 🔥 Puthusa add cheythathu */
            a.modification_reason,
            l.leave_type,
            l.status as leave_status_approval
        FROM salesmen s
        LEFT JOIN attendance a ON s.salesman_id = a.salesman_id AND a.date = '$date'
        LEFT JOIN leave_requests l ON s.salesman_id = l.salesman_id AND l.leave_date = '$date' AND l.status = 'Approved'
        WHERE s.status = 'Active' AND DATE(s.created_at) <= '$date'
        " . (!empty($showroom) ? " AND s.showroom_name = '$showroom' " : "") . "
        ORDER BY s.name ASC";

$result = $conn->query($sql);

// Fallback if 'created_at' column doesn't exist (Quick DB Check to avoid crash)
if (!$result && $conn->errno == 1054) { // 1054 = Unknown column
    // Retry without date filter
    $sql = "SELECT 
                s.salesman_id, 
                s.name, 
                s.phone,
                s.showroom_name,
                s.gender, 
                s.promoters, 
                s.shift_start_time,
                s.custom_late_cutoff,
                a.clock_in_time, 
                a.clock_out_time, 
                a.selfie_url, 
                a.clock_out_selfie_url,
                a.reentry_selfie_url,
                a.final_out_selfie_url,
                a.status as att_status,
                a.is_late,
                a.id as attendance_id,
                a.admin_approval,
                a.late_entry_approved,
                a.latitude,
                a.longitude,
                a.out_latitude,   /* 🔥 Puthusa add cheythathu */
                a.out_longitude,  /* 🔥 Puthusa add cheythathu */
                a.modification_reason,
                l.leave_type,
                l.status as leave_status_approval
            FROM salesmen s
            LEFT JOIN attendance a ON s.salesman_id = a.salesman_id AND a.date = '$date'
            LEFT JOIN leave_requests l ON s.salesman_id = l.salesman_id AND l.leave_date = '$date' AND l.status = 'Approved'
            WHERE s.status = 'Active'
            " . (!empty($showroom) ? " AND s.showroom_name = '$showroom' " : "") . "
            ORDER BY s.name ASC";
    $result = $conn->query($sql);
}

$employees = [];

if ($result) {
    while ($row = $result->fetch_assoc()) {

        $status = 'not_logged_in';
        $displayStatus = 'Not In';
        $isLate = 0;
        $lateMinutes = 0;

        // 🔥 NEW: GET PER-SALESMAN LIMITS
        $shiftStartStr = (!empty($row['shift_start_time']) && $row['shift_start_time'] !== '00:00:00' && strtolower($row['shift_start_time']) !== 'null') ? $row['shift_start_time'] : '09:30:00';
        $lateCutoffStr = (!empty($row['custom_late_cutoff']) && $row['custom_late_cutoff'] !== '00:00:00' && strtolower($row['custom_late_cutoff']) !== 'null') ? $row['custom_late_cutoff'] : '10:01:00';

        // 🔥 Calculate isLate flag from custom shift_start_time 
        if (!empty($row['clock_in_time'])) {
            $clockInTimestamp = strtotime($row['clock_in_time']);
            $dateStr = date('Y-m-d', $clockInTimestamp);
            $shiftStartTimeStamp = strtotime("$dateStr $shiftStartStr");

            // 🔥 ADDED 59 SECONDS GRACE: Up to 09:30:59 is still Present
            $shiftStartTimeStampWithGrace = $shiftStartTimeStamp + 59;

            if ($clockInTimestamp > $shiftStartTimeStampWithGrace) {
                $isLate = 1;
                // Calculate late minutes strictly from the shift start minute
                $lateMinutes = round(($clockInTimestamp - $shiftStartTimeStamp) / 60);
            }
        }

        // 🔥 PRIORITY 1: USE DATABASE STATUS (Source of Truth)
        if (!empty($row['att_status'])) {
            $status = strtolower($row['att_status']);
            if ($isLate && $status == 'present' && $row['late_entry_approved'] != 1 && $row['admin_approval'] !== 'Approved') {
                $status = 'late';
            }
            $displayStatus = ucwords($status);
        }
        // 🔥 PRIORITY 2: Calculate fallback dynamically if status is empty but clock_in exists
        elseif (!empty($row['clock_in_time'])) {
            $clockInTimestamp = strtotime($row['clock_in_time']);
            $dateStr = date('Y-m-d', $clockInTimestamp);

            $startTimeStamp = strtotime("$dateStr " . trim($shiftStartStr));
            $lateCutoffStamp = strtotime("$dateStr " . trim($lateCutoffStr));
            if (!$lateCutoffStamp)
                $lateCutoffStamp = strtotime("$dateStr 10:01:00");
            $time0300pm = strtotime("$dateStr 15:01:00");

            if ($clockInTimestamp < $lateCutoffStamp) {
                if ($isLate) {
                    $status = 'late';
                    $displayStatus = 'Late';
                } else {
                    $status = 'present';
                    $displayStatus = 'Present';
                }
            } elseif ($clockInTimestamp < $time0300pm) {
                $status = 'half day';
                $displayStatus = 'Half Day';
            } else {
                $status = 'half day';
                $displayStatus = 'Half Day (Excused)';
            }
        } else {
            // No clock_in and no database status
            $status = 'not_logged_in';
            $displayStatus = 'Not In';
        }

        // 🎉 HOLIDAY OVERRIDE (Highest Priority)
        if ($is_holiday) {
            $status = 'holiday';
            $displayStatus = 'Holiday';
        } elseif (!empty($row['leave_type']) && empty($row['clock_in_time'])) {
            $status = 'on_leave';
            $displayStatus = 'On Leave';
        }

        // 🌟 MODIFICATION REASON OVERRIDE (M/O SO HALF DAY)
        if (isset($row['modification_reason']) && strpos($row['modification_reason'], 'M/O SO HALF DAY') !== false) {
            $status = 'excused';
            $displayStatus = 'M/O SO HALF DAY';
        }

        // 🔥 SAFEGUARD: Ensure status is never empty to prevent "Unknown" in Flutter
        if (empty($status)) {
            $status = 'not_logged_in';
            $displayStatus = 'Not In';
        }

        // --- PROCESS ALL 3 IMAGES ---
        $selfieFullUrl = processUrl($row['selfie_url'], $base_url);
        $outSelfieFullUrl = processUrl($row['clock_out_selfie_url'], $base_url);
        $reentrySelfieFullUrl = processUrl($row['reentry_selfie_url'], $base_url);
        $finalOutSelfieFullUrl = processUrl($row['final_out_selfie_url'] ?? '', $base_url);

        // 🔥 APPROVAL BUTTON LOGIC (Gender-Based Time Window + Past 7 Days)
        $showApprovalButtons = false;

        if (!empty($row['clock_out_time']) && empty($row['admin_approval'])) {
            $clockOutTimestamp = strtotime($row['clock_out_time']);
            $hour = (int) date('H', $clockOutTimestamp); // 24-hour format

            // Check if within past 7 days
            $currentDate = strtotime(date('Y-m-d')); // Today at 00:00:00
            $recordDate = strtotime(date('Y-m-d', $clockOutTimestamp)); // Record date at 00:00:00
            $daysDiff = ($currentDate - $recordDate) / 86400; // Convert seconds to days

            // Only show for records within past 7 days
            if ($daysDiff >= 0 && $daysDiff <= 7) {
                // Gender-based cutoff
                $gender = strtolower($row['gender'] ?? 'male');
                $maxHour = ($gender === 'female') ? 20 : 21; // Girls: 8 PM (20:00), Boys: 9 PM (21:00)

                // Check if between 16:00 (4 PM) and gender-specific cutoff
                if ($hour >= 16 && $hour < $maxHour) {
                    // Only for these statuses
                    if (in_array($status, ['present', 'late', 'half day'])) {
                        $showApprovalButtons = true;
                    }
                }
            }
        }

        $employees[] = [
            "id" => $row['salesman_id'],
            "employeeId" => $row['salesman_id'],
            "name" => $row['name'],
            "phone" => $row['phone'] ?? null,
            "role" => $row['role'] ?? 'Salesman',
            "role_color" => getRoleColor($row['role'] ?? ''), // 🎨 Role Color (PHP-Driven)
            "gender" => $row['gender'] ?? 'Male',
            "showroom_name" => $row['showroom_name'] ?? 'Main Branch', // 🔥 Branch Filter
            "promoters" => $row['promoters'] ?? null,
            "profilePhoto" => null,
            "status" => $status,
            "displayStatus" => $displayStatus,
            "inTime" => !empty($row['clock_in_time']) ? date('h:i A', strtotime($row['clock_in_time'])) : "--:--",
            "outTime" => !empty($row['clock_out_time']) ? date('h:i A', strtotime($row['clock_out_time'])) : "--:--",
            "isLate" => $isLate == 1,
            "lateMinutes" => $lateMinutes,
            "leaveStatus" => $row['leave_type'],
            "adminApproval" => $row['admin_approval'],
            "attendanceId" => $row['attendance_id'],
            "showApprovalButtons" => $showApprovalButtons, // 🔥 NEW: Gender-based button visibility
            // Standardized JSON keys
            "selfieUrl" => $selfieFullUrl,
            "outSelfieUrl" => $outSelfieFullUrl,
            "reentrySelfieUrl" => $reentrySelfieFullUrl,
            "finalOutSelfieUrl" => $finalOutSelfieFullUrl,
            // Keep snake_case for compatibility or debugging
            "out_selfie_url" => $outSelfieFullUrl,
            "reentry_selfie_url" => $reentrySelfieFullUrl,

            "selfieTimestamp" => $row['clock_in_time'],
            "pettaCount" => 0,

            // 🔥 Location Co-ordinates
            "latitude" => $row['latitude'] ?? null,
            "longitude" => $row['longitude'] ?? null,
            "outLatitude" => $row['out_latitude'] ?? null,
            "outLongitude" => $row['out_longitude'] ?? null,

            "holiday_reason" => $is_holiday ? $holiday_reason : "" // 🎉 Holiday Info
        ];
    }
    echo json_encode(["status" => "success", "data" => $employees]);
} else {
    echo json_encode(["status" => "error", "message" => "Database error: " . $conn->error]);
}
$conn->close();
?>
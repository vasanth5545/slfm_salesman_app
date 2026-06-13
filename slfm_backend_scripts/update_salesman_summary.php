<?php
// slfm_backend_scripts/update_salesman_summary.php
// PURPOSE: Calculates and updates monthly performance stats
// UPDATES:
// 1. Percentage Calculation: (Present + HalfDay*0.5) / (DaysElapsed - Holidays) * 100
// 2. Leave Consumption: Saves 'total_days_consumed' to DB.
// 3. Worked Days: Saves 'total_worked_days' to DB.
// 4. Excluded Dates: Tracks and saves days with missing clock-out.

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: POST");
header("Access-Control-Allow-Headers: Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With");

require_once __DIR__ . '/db_connect.php';

// Get Input
$input_data = json_decode(file_get_contents("php://input"), true);
$salesman_id = $input_data['salesman_id'] ?? $_POST['salesman_id'] ?? $_GET['salesman_id'] ?? '';

if (empty($salesman_id)) {
    echo json_encode(["status" => "error", "message" => "Salesman ID is required."]);
    exit();
}

$salesman_id = $conn->real_escape_string($salesman_id);
$current_date = date('Y-m-d');
$current_month = date('Y-m'); // YYYY-MM
$current_day = (int)date('d'); // Day of the month (1-31)

// Helper: Calculate Hours
function calculateHours($start, $end) {
    if (!$start || !$end) return 0;
    $t1 = strtotime($start);
    $t2 = strtotime($end);
    return round(abs($t2 - $t1) / 3600, 2); 
}

// Helper: Format Hours
function formatHours($decimalHours) {
    $hours = floor($decimalHours);
    $minutes = round(($decimalHours - $hours) * 60);
    return sprintf("%02d:%02d:00", $hours, $minutes);
}

// 1. Get Salesman Details
$salesman_sql = "SELECT name, showroom_name FROM salesmen WHERE salesman_id = '$salesman_id'";
$salesman_result = $conn->query($salesman_sql);
$salesman_row = $salesman_result->fetch_assoc();
$salesman_name = $salesman_row['name'] ?? $salesman_id;
$showroom_name = $salesman_row['showroom_name'] ?? 'Unknown';

// 2. Fetch Attendance Records for CURRENT MONTH
$sql = "SELECT date, clock_in_time, clock_out_time, status FROM attendance 
        WHERE salesman_id = '$salesman_id' AND DATE_FORMAT(date, '%Y-%m') = '$current_month'";
$result = $conn->query($sql);

$total_present = 0;
$total_half_days = 0;
$total_leaves_recorded = 0; 
$total_absent = 0;          
$excluded_dates = []; // 🔥 Initialize Array          

$total_hours_month_decimal = 0;
$weekly_hours_decimal = 0;

$current_week_start = date('Y-m-d', strtotime('monday this week'));
$current_week_end = date('Y-m-d', strtotime('sunday this week'));

while ($row = $result->fetch_assoc()) {
    $date = $row['date'];
    $status = $row['status'];
    $in_time = $row['clock_in_time'];
    $out_time = $row['clock_out_time'];
    
    // Normalize Status Check (Handle 'On Leave', 'Leave', 'Sick Leave' etc as Leave)
    $status_lower = strtolower($status);

    // --- STRICT CHECK (As per User) ---
    // Condition: 
    // 1. Status is 'Present' or 'Half Day' (Attempted to work)
    // 2. Clock In Time EXISTS (User came)
    // 3. Clock Out Time is NULL (User didn't close)
    // ACTION: DO NOT CALCULATE (Skip) & STORE DATE
    if ($date != $current_date && (!empty($in_time) && ($in_time != '00:00:00')) && (empty($out_time) || $out_time == '00:00:00')) {
        if ($status_lower == 'present' || $status_lower == 'half day') {
             $excluded_dates[] = $date; // 🛑 Add to Excluded List
             continue; // 🛑 STRICTLY SKIP
        }
    }
    
    // Status Counts
    if ($status_lower == 'present') {
        $total_present++;
    } elseif ($status_lower == 'half day') {
        $total_half_days++;
    } elseif (strpos($status_lower, 'leave') !== false) {
        $total_leaves_recorded++;
    } elseif ($status_lower == 'absent') {
        $total_absent++;
    }
    
    // Calculate Hours
    $hours = 0;
    if ($in_time && $out_time) {
        $hours = calculateHours($in_time, $out_time);
    } elseif ($in_time && $date == $current_date) {
        $hours = calculateHours($in_time, date('Y-m-d H:i:s'));
    }
    
    $total_hours_month_decimal += $hours;
    if ($date >= $current_week_start && $date <= $current_week_end) {
        $weekly_hours_decimal += $hours;
    }
}

// ---------------------------------------------------------
// LOGIC: HOLIDAY COUNT 📅
// ---------------------------------------------------------
$holidays_count = 0;
$h_sql = "SELECT count(*) as h_count FROM holidays 
          WHERE DATE_FORMAT(holiday_date, '%Y-%m') = '$current_month' 
          AND holiday_date <= '$current_date'";
$h_res = $conn->query($h_sql);
if ($h_res && $h_res->num_rows > 0) {
    $h_row = $h_res->fetch_assoc();
    $holidays_count = (int)$h_row['h_count'];
}

// ---------------------------------------------------------
// LOGIC: PERCENTAGE CALCULATION 📊
// Formula: (Present + (Half Day * 0.5)) / (Days_Elapsed - Holidays - ExcludedDays) * 100
// ---------------------------------------------------------
$effective_present = $total_present + ($total_half_days * 0.5);

$days_passed = $current_day; // e.g., 10
// 🔥 SUBTRACT EXCLUDED DATES FROM DENOMINATOR TOO (Optional: User said "don't calculate", usually implies not counting as potential working day either?)
// Let's assume we maintain strict Working Days. If they came and failed to clock out, it's a wasted day, but technically "passed".
// However, standard attendance % is (Attended / Expected).
// If we exclude it from numerator, we usually exclude from expected if it wasn't a valid working opportunity?
// NO, usually "Days Consumed" includes it. 
// Let's stick to simple: Just don't add points. Denominator stays same (Days Passed - Holidays).
// 🛑 STRICT FIX: Subtract Excluded Dates from Denominator
// User wants these dates COMPLETELY IGNORED (not counted as working days)
$working_days_so_far = $days_passed - $holidays_count - count($excluded_dates);

// Safety: avoid division by zero
if ($working_days_so_far <= 0) $working_days_so_far = 1;

$attendance_percentage = ($effective_present / $working_days_so_far) * 100;
if ($attendance_percentage > 100) $attendance_percentage = 100;

// ---------------------------------------------------------
// LOGIC: LEAVE CONSUMPTION 🍃 (UPDATED WITH LEAVE REQUESTS)
// ---------------------------------------------------------
// STEP 1: Calculate Approved Leave Requests (Full Day = 1.0, Half Day = 0.5)
$approved_leave_days = 0;
$leave_req_sql = "SELECT 
                    SUM(CASE 
                        WHEN leave_type = 'Full Day' THEN 1.0 
                        WHEN leave_type = 'Half Day' THEN 0.5 
                        ELSE 0 
                    END) as approved_days
                  FROM leave_requests 
                  WHERE salesman_id = '$salesman_id' 
                  AND DATE_FORMAT(leave_date, '%Y-%m') = '$current_month'
                  AND status = 'Approved'";
$leave_req_res = $conn->query($leave_req_sql);
if ($leave_req_res && $leave_req_res->num_rows > 0) {
    $lr_row = $leave_req_res->fetch_assoc();
    $approved_leave_days = (float)($lr_row['approved_days'] ?? 0);
}

// STEP 2: Attendance-Based Leave Count (Backward Compatible)
// This catches leaves marked in attendance table (time-based or manual)
$attendance_leave_count = $total_leaves_recorded + $total_absent;

// STEP 3: Combine Both (Use MAX to avoid double-counting)
// If admin approved leave AND marked attendance, count once
// Formula: MAX(approved_leaves, attendance_leaves) + (Half Days * 0.5)
$leave_from_requests = $approved_leave_days;
$leave_from_attendance = $attendance_leave_count;

// Use the higher value (in case of discrepancy, trust the higher count)
$total_leave_days = max($leave_from_requests, $leave_from_attendance);

// Add Half Day attendance status (late clock-ins)
$total_days_consumed = $total_leave_days + ($total_half_days * 0.5);

// 🆕 Total Worked Days Logic
$total_worked_days = $total_present + ($total_half_days * 0.5);


// Formatting
$total_working_hours = formatHours($total_hours_month_decimal);
$weekly_working_hours = formatHours($weekly_hours_decimal);
// Today's Check
$today_hours_decimal = 0;
$today_sql = "SELECT clock_in_time, clock_out_time FROM attendance WHERE salesman_id = '$salesman_id' AND date = '$current_date'";
$today_res = $conn->query($today_sql);
if ($today_res && $today_res->num_rows > 0) {
    $t_row = $today_res->fetch_assoc();
    if ($t_row['clock_in_time']) {
        $end_t = $t_row['clock_out_time'] ?? date('Y-m-d H:i:s');
        $today_hours_decimal = calculateHours($t_row['clock_in_time'], $end_t);
    }
}
$today_working_hours = formatHours($today_hours_decimal);

// PREPARE EXCLUDED DATES JSON
$excluded_dates_json = !empty($excluded_dates) ? json_encode($excluded_dates) : NULL;
$excluded_dates_json_sql = $excluded_dates_json ? "'$excluded_dates_json'" : "NULL";

// 3. Update or Insert into Summary Table
$check_sql = "SELECT id FROM salesman_monthly_performance WHERE salesman_id = '$salesman_id' AND report_month = '$current_month'";
$check_res = $conn->query($check_sql);

if ($check_res && $check_res->num_rows > 0) {
    // Update
    $update_sql = "UPDATE salesman_monthly_performance SET 
        total_working_hours = '$total_working_hours',
        today_working_hours = '$today_working_hours',
        weekly_working_hours = '$weekly_working_hours',
        attendance_percentage = '$attendance_percentage',
        total_days_consumed = '$total_days_consumed',
        total_worked_days = '$total_worked_days',
        total_present = '$total_present',
        total_absent = '$total_absent',
        total_half_days = '$total_half_days',
        total_full_leaves = '$total_leaves_recorded',
        excluded_dates = $excluded_dates_json_sql
        WHERE salesman_id = '$salesman_id' AND report_month = '$current_month'";
    $conn->query($update_sql);
} else {
    // Insert
    $insert_sql = "INSERT INTO salesman_monthly_performance 
    (salesman_id, salesman_name, showroom_name, report_month, total_working_hours, today_working_hours, weekly_working_hours, attendance_percentage, total_days_consumed, total_worked_days, total_present, total_absent, total_half_days, total_full_leaves, excluded_dates)
    VALUES 
    ('$salesman_id', '$salesman_name', '$showroom_name', '$current_month', '$total_working_hours', '$today_working_hours', '$weekly_working_hours', '$attendance_percentage', '$total_days_consumed', '$total_worked_days', '$total_present', '$total_absent', '$total_half_days', '$total_leaves_recorded', $excluded_dates_json_sql)";
    $conn->query($insert_sql);
}

// 4. Return Data
echo json_encode([
    "status" => "success",
    "message" => "Performance Updated",
    "data" => [
        "salesman_id" => $salesman_id,
        "month" => $current_month,
        "attendance_percentage" => round($attendance_percentage, 2) . "%",
        "total_days_consumed" => (float)$total_days_consumed,
        "total_worked_days" => (float)$total_worked_days,
        "working_days_passed" => $working_days_so_far,
        "holidays_deducted" => $holidays_count,
        "excluded_dates" => $excluded_dates, // 🔥 Return to App
        "breakdown" => [
            "present" => $total_present,
            "half_days" => $total_half_days,
            "full_leaves" => $total_leaves_recorded,
            "absent" => $total_absent
        ],
        "hours" => [
            "today" => $today_working_hours,
            "week" => $weekly_working_hours,
            "month" => $total_working_hours
        ]
    ]
]);

$conn->close();
?>

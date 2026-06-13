<?php
// slfm_backend_scripts/fix_data.php
// UPDATED: Added 'PART D' for Monthly Performance Sync WITH HOLIDAY LOGIC
// FULL FILE REPLACEMENT - NO LOGIC LOST
header("Content-Type: application/json");
// Connect to DB
$db_path = __DIR__ . '/db_connect.php';
if (file_exists($db_path)) {
    require_once $db_path;
} else {
    echo json_encode(["status" => "error", "message" => "db_connect.php not found"]);
    exit;
}
// Disable error display for cleaner JSON
error_reporting(E_ERROR | E_PARSE);
ini_set('display_errors', 0);
date_default_timezone_set('Asia/Kolkata');
$response = [];
$current_time = time();
$date = date('Y-m-d'); 
$input_month = $_GET['report_month'] ?? $_POST['report_month'] ?? date('Y-m');
// Validate Format YYYY-MM
if (!preg_match("/^\d{4}-\d{2}$/", $input_month)) {
    $input_month = date('Y-m');
}
$current_month = $input_month; // Set the Target Month
$response['target_month'] = $current_month;
$current_day_number = (int)date('d');

// ==========================================
// PART A: SCHEMA UPDATES
// ==========================================
// 1. GPS Status
$check_gps = $conn->query("SHOW COLUMNS FROM salesmen LIKE 'gps_status'");
if ($check_gps->num_rows == 0) {
    $conn->query("ALTER TABLE salesmen ADD COLUMN gps_status VARCHAR(10) DEFAULT 'ON'");
    $response['schema_updates'][] = "Added 'gps_status'";
}
// 2. GENDER
$check_gender = $conn->query("SHOW COLUMNS FROM salesmen LIKE 'gender'");
if ($check_gender->num_rows == 0) {
    $conn->query("ALTER TABLE salesmen ADD COLUMN gender ENUM('male', 'female') DEFAULT 'male'");
    $response['schema_updates'][] = "Added 'gender'";
}
// 3. SHIFT TIMES
$check_shift = $conn->query("SHOW COLUMNS FROM salesmen LIKE 'shift_start_time'");
if ($check_shift->num_rows == 0) {
    $conn->query("ALTER TABLE salesmen ADD COLUMN shift_start_time TIME DEFAULT '09:30:00', ADD COLUMN shift_end_time TIME DEFAULT '21:30:00'");
    $response['schema_updates'][] = "Added shift times";
}
// 4. ATTENDANCE COLUMNS
$att_cols_to_check = [
    'latitude' => "DECIMAL(10, 8) DEFAULT NULL",
    'longitude' => "DECIMAL(11, 8) DEFAULT NULL",
    'status' => "VARCHAR(50) DEFAULT 'Absent'", 
    'clock_out_time' => "DATETIME DEFAULT NULL"
];
foreach ($att_cols_to_check as $col => $def) {
    $check_att = $conn->query("SHOW COLUMNS FROM attendance LIKE '$col'");
    if ($check_att->num_rows == 0) {
        $conn->query("ALTER TABLE attendance ADD COLUMN $col $def");
        $response['attendance_table_fix'][] = "Added '$col'";
    }
}
// 5. RESUME COUNT
$check_resume = $conn->query("SHOW COLUMNS FROM attendance LIKE 'resume_count'");
if ($check_resume->num_rows == 0) {
    $sql_resume = "ALTER TABLE attendance ADD COLUMN resume_count INT DEFAULT 0";
    if ($conn->query($sql_resume) === TRUE) {
        $response['schema_updates'][] = "Added 'resume_count' column";
    }
}
// 6. CLOCK OUT SELFIE URL
$check_out_img = $conn->query("SHOW COLUMNS FROM attendance LIKE 'clock_out_selfie_url'");
if ($check_out_img->num_rows == 0) {
    $sql_out_img = "ALTER TABLE attendance ADD COLUMN clock_out_selfie_url TEXT DEFAULT NULL";
    if ($conn->query($sql_out_img) === TRUE) {
        $response['schema_updates'][] = "Added 'clock_out_selfie_url' column";
    }
}
// 7. LEAVE CANCEL REQUESTS
$cancel_table_sql = "CREATE TABLE IF NOT EXISTS leave_cancel_requests (
    id INT AUTO_INCREMENT PRIMARY KEY,
    salesman_id VARCHAR(50),
    salesman_name VARCHAR(100),
    leave_id INT,
    cancel_reason TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
)";
if ($conn->query($cancel_table_sql) === TRUE) {
    $response['tables'][] = "Checked 'leave_cancel_requests' table";
}
// 8. PERFORMANCE SUMMARY TABLE
// UPDATED: Added total_days_consumed to structure if creating new
$perf_table_sql = "CREATE TABLE IF NOT EXISTS salesman_monthly_performance (
  id int(11) NOT NULL AUTO_INCREMENT,
  salesman_id varchar(20) NOT NULL,
  salesman_name varchar(100) NOT NULL,
  showroom_name varchar(100) NOT NULL,
  report_month varchar(7) NOT NULL,
  total_working_hours varchar(20) DEFAULT '00:00:00',
  today_working_hours varchar(20) DEFAULT '00:00:00',
  weekly_working_hours varchar(20) DEFAULT '00:00:00',
  attendance_percentage decimal(5,2) DEFAULT 0.00,
  total_days_consumed decimal(5,2) DEFAULT 0.00, 
  total_worked_days decimal(5,2) DEFAULT 0.00,
  total_present int(11) DEFAULT 0,
  total_absent int(11) DEFAULT 0,
  total_half_days int(11) DEFAULT 0,
  total_full_leaves int(11) DEFAULT 0,
  excluded_dates text DEFAULT NULL,
  leave_details text DEFAULT NULL,
  last_updated timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (id),
  UNIQUE KEY idx_salesman_month (salesman_id,report_month)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";
if ($conn->query($perf_table_sql) === TRUE) {
    $response['tables'][] = "Checked 'salesman_monthly_performance' table";
}
// 8.1 CHECK FOR NEW COLUMN (Safe Add)
$check_consumed = $conn->query("SHOW COLUMNS FROM salesman_monthly_performance LIKE 'total_days_consumed'");
if ($check_consumed && $check_consumed->num_rows == 0) {
    $conn->query("ALTER TABLE salesman_monthly_performance ADD COLUMN total_days_consumed DECIMAL(5,2) DEFAULT 0.00 AFTER attendance_percentage");
    $response['schema_updates'][] = "Added 'total_days_consumed' column";
}
// 8.2 CHECK FOR TOTAL WORKED DAYS
$check_twd = $conn->query("SHOW COLUMNS FROM salesman_monthly_performance LIKE 'total_worked_days'");
if ($check_twd && $check_twd->num_rows == 0) {
    $conn->query("ALTER TABLE salesman_monthly_performance ADD COLUMN total_worked_days DECIMAL(5,2) DEFAULT 0.00 AFTER total_days_consumed");
    $response['schema_updates'][] = "Added 'total_worked_days' column";
}

// 8.3 CHECK FOR EXCLUDED DATES (🔥 NEW)
$check_exc = $conn->query("SHOW COLUMNS FROM salesman_monthly_performance LIKE 'excluded_dates'");
if ($check_exc && $check_exc->num_rows == 0) {
    $conn->query("ALTER TABLE salesman_monthly_performance ADD COLUMN excluded_dates TEXT DEFAULT NULL AFTER report_month");
    $response['schema_updates'][] = "Added 'excluded_dates' column";
}

// 8.4 CHECK FOR HOLIDAYS TABLE
$sql_holidays = "CREATE TABLE IF NOT EXISTS `holidays` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `holiday_date` date NOT NULL,
  `reason` varchar(255) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `holiday_date` (`holiday_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";
$conn->query($sql_holidays);


// ==========================================
// PART B: DATA FIXES
// ==========================================
// 1. Get All Active Salesmen
$input_id = $_GET['salesman_id'] ?? $_POST['salesman_id'] ?? '';
$salesmen_list = [];

if (!empty($input_id)) {
    // Specific Salesman Mode 🎯
    $s_sql = "SELECT salesman_id, name, showroom_name FROM salesmen WHERE salesman_id = '$input_id' AND status = 'Active'";
    $response['mode'] = "Single Salesman Fix: $input_id";
} else {
    // Bulk Mode 🌍
    $s_sql = "SELECT salesman_id, name, showroom_name FROM salesmen WHERE status = 'Active'";
    $response['mode'] = "Bulk Fix (All Active Salesmen)";
}

$s_res = $conn->query($s_sql);
if ($s_res) {
    while($row = $s_res->fetch_assoc()) {
        $salesmen_list[] = $row;
    }
}

// 9. SYNC NAMES
// (Only sync if filtering is not strict or do it for consistency anyway)
$conn->query("UPDATE attendance a JOIN salesmen s ON a.salesman_id = s.salesman_id SET a.showroom_name = s.showroom_name WHERE a.showroom_name IS NULL OR a.showroom_name = ''");
$conn->query("UPDATE attendance a JOIN salesmen s ON a.salesman_id = s.salesman_id SET a.salesman_name = s.name WHERE a.salesman_name IS NULL OR a.salesman_name = ''");

// 9.1 FIX HUGE DURATION / NEGATIVE DURATION BUG (Vasanth Issue) 🐛
// Logic: If Clock Out is BEFORE Clock In (Date mismatch), fix the Date of Clock Out to match Clock In
$sql_bug_fix = "SELECT id, clock_in_time, clock_out_time FROM attendance WHERE clock_out_time < clock_in_time";
$bug_res = $conn->query($sql_bug_fix);
$bug_count = 0;
if ($bug_res) {
    while ($b_row = $bug_res->fetch_assoc()) {
        $in_ts = strtotime($b_row['clock_in_time']);
        $out_ts = strtotime($b_row['clock_out_time']);
        
        // If Out Year/Month/Day doesn't match In Year/Month/Day, but time is valid
        // We trust the TIME of the output, but force the DATE of the input
        $correct_out_date_str = date('Y-m-d', $in_ts);
        $correct_out_time_str = date('H:i:s', $out_ts);
        $new_out_datetime = "$correct_out_date_str $correct_out_time_str";
        
        // Double check: If new out is still before in (e.g. overnight work), add 1 day? 
        // For this app, we assume same day mostly. If new out < in, it might be next day (rare).
        // Let's assume SAME DAY fix for safety first as per Vasanth case (29th In, 23rd Out -> 29th Out).
        
        $conn->query("UPDATE attendance SET clock_out_time = '$new_out_datetime' WHERE id = " . $b_row['id']);
        $bug_count++;
    }
}
$response['data_integrity_fix'] = "Fixed $bug_count records with 'Previous Date' ClockOut Bug.";

// 10. TASK 6 FIX
$sql_check = "SELECT id, clock_out_time, status FROM attendance WHERE date = '$date' AND clock_out_time IS NOT NULL";
$result = $conn->query($sql_check);
$updated_count = 0;
if ($result) {
    while ($row = $result->fetch_assoc()) {
        $last_out = strtotime($row['clock_out_time']);
        $diff_mins = ($current_time - $last_out) / 60;
        if ($diff_mins > 60 && $row['status'] != 'Leave') {
            $conn->query("UPDATE attendance SET status = 'Leave' WHERE id = " . $row['id']);
            $updated_count++;
        }
    }
}
$response['task_6_fix'] = "Updated $updated_count records to 'Leave' (>1 hour gap).";

// 10.1 MISSING OUT TIME FIX - REMOVED AS PER REQUEST
// Logic: Records with missing Out Time will be IGNORED in calculation logic.

// 11. TASK 1 FIX
$sql_fix_present = "SELECT id, clock_in_time FROM attendance WHERE date = '$date' AND status = 'Present'";
$res_fix = $conn->query($sql_fix_present);
$fixed_count = 0;
if ($res_fix) {
    while ($row = $res_fix->fetch_assoc()) {
        if (!empty($row['clock_in_time'])) {
            $in_time_str = date('H:i:s', strtotime($row['clock_in_time']));
            if ($in_time_str > '10:00:00') {
                $correct_status = ($in_time_str > '15:00:00') ? 'Leave' : 'Half Day';
                $conn->query("UPDATE attendance SET status = '$correct_status' WHERE id = " . $row['id']);
                $fixed_count++;
            }
        }
    }
}
$response['task_1_fix'] = "Fixed $fixed_count records from 'Present' to 'Half Day'/'Leave'.";

// 12. TIME CONSISTENCY FIX (Targeted or Bulk) 🕒
$input_date = $_GET['date'] ?? $_POST['date'] ?? '';

$sql_consist = "SELECT a.id, a.clock_in_time, a.clock_out_time, a.status, s.gender 
                FROM attendance a 
                JOIN salesmen s ON a.salesman_id = s.salesman_id 
                WHERE a.clock_in_time IS NOT NULL";

// Apply Filters
if (!empty($input_id)) {
    $sql_consist .= " AND a.salesman_id = '$input_id'";
}
if (!empty($input_date)) {
    $sql_consist .= " AND a.date = '$input_date'";
    $response['date_filter'] = "Applied to Date: $input_date";
} else {
    // Default to Current Month if no date specified
    $sql_consist .= " AND DATE_FORMAT(a.date, '%Y-%m') = '$current_month'";
}

$res_consist = $conn->query($sql_consist);
$consist_fix_count = 0;

if ($res_consist) {
    while ($row = $res_consist->fetch_assoc()) {
        $in_time = !empty($row['clock_in_time']) ? date('H:i:s', strtotime($row['clock_in_time'])) : null;
        $out_time = !empty($row['clock_out_time']) ? date('H:i:s', strtotime($row['clock_out_time'])) : null;
        
        $current_status = $row['status'];
        $gender = strtolower($row['gender'] ?? 'male');

        // Rule 1: Determine Base Status from In-Time
        $calc_status = 'Present';
        if ($in_time > '15:00:00') {
            $calc_status = 'Leave';
        } elseif ($in_time > '10:00:00') {
            $calc_status = 'Half Day';
        }

        // Rule 2: Downgrade based on Out-Time (if exists)
        if ($out_time && ($calc_status == 'Present' || $calc_status == 'Half Day')) {
            $exit_cutoff = ($gender == 'female') ? '20:00:00' : '21:00:00';
            
            // Logic Mapped from attendance.php
            if ($out_time < '14:30:00') {
                $calc_status = 'Leave';
            } elseif ($out_time < $exit_cutoff) {
                // Left before Safe Window -> Half Day
                // (Unless it was already Leave, which is handled above)
                $calc_status = 'Half Day';
            }
            // If >= exit_cutoff, status remains (Present stays Present)
        }

        // Fix Bug: Restore 'Present' if it was wrongly marked Half Day/Leave but times are safe
        // (Only if auto-correction is desired. Here we strictly enforce calculated status)
        
        if ($calc_status != $current_status) {
            $conn->query("UPDATE attendance SET status = '$calc_status' WHERE id = " . $row['id']);
            $consist_fix_count++;
        }
    }
}
$response['consistency_fix'] = "Deep Fixed $consist_fix_count records.";

// ==========================================
// PART C: INFRASTRUCTURE
// ==========================================
$folders = ['uploads', 'uploads/attendance', 'uploads/bills', 'uploads/damage_reports'];
foreach ($folders as $dir) { if (!is_dir($dir)) mkdir($dir, 0777, true); }
// ==========================================
// PART D: MONTHLY PERFORMANCE SUMMARY SYNC
// ==========================================
// Helper Functions
function calculateHours($start, $end) {
    if (!$start || !$end) return 0;
    $t1 = strtotime($start);
    $t2 = strtotime($end);
    return abs($t2 - $t1) / 3600; // Float hours
}
function formatHours($decimalHours) {
    $hours = floor($decimalHours);
    $minutes = round(($decimalHours - $hours) * 60);
    return sprintf("%02d:%02d:00", $hours, $minutes);
}


// FETCH HOLIDAYS COUNT 📅
// -----------------------
$holidays_count = 0;
// We need to count holidays occurring UP TO THE END of the target month (or today if current)
$end_of_target_month = date("Y-m-t", strtotime($current_month . "-01"));
$limit_date = ($current_month == date('Y-m')) ? $date : $end_of_target_month;

$h_sql = "SELECT count(*) as h_count FROM holidays 
          WHERE DATE_FORMAT(holiday_date, '%Y-%m') = '$current_month' 
          AND holiday_date <= '$limit_date'";
$h_res = $conn->query($h_sql);
if ($h_res && $h_res->num_rows > 0) {
    $h_row = $h_res->fetch_assoc();
    $holidays_count = (int)$h_row['h_count'];
}


$perf_updated_count = 0;
$current_week_start = date('Y-m-d', strtotime('monday this week'));
$current_week_end = date('Y-m-d', strtotime('sunday this week'));
foreach ($salesmen_list as $salesman) {
    $sid = $salesman['salesman_id'];
    $sname = $salesman['name'];
    $s_showroom = $salesman['showroom_name'];
    // 2. Fetch Attendance for Current Month
    $att_sql = "SELECT date, clock_in_time, clock_out_time, status FROM attendance 
                WHERE salesman_id = '$sid' AND DATE_FORMAT(date, '%Y-%m') = '$current_month'";
    
    $att_res = $conn->query($att_sql);
    
    $total_hours_decimal = 0;
    $today_hours_decimal = 0;
    $weekly_hours_decimal = 0;
    
    $present_count = 0;
    $half_day_count = 0;
    $leave_count = 0; // Recorded 'Leave' status
    $absent_count = 0; // Recorded 'Absent' status
    $excluded_dates = []; // 🔥 Initialize Array for this salesman

    // Loop through records
    while ($row = $att_res->fetch_assoc()) {
        $r_date = $row['date'];
        $r_status = $row['status'];
        $in_time = $row['clock_in_time'];
        $out_time = $row['clock_out_time'];
        
        // Normalize Status Check (Handle 'On Leave', 'Leave', 'Sick Leave' etc as Leave)
        $status_lower = strtolower($r_status);

        // --- STRICT CHECK (As per User) ---
        // Condition: 
        // 1. Status is 'Present' or 'Half Day'
        // 2. Clock In Time EXISTS (User came)
        // 3. Clock Out Time is NULL (User didn't close)
        // ACTION: DO NOT CALCULATE (Skip) & STORE DATE
        if ($r_date != $date && !empty($in_time) && empty($out_time)) {
             if ($status_lower == 'present' || $status_lower == 'half day') {
                 $excluded_dates[] = $r_date; // 🛑 Add to Excluded List
                 continue; // 🛑 STRICTLY SKIP
             }
        }
        
        // Status Counts
        if ($status_lower == 'present') {
            $present_count++;
        } elseif ($status_lower == 'half day') {
            $half_day_count++;
        } elseif (strpos($status_lower, 'leave') !== false) {
             // Catches 'Leave', 'On Leave', 'Sick Leave'
            $leave_count++;
        } elseif ($status_lower == 'absent') {
            $absent_count++;
        }
        
        // Hours Calculation
        $hours = 0;
        if ($in_time && $out_time) {
            $hours = calculateHours($in_time, $out_time);
        } elseif ($in_time && $r_date == $date) {
            // Still working today
            $hours = calculateHours($in_time, date('Y-m-d H:i:s'));
            $today_hours_decimal = $hours;
        }
        
        $total_hours_decimal += $hours;
        
        // Weekly Hours
        if ($r_date >= $current_week_start && $r_date <= $current_week_end) {
            $weekly_hours_decimal += $hours;
        }
    }
    
    // Percentage Calculation 📊
    // Formula: (Present + (Half Day * 0.5)) / (Days_Elapsed - Holidays) * 100
    // --------------------------------------------------------------------------------
    $effective_present = $present_count + ($half_day_count * 0.5);
    
    // Days Passed
    if ($current_month == date('Y-m')) {
        $days_passed = (int)date('d');
    } else {
        $days_passed = (int)date('t', strtotime($current_month . "-01")); // Total days in that month
    }
    $working_days_so_far = $days_passed - $holidays_count;
    
    if ($working_days_so_far <= 0) $working_days_so_far = 1; // Safety
    
    $percentage = ($effective_present / $working_days_so_far) * 100;
    if ($percentage > 100) $percentage = 100;

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
                      WHERE salesman_id = '$sid' 
                      AND DATE_FORMAT(leave_date, '%Y-%m') = '$current_month'
                      AND status = 'Approved'";
    $leave_req_res = $conn->query($leave_req_sql);
    if ($leave_req_res && $leave_req_res->num_rows > 0) {
        $lr_row = $leave_req_res->fetch_assoc();
        $approved_leave_days = (float)($lr_row['approved_days'] ?? 0);
    }
    
    // STEP 2: Attendance-Based Leave Count (Backward Compatible)
    $attendance_leave_count = $leave_count + $absent_count;
    
    // STEP 3: Combine Both (Use MAX to avoid double-counting)
    $leave_from_requests = $approved_leave_days;
    $leave_from_attendance = $attendance_leave_count;
    $total_leave_days = max($leave_from_requests, $leave_from_attendance);
    
    // Add Half Day attendance status (late clock-ins)
    $total_consumed_calc = $total_leave_days + ($half_day_count * 0.5);

    // 🆕 Total Worked Days Logic (New Column)
    // Formula: Present (1) + Half Day (0.5)
    $total_worked_days = $present_count + ($half_day_count * 0.5);

    
    // Format Strings
    $fmt_total_hours = formatHours($total_hours_decimal);
    $fmt_today_hours = formatHours($today_hours_decimal);
    $fmt_weekly_hours = formatHours($weekly_hours_decimal);
    
    // PREPARE EXCLUDED DATES JSON
    $excluded_dates_json = !empty($excluded_dates) ? json_encode($excluded_dates) : NULL;
    $excluded_dates_json_sql = $excluded_dates_json ? "'$excluded_dates_json'" : "NULL";

    // 3. Upsert into Performance Table
    $chk_sql = "SELECT id FROM salesman_monthly_performance WHERE salesman_id = '$sid' AND report_month = '$current_month'";
    $chk_res = $conn->query($chk_sql);
    
    if ($chk_res->num_rows > 0) {
        $up_sql = "UPDATE salesman_monthly_performance SET 
            total_working_hours = '$fmt_total_hours',
            today_working_hours = '$fmt_today_hours',
            weekly_working_hours = '$fmt_weekly_hours',
            attendance_percentage = '$percentage',
            total_days_consumed = '$total_consumed_calc', 
            total_worked_days = '$total_worked_days',
            total_present = '$present_count',
            total_absent = '$absent_count',
            total_half_days = '$half_day_count',
            total_full_leaves = '$leave_count',
            excluded_dates = $excluded_dates_json_sql
            WHERE salesman_id = '$sid' AND report_month = '$current_month'";
        $conn->query($up_sql);
    } else {
        $in_sql = "INSERT INTO salesman_monthly_performance 
        (salesman_id, salesman_name, showroom_name, report_month, total_working_hours, today_working_hours, weekly_working_hours, attendance_percentage, total_days_consumed, total_worked_days, total_present, total_absent, total_half_days, total_full_leaves, excluded_dates)
        VALUES 
        ('$sid', '$sname', '$s_showroom', '$current_month', '$fmt_total_hours', '$fmt_today_hours', '$fmt_weekly_hours', '$percentage', '$total_consumed_calc', '$total_worked_days', '$present_count', '$absent_count', '$half_day_count', '$leave_count', $excluded_dates_json_sql)";
        $conn->query($in_sql);
    }
    $perf_updated_count++;
}
$response['performance_sync'] = "Updated monthly summary for $perf_updated_count salesmen.";
$response['logic_info'] = "Holidays deduced: $holidays_count. Days passed: $current_day_number.";

echo json_encode(["status" => "success", "report" => $response]);
$conn->close();
?>

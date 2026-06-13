<?php
// slfm_api/billing_counter/get_attendance_report.php
// PURPOSE: Reports attendance matching 'Salesman Monthly Performance' logic strictly.
// FEATURES:
// 1. Separate Counts for Present, Half Day, Absent, Leave.
// 2. EXCLUDES 'Incomplete Days' (No Clock Out) to match Summary Tab logic.
// 3. EXCLUDES 'Holidays' from Absent count (User request: "holiday va than absent nu calculate paannidu").
// 4. Total Work Calculation = Present + (Half Day * 0.5).

error_reporting(E_ERROR | E_PARSE);
ini_set('display_errors', 0);

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");
date_default_timezone_set('Asia/Kolkata');

// 🔌 DB CONNECT
$db_path_current = __DIR__ . '/db_connect.php';
$db_path_parent = __DIR__ . '/../db_connect.php';

if (file_exists($db_path_current)) {
    require_once $db_path_current;
} elseif (file_exists($db_path_parent)) {
    require_once $db_path_parent;
} else {
    http_response_code(500);
    echo json_encode(["status" => "error", "message" => "db_connect.php not found"]);
    exit;
}

// 5. Get Input Data
$start_date = $_POST['start_date'] ?? $_GET['start_date'] ?? date('Y-m-01');
$end_date   = $_POST['end_date']   ?? $_GET['end_date']   ?? date('Y-m-t');
$current_date = date('Y-m-d');

// 6. Fetch Active Salesmen
$salesmen_sql = "SELECT salesman_id, name, showroom_name, created_at FROM salesmen WHERE status = 'Active' ORDER BY name ASC";
$salesmen_res = $conn->query($salesmen_sql);

// 6b. Fetch Holidays for the range (To exclude from Absent count)
$holidays = [];
$h_sql = "SELECT holiday_date FROM holidays WHERE holiday_date BETWEEN '$start_date' AND '$end_date'";
$h_res = $conn->query($h_sql);
if ($h_res) {
    while ($h_row = $h_res->fetch_assoc()) {
        $holidays[] = $h_row['holiday_date']; // Store dates like '2026-02-02'
    }
}

$report_data = [];

if ($salesmen_res && $salesmen_res->num_rows > 0) {
    while ($salesman = $salesmen_res->fetch_assoc()) {
        $sid = $salesman['salesman_id'];
        $name = $salesman['name'];
        $showroom = $salesman['showroom_name'] ?? 'Unknown';

        // 7. Count Statuses with CASE Logic + EXCLUSION LOGIC
        // Rule 1: If date != today AND clock_in EXISTS AND clock_out IS NULL -> EXCLUDE (Incomplete Day)
        // Rule 2: If date IS A HOLIDAY -> DO NOT COUNT AS ABSENT (Even if marked Absent in DB)
        
        $att_rows_sql = "SELECT date, status, is_late, clock_in_time, clock_out_time 
                         FROM attendance 
                         WHERE salesman_id = '$sid' 
                         AND date BETWEEN '$start_date' AND '$end_date'";
        $att_rows_res = $conn->query($att_rows_sql);
        
        $present_count = 0;
        $half_day_count = 0;
        $absent_count = 0;
        $leave_att_count = 0;
        $late_count = 0;
        
        $join_date_only = !empty($salesman['created_at']) ? date('Y-m-d', strtotime($salesman['created_at'])) : '2000-01-01';

        if ($att_rows_res) {
            while ($row = $att_rows_res->fetch_assoc()) {
                $r_date = $row['date'];
                $r_status = $row['status']; // Case sensitive from DB
                $r_in = $row['clock_in_time'];
                $r_out = $row['clock_out_time'];
                $r_late = (int)$row['is_late'];
                
                // Normalization
                $status_lower = strtolower($r_status);

                // 🛑 JOIN DATE FILTER (Skip Absent before join)
                if ($status_lower == 'absent' && $r_date < $join_date_only) {
                    continue;
                }
                
                // --- EXCLUSION LOGIC 1: INCOMPLETE DAYS ---
                if ($r_date != $current_date && !empty($r_in) && empty($r_out)) {
                    if ($status_lower == 'present' || $status_lower == 'half day') {
                        continue; // 🛑 STRICT SKIP
                    }
                }

                // --- EXCLUSION LOGIC 2: HOLIDAYS ---
                // If this date is in our holidays list, IGNORE 'Absent' status.
                // (We still count Present if they worked on a holiday, usually)
                if (in_array($r_date, $holidays)) {
                    if ($status_lower == 'absent') {
                         continue; // 🛑 SKIP ABSENT ON HOLIDAY
                    }
                    // What if status is 'Leave'? Usually holiday overrides leave too.
                    if (strpos($status_lower, 'leave') !== false) {
                         continue; // 🛑 SKIP LEAVE ON HOLIDAY
                    }
                }
                
                // Count remaining valid statuses
                if ($status_lower == 'present') {
                    $present_count++;
                    if ($r_late == 1) $late_count++; 
                } elseif ($status_lower == 'half day') {
                    $half_day_count++;
                     if ($r_late == 1) $late_count++;
                } elseif ($status_lower == 'absent') {
                    $absent_count++;
                } elseif (strpos($status_lower, 'leave') !== false) {
                    $leave_att_count++;
                }
            }
        }

        // 8. Count Approved Leaves
        // Note: Should we filter holidays from approved leaves too? 
        // Summary logic doesn't explicitly filter holidays from approved leaves query,
        // but let's assume if approved, it counts. 
        // However, user said "holiday... calculate panna theva illa".
        // Let's stick to fixing the specific "Absent" issue first.
        
        $leave_req_sql = "SELECT COUNT(*) as leave_days_req
                          FROM leave_requests 
                          WHERE salesman_id = '$sid' 
                          AND status = 'Approved' 
                          AND leave_date BETWEEN '$start_date' AND '$end_date'";
        
        $leave_req_result = $conn->query($leave_req_sql);
        $leave_req_row = ($leave_req_result) ? $leave_req_result->fetch_assoc() : ['leave_days_req' => 0];

        // 9. CALCULATE METRICS
        $final_leave_count = max($leave_att_count, (int)$leave_req_row['leave_days_req']);
        $total_worked = $present_count + ($half_day_count * 0.5);

        $report_data[] = [
            'id'            => $sid,
            'name'          => $name,
            'showroom_name' => $showroom,
            'present'       => $present_count,
            'half_day'      => $half_day_count,
            'absent'        => $absent_count,
            'leave'         => $final_leave_count,
            'late'          => $late_count,
            'total_working_days' => $total_worked,
            'join_date'     => $salesman['created_at'] // 🔥 Added Join Date
        ];
    }
}

// 10. Return JSON Response
echo json_encode([
    "status" => "success", 
    "data"   => $report_data,
    "period" => [
        "start" => $start_date,
        "end"   => $end_date
    ]
]);

$conn->close();
?>

<?php
// slfm_api/billing_counter/get_all_salesman_timing_report.php
// PURPOSE: Fetches attendance timings for ALL salesmen in a showroom for a period.

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
$showroom   = $_POST['showroom']   ?? $_GET['showroom']   ?? 'All';
$start_date = $_POST['start_date'] ?? $_GET['start_date'] ?? date('Y-m-01');
$end_date   = $_POST['end_date']   ?? $_GET['end_date']   ?? date('Y-m-t');

// 6. Fetch Salesmen for this branch
$s_clause = ($showroom === 'All' || empty($showroom)) ? "" : " AND showroom_name = '$showroom' ";
$salesmen_sql = "SELECT salesman_id, name, showroom_name, created_at FROM salesmen WHERE status = 'Active' $s_clause ORDER BY name ASC";
$salesmen_res = $conn->query($salesmen_sql);

$salesmen_list = [];
$sid_array = [];
if ($salesmen_res) {
    while ($s = $salesmen_res->fetch_assoc()) {
        $salesmen_list[$s['salesman_id']] = $s;
        $salesmen_list[$s['salesman_id']]['join_date_only'] = !empty($s['created_at']) ? date('Y-m-d', strtotime($s['created_at'])) : '2000-01-01';
        $salesmen_list[$s['salesman_id']]['join_time_fmt']  = !empty($s['created_at']) ? date('h:i A', strtotime($s['created_at'])) : '--:--';
        $sid_array[] = "'" . $s['salesman_id'] . "'";
    }
}

if (empty($sid_array)) {
    echo json_encode(["status" => "success", "data" => (object)[], "message" => "No salesmen found for this showroom"]);
    exit;
}

// 7. Fetch Attendance Timings
$sid_list = implode(',', $sid_array);
$att_sql = "SELECT salesman_id, date, status, clock_in_time, clock_out_time, is_late 
            FROM attendance 
            WHERE salesman_id IN ($sid_list) 
            AND date BETWEEN '$start_date' AND '$end_date'
            ORDER BY date ASC, salesman_id ASC";
$att_res = $conn->query($att_sql);

$attendance_records = [];
$today_str = date('Y-m-d');

if ($att_res) {
    while ($row = $att_res->fetch_assoc()) {
        $r_date = $row['date'];
        $sid = $row['salesman_id'];
        $s_info = $salesmen_list[$sid];
        
        $status_lower = strtolower($row['status']);
        $in_t = $row['clock_in_time'];
        $out_t = $row['clock_out_time'];
        
        // 1. Join Date Filter: Skip ABSENT before join date
        if ($status_lower == 'absent' && $r_date < $s_info['join_date_only']) {
            continue;
        }

        $disp_status = $row['status'];
        $status_lower = strtolower($disp_status);

        if ($status_lower == 'present') {
            $disp_status = 'Present';
        } elseif ($status_lower == 'half day') {
            $disp_status = 'Half day';
        } elseif ($status_lower == 'absent') {
            $disp_status = 'Absent';
        } elseif (strpos($status_lower, 'leave') !== false) {
            $disp_status = 'Leave';
        }

        $remarks = ($row['is_late'] == 1 ? "Late" : "");

        // 2. Missing Clock-out Filter (Past Dates)
        if ($r_date != $today_str && !empty($in_t) && empty($out_t)) {
            if ($status_lower == 'present' || $status_lower == 'half day') {
                $disp_status = "--"; 
                $remarks = ($remarks ? "$remarks | " : "") . "No Clock-out";
            }
        }
        
        $entry = [
            'name'      => $s_info['name'],
            'showroom'  => $s_info['showroom_name'],
            'status'    => $disp_status,
            'in_time'   => !empty($in_t) ? date('h:i A', strtotime($in_t)) : '--:--',
            'out_time'  => !empty($out_t) ? date('h:i A', strtotime($out_t)) : '--:--',
            'remarks'   => $remarks,
            'join_date' => $s_info['join_date_only'],
            'join_time' => $s_info['join_time_fmt'] // 🔥 ADDED JOIN TIME
        ];
        
        $attendance_records[$r_date][] = $entry;
    }
}

// 8. Return JSON
echo json_encode([
    "status" => "success",
    "showroom" => $showroom,
    "period" => ["start" => $start_date, "end" => $end_date],
    "data" => (object)$attendance_records
]);

$conn->close();
?>

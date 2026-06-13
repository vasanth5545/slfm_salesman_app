<?php
// slfm_api/billing_counter/get_salesman_monthly_report.php
// PURPOSE: Fetches detailed day-by-day attendance for a single salesman for a date range.

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
$salesman_id = $_POST['salesman_id'] ?? $_GET['salesman_id'] ?? '';
$start_date  = $_POST['start_date']  ?? $_GET['start_date']  ?? date('Y-m-01');
$end_date    = $_POST['end_date']    ?? $_GET['end_date']    ?? date('Y-m-t');

if (empty($salesman_id)) {
    echo json_encode(["status" => "error", "message" => "Salesman ID is required"]);
    exit;
}

// 6. Fetch Salesman Details
$salesman_sql = "SELECT name, showroom_name FROM salesmen WHERE salesman_id = '$salesman_id' LIMIT 1";
$salesman_res = $conn->query($salesman_sql);
if (!$salesman_res || $salesman_res->num_rows == 0) {
    echo json_encode(["status" => "error", "message" => "Salesman not found"]);
    exit;
}
$salesman_info = $salesman_res->fetch_assoc();

// 6b. Fetch Holidays for the range
$holidays = [];
$h_sql = "SELECT holiday_date, name FROM holidays WHERE holiday_date BETWEEN '$start_date' AND '$end_date'";
$h_res = $conn->query($h_sql);
if ($h_res) {
    while ($h_row = $h_res->fetch_assoc()) {
        $holidays[$h_row['holiday_date']] = $h_row['name'];
    }
}

// 7. Fetch Attendance Entries
$attendance_data = [];
$att_sql = "SELECT date, status, clock_in_time, clock_out_time, is_late, late_entry_approved 
            FROM attendance 
            WHERE salesman_id = '$salesman_id' 
            AND date BETWEEN '$start_date' AND '$end_date'";
$att_res = $conn->query($att_sql);
if ($att_res) {
    while ($row = $att_res->fetch_assoc()) {
        $attendance_data[$row['date']] = $row;
    }
}

// 8. Iterate through every day in range to build complete report
$report_rows = [];
$current_ts = strtotime($start_date);
$end_ts     = strtotime($end_date);

while ($current_ts <= $end_ts) {
    $date_str = date('Y-m-d', $current_ts);
    $day_name = date('D', $current_ts); // Mon, Tue, etc.
    
    $row_data = [
        'date'     => $date_str,
        'day'      => $day_name,
        'status'   => 'Absent', // Default
        'in_time'  => '--:--',
        'out_time' => '--:--',
        'remarks'  => ''
    ];
    
    // Check Holiday first
    if (isset($holidays[$date_str])) {
        $row_data['status'] = 'Holiday';
        $row_data['remarks'] = $holidays[$date_str];
    }
    
    // Check Attendance record
    if (isset($attendance_data[$date_str])) {
        $att = $attendance_data[$date_str];
        $row_data['status'] = $att['status'];
        
        // Format In Time
        if (!empty($att['clock_in_time'])) {
            $row_data['in_time'] = date('h:i A', strtotime($att['clock_in_time']));
        }
        
        // Format Out Time
        if (!empty($att['clock_out_time'])) {
            $row_data['out_time'] = date('h:i A', strtotime($att['clock_out_time']));
        } else if (!empty($att['clock_in_time'])) {
            // Clocked in but no clock out
            if ($date_str != date('Y-m-d')) {
                $row_data['remarks'] = "No Clock-out";
            } else {
                $row_data['remarks'] = "Ongoing";
            }
        }
        
        // Late Entry Remarks
        if ($att['is_late'] == 1) {
            $row_data['remarks'] .= ($row_data['remarks'] ? " | " : "") . "Late Entry";
            if ($att['late_entry_approved'] == 1) {
                $row_data['remarks'] .= " (Approved)";
            }
        }
    }
    
    $report_rows[] = $row_data;
    $current_ts = strtotime("+1 day", $current_ts);
}

// 9. Return JSON
echo json_encode([
    "status" => "success",
    "salesman" => [
        "id" => $salesman_id,
        "name" => $salesman_info['name'],
        "showroom" => $salesman_info['showroom_name']
    ],
    "data" => $report_rows
]);

$conn->close();
?>

<?php
// billing_counter/mark_absent.php
// Smart Trigger: Checks LAST 7 DAYS.
// FIXED: Checks 'created_at' to prevent marking absent before joining date.
// UPDATED: Syncs 'Approved' Leaves to Attendance Status 'On Leave'
header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *"); 
date_default_timezone_set('Asia/Kolkata');
require '../db_connect.php';
$input_data = json_decode(file_get_contents('php://input'), true);
$specific_salesman_id = $input_data['salesman_id'] ?? $_POST['salesman_id'] ?? null;
$current_time = date('H:i');
$cutoff_time = '10:00'; 
$today = date('Y-m-d');
// 1. Determine End Date
if ($current_time >= $cutoff_time) {
    $end_date_str = $today;
} else {
    $end_date_str = date('Y-m-d', strtotime("-1 days"));
}
// 2. Determine Start Date (7 days back)
$start_date_str = date('Y-m-d', strtotime("$end_date_str -6 days"));
// 3. Generate Date List
$dates_to_check = [];
$current_date = $start_date_str;
while ($current_date <= $end_date_str) {
    $dates_to_check[] = $current_date;
    $current_date = date('Y-m-d', strtotime("$current_date +1 days"));
}
$absent_count = 0;
$cleaned_count = 0;
$skipped_new_joinee_count = 0;
$leave_synced = 0;
$marked_ids = [];
foreach ($dates_to_check as $process_date) {
    
    // SQL: Select Salesmen (Added 'created_at' to check joining date)
    $salesmen_sql = "SELECT salesman_id, name, showroom_name, created_at FROM salesmen WHERE status = 'Active'";
    if ($specific_salesman_id) {
        $salesmen_sql .= " AND salesman_id = '$specific_salesman_id'";
    }
    
    $salesmen_result = $conn->query($salesmen_sql);
    if ($salesmen_result && $salesmen_result->num_rows > 0) {
        while($row = $salesmen_result->fetch_assoc()) {
            $sid = $row['salesman_id'];
            $sname = $row['name']; 
            $showroom = $row['showroom_name'] ?? 'Main Branch';
            
            // --- 🔥 JOINING DATE CHECK (Preserved) ---
            $join_date = date('Y-m-d', strtotime($row['created_at']));
            if ($process_date < $join_date) {
                $skipped_new_joinee_count++;
                continue; 
            }
            // A. Check Attendance
            $check_attendance = "SELECT id, status FROM attendance WHERE salesman_id = '$sid' AND date = '$process_date'";
            $att_res = $conn->query($check_attendance);
            $att_row = $att_res->fetch_assoc();
            $has_entry = ($att_res->num_rows > 0);
            $current_status = $has_entry ? $att_row['status'] : '';
            // B. Check Approved Leave
            $check_leave = "SELECT id FROM leave_requests 
                            WHERE salesman_id = '$sid' 
                            AND leave_date = '$process_date' 
                            AND status = 'Approved'"; 
            $leave_res = $conn->query($check_leave);
            $has_approved_leave = ($leave_res->num_rows > 0);
            // LOGIC 1: LEAVE SYNC (NEW) -> If Leave Approved, Ensure Attendance says "On Leave"
            if ($has_approved_leave) {
                $safe_showroom = $conn->real_escape_string($showroom);
                $safe_name = $conn->real_escape_string($sname);
                if (!$has_entry) {
                    $insert_sql = "INSERT INTO attendance (salesman_id, salesman_name, showroom_name, date, status, is_late, clock_in_time) 
                                   VALUES ('$sid', '$safe_name', '$safe_showroom', '$process_date', 'On Leave', 0, NULL)";
                    if ($conn->query($insert_sql) === TRUE) { $leave_synced++; }
                } 
                elseif ($current_status == 'Absent') {
                     // If currently marked Absent, but Leave is Approved, update to 'On Leave'
                     $del_sql = "UPDATE attendance SET status = 'On Leave' WHERE id = " . $att_row['id'];
                     if ($conn->query($del_sql) === TRUE) { $leave_synced++; }
                }
            }
            // LOGIC 2: CONFLICT FIX (Preserved: If Absent & Approved Leave -> Conflict Fixed above or here)
            elseif ($current_status == 'Absent' && $has_approved_leave) {
                // This block is now technically unreachable because of LOGIC 1, which updates it to On Leave
                // But we keep your logic for safety
                $del_sql = "DELETE FROM attendance WHERE id = " . $att_row['id'];
                if ($conn->query($del_sql) === TRUE) { $cleaned_count++; }
            }
            // LOGIC 3: MARK ABSENT (Preserved)
            elseif (!$has_entry && !$has_approved_leave) {
                $safe_showroom = $conn->real_escape_string($showroom);
                $safe_name = $conn->real_escape_string($sname);
                
                $insert_sql = "INSERT INTO attendance (salesman_id, salesman_name, showroom_name, date, status, is_late, clock_in_time) 
                               VALUES ('$sid', '$safe_name', '$safe_showroom', '$process_date', 'Absent', 0, NULL)";
                               
                if ($conn->query($insert_sql) === TRUE) {
                    $absent_count++;
                    $marked_ids[] = ["id" => $sid, "name" => $sname, "date" => $process_date];
                }
            }
        }
    }
}
echo json_encode([
    "status" => "success", 
    "message" => "Sync Completed.",
    "marked_absent" => $absent_count,
    "has_leave_synced" => $leave_synced,
    "cleaned_conflicts" => $cleaned_count,
    "skipped_new_joinees" => $skipped_new_joinee_count
]);
$conn->close();
?>
<?php
// slfm_api/billing_counter/mark_attendance.php
error_reporting(E_ALL);
ini_set('display_errors', 0);
header("Content-Type: application/json");
date_default_timezone_set('Asia/Kolkata');
require '../db_connect.php'; 
$salesman_id = $_POST['salesman_id'] ?? '';
$action = $_POST['action'] ?? ''; // 'clock_in', 'clock_out'
$selfie_url = $_POST['selfie_url'] ?? '';
$date = date('Y-m-d');
$time = date('H:i:s');
if (empty($salesman_id) || empty($action)) {
    echo json_encode(["status" => "error", "message" => "Missing parameters"]);
    exit;
}
// Check existing attendance and Fetch Salesman Details (Name, Showroom, Gender)
$sql = "SELECT s.name as s_name, s.showroom_name as s_showroom, s.gender, a.* 
        FROM salesmen s 
        LEFT JOIN attendance a ON s.salesman_id = a.salesman_id AND a.date = '$date'
        WHERE s.salesman_id = '$salesman_id'";
$result = $conn->query($sql);
$row = $result->fetch_assoc();
if (!$row) {
    echo json_encode(["status" => "error", "message" => "Salesman not found or inactive"]);
    exit;
}
$s_name = $conn->real_escape_string($row['s_name']);
$s_showroom = $conn->real_escape_string($row['s_showroom']);
$gender = $row['gender'] ?? 'Male';
if ($action == 'clock_in') {
    // Check if "Auto-Absent" record exists (Status=Absent but ClockIn is NULL/Empty)
    $is_auto_absent = (!empty($row['id']) && $row['status'] == 'Absent' && empty($row['clock_in_time']));
    if (empty($row['id']) || $is_auto_absent) {
        // --- NEW ENTRY (Or Override Absent) ---
        $is_late = 0;
        $in_time = strtotime($time); 
        $t930 = strtotime("09:30:00");
        $t1000 = strtotime("10:00:00");
        $t1500 = strtotime("15:00:00");
        $initial_status = 'Present';
        if ($in_time > $t930 && $in_time <= $t1000) {
            $is_late = 1; // Late
        } elseif ($in_time > $t1000 && $in_time <= $t1500) {
            $initial_status = 'Half Day'; // Entry after 10 AM is Half Day
        } elseif ($in_time > $t1500) {
            $initial_status = 'Absent'; // Entry after 3 PM is Leave
        }
        if ($is_auto_absent) {
            // UPDATE existing Auto-Absent record
            $stmt = $conn->prepare("UPDATE attendance SET clock_in_time=?, selfie_url=?, is_late=?, status=? WHERE id=?");
            $stmt->bind_param("ssisi", $time, $selfie_url, $is_late, $initial_status, $row['id']);
             if ($stmt->execute()) {
                echo json_encode(["status" => "success", "message" => "Clocked In (Absent Overridden)"]);
            } else { echo json_encode(["status" => "error", "message" => "DB Error"]); }
        } else {
            // INSERT New Record (With Name & Showroom)
            $stmt = $conn->prepare("INSERT INTO attendance (salesman_id, salesman_name, showroom_name, date, clock_in_time, selfie_url, is_late, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
            $stmt->bind_param("isssssis", $salesman_id, $s_name, $s_showroom, $date, $time, $selfie_url, $is_late, $initial_status);
             if ($stmt->execute()) {
                echo json_encode(["status" => "success", "message" => "Clocked In"]);
            } else { echo json_encode(["status" => "error", "message" => "DB Error"]); }
        }
        
    } else {
        // --- RE-ENTRY CHECK (Already has valid record) ---
        if (!empty($row['clock_out_time'])) {
            $last_out = strtotime($row['clock_out_time']);
            $now = strtotime($time);
            $diff_minutes = round(($now - $last_out) / 60);
            if ($diff_minutes <= 60) {
                // WITHIN 1 HOUR -> RESUME DUTY (Wipe clock_out)
                $update = "UPDATE attendance SET clock_out_time = NULL, status = 'Present' WHERE id = " . $row['id'];
                if ($conn->query($update)) {
                    echo json_encode(["status" => "success", "message" => "Resumed Duty (Re-entry within 1 hr)"]);
                }
            } else {
                // AFTER 1 HOUR -> PENALTY (Absent/Leave)
                $update = "UPDATE attendance SET status = 'Absent' WHERE id = " . $row['id']; 
                if ($conn->query($update)) {
                     echo json_encode(["status" => "error", "message" => "Re-entry timeout! Marked as Leave."]);
                }
            }
        } else {
            echo json_encode(["status" => "error", "message" => "Already clocked in."]);
        }
    }
} elseif ($action == 'clock_out') {
    if (!empty($row['id']) && empty($row['clock_out_time'])) {
        // --- CLOCK OUT VALIDATION ---
        $out_timestamp = strtotime($time);
        $t1430 = strtotime("14:30:00"); // 2:30 PM
        $t1500 = strtotime("15:00:00"); // 3:00 PM
        
        $final_status = 'Present';
        // Check 1: LEFT EARLY (Before 2:30 PM)
        if ($out_timestamp < $t1430) {
            $final_status = 'Absent'; // Leave
        }
        // Check 2: HALF DAY WINDOW (2:30 - 3:00 PM)
        elseif ($out_timestamp >= $t1430 && $out_timestamp <= $t1500) {
            $final_status = 'Half Day';
        }
        
        // Preserve 'Absent' if they entered late (after 3 PM) or 'Leave'
        if ($row['status'] == 'Absent' || $row['status'] == 'Leave') {
            $final_status = 'Absent';
        }
        $stmt = $conn->prepare("UPDATE attendance SET clock_out_time = ?, status = ? WHERE id = ?");
        $stmt->bind_param("ssi", $time, $final_status, $row['id']);
        
        if ($stmt->execute()) {
             echo json_encode(["status" => "success", "message" => "Clocked Out ($final_status)"]);
        }
    } else {
        echo json_encode(["status" => "error", "message" => "Not clocked in or already out."]);
    }
}
$conn->close();
?>
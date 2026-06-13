<?php
/**
 * BATCH Status Check — Returns today's status for ALL salesmen in ONE query.
 * Called once when scanner starts. No per-user calls needed during scanning.
 */
header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");
date_default_timezone_set('Asia/Kolkata');

require_once 'db_connect.php';

$date = date('Y-m-d');
$now = time();
$current_time = date('H:i:s');

$sql = "SELECT salesman_id, clock_in_time, clock_out_time, resume_count, status FROM attendance WHERE date = '$date'";
$result = $conn->query($sql);

$statuses = [];

if ($result && $result->num_rows > 0) {
    while ($row = $result->fetch_assoc()) {
        $sid = $row['salesman_id'];
        $can_clock_in = true;
        $block_reason = null;

        if (!empty($row['clock_in_time']) && empty($row['clock_out_time'])) {
            $can_clock_in = false;
            $block_reason = 'already_clocked_in';
        } elseif (!empty($row['clock_out_time'])) {
            $resume_count = (int) ($row['resume_count'] ?? 0);
            if ($resume_count >= 1) {
                $can_clock_in = false;
                $block_reason = 'quota_finished';
            } else {
                $out_time = strtotime($row['clock_out_time']);
                $diff_minutes = ($now - $out_time) / 60;
                if ($diff_minutes > 60) {
                    $can_clock_in = false;
                    $block_reason = 'break_exceeded';
                }
                if ($current_time > '19:30:00') {
                    $can_clock_in = false;
                    $block_reason = 'after_shift';
                }
            }
        }

        $statuses[$sid] = [
            "clock_in" => $row['clock_in_time'],
            "clock_out" => $row['clock_out_time'],
            "resume_count" => (int) ($row['resume_count'] ?? 0),
            "attendance_status" => $row['status'] ?? "Not Marked",
            "can_clock_in" => $can_clock_in,
            "block_reason" => $block_reason
        ];
    }
}

echo json_encode([
    "status" => "success",
    "data" => $statuses
]);

$conn->close();
?>

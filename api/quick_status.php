<?php
/**
 * FAST Quota & Status Check — Ultra-lightweight endpoint.
 * Returns ONLY: clock_in, clock_out, resume_count, can_clock_in for a salesman today.
 * No performance calculations, no monthly stats — just a single SELECT + quick logic.
 */
header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");
date_default_timezone_set('Asia/Kolkata');

require_once 'db_connect.php';

$json_data = json_decode(file_get_contents('php://input'), true);
$salesman_id = $json_data['salesman_id'] ?? $_GET['salesman_id'] ?? $_POST['salesman_id'] ?? '';

if (empty($salesman_id)) {
    echo json_encode(["status" => "error", "message" => "Salesman ID required"]);
    exit;
}

$date = date('Y-m-d');
$stmt = $conn->prepare("SELECT clock_in_time, clock_out_time, resume_count, status FROM attendance WHERE salesman_id = ? AND date = ? LIMIT 1");
$stmt->bind_param("ss", $salesman_id, $date);
$stmt->execute();
$result = $stmt->get_result();

$response = [
    "status" => "success",
    "clock_in" => null,
    "clock_out" => null,
    "resume_count" => 0,
    "attendance_status" => "Not Marked",
    "can_clock_in" => true,
    "block_reason" => null
];

if ($result->num_rows > 0) {
    $row = $result->fetch_assoc();
    $response['clock_in'] = $row['clock_in_time'];
    $response['clock_out'] = $row['clock_out_time'];
    $response['resume_count'] = (int) ($row['resume_count'] ?? 0);
    $response['attendance_status'] = $row['status'] ?? "Not Marked";

    // SMART PRE-CHECK: Determine if user CAN clock in again
    if (!empty($row['clock_in_time']) && empty($row['clock_out_time'])) {
        // Already clocked in, not clocked out
        $response['can_clock_in'] = false;
        $response['block_reason'] = 'already_clocked_in';
    } elseif (!empty($row['clock_out_time'])) {
        // Clocked out — check re-entry eligibility
        $resume_count = (int) ($row['resume_count'] ?? 0);

        if ($resume_count >= 1) {
            // Resume limit exceeded
            $response['can_clock_in'] = false;
            $response['block_reason'] = 'quota_finished';
        } else {
            // Check if break exceeded 1 hour
            $out_time = strtotime($row['clock_out_time']);
            $now = time();
            $diff_minutes = ($now - $out_time) / 60;

            if ($diff_minutes > 60) {
                $response['can_clock_in'] = false;
                $response['block_reason'] = 'break_exceeded';
            }

            // Check if after 7:30 PM
            if (date('H:i:s') > '19:30:00') {
                $response['can_clock_in'] = false;
                $response['block_reason'] = 'after_shift';
            }
        }
    }
}

echo json_encode($response);

$stmt->close();
$conn->close();
?>
<?php
// api/daily_cleanup.php
// This script should be run via a Cron Job every night at 23:55 (11:55 PM)

error_reporting(E_ERROR | E_PARSE);
ini_set('display_errors', 0);

date_default_timezone_set('Asia/Kolkata');

$db_path = __DIR__ . '/db_connect.php';
if (file_exists($db_path)) {
    require_once $db_path;
} else {
    echo json_encode(["status" => "error", "message" => "db_connect.php not found"]);
    exit;
}

// Helper to trigger performance update
function triggerPerformanceUpdate($sid)
{
    $protocol = isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? "https" : "http";
    $host = $_SERVER['HTTP_HOST'];
    $script_dir = dirname($_SERVER['PHP_SELF']);
    $script_dir = trim($script_dir, '/\\');
    $script_dir = str_replace('\\', '/', $script_dir);
    $base_url = "$protocol://$host/$script_dir/";

    $url = $base_url . "update_salesman_summary.php";
    $data = json_encode(['salesman_id' => $sid, 'skip_sync_signal' => true]);

    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($ch, CURLOPT_POSTFIELDS, $data);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($data)
        ]);
        curl_setopt($ch, CURLOPT_TIMEOUT_MS, 5000); // 5 seconds max
        curl_setopt($ch, CURLOPT_NOSIGNAL, 1);
        @curl_exec($ch);
        curl_close($ch);
    }
}

// 1. Find all salesmen who have missing outtime for past dates
$find_query = "SELECT DISTINCT salesman_id FROM attendance 
               WHERE date < CURRENT_DATE 
                 AND clock_in_time IS NOT NULL AND clock_in_time <> '' 
                 AND (clock_out_time IS NULL OR clock_out_time = '')";

$result = $conn->query($find_query);
$affected_salesmen = [];

if ($result && $result->num_rows > 0) {
    while ($row = $result->fetch_assoc()) {
        if (!empty($row['salesman_id'])) {
            $affected_salesmen[] = $row['salesman_id'];
        }
    }
}

// 2. Run the update query to mark them as Half Day
$update_query = "UPDATE attendance
                 SET status = 'Half Day',
                     modified_by = 'DEV',
                     modification_reason = 'M/O SO HALF DAY',
                     admin_approval = 'Approved',
                     clock_out_time = CONCAT(date, ' 14:30:00')
                 WHERE date < CURRENT_DATE
                   AND clock_in_time IS NOT NULL AND clock_in_time <> ''
                   AND (clock_out_time IS NULL OR clock_out_time = '')";

if ($conn->query($update_query)) {
    $rows_updated = $conn->affected_rows;

    // 3. Trigger performance update for each affected salesman
    foreach ($affected_salesmen as $sid) {
        triggerPerformanceUpdate($sid);
    }

    echo json_encode([
        "status" => "success",
        "message" => "Cleanup complete.",
        "rows_updated" => $rows_updated,
        "salesmen_updated" => count($affected_salesmen)
    ]);
} else {
    echo json_encode([
        "status" => "error",
        "message" => "Failed to execute update.",
        "error" => $conn->error
    ]);
}

$conn->close();
?>

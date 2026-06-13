<?php
// We must include db_connect.php FIRST because it sends its own headers (application/json)
$db_path = __DIR__ . '/db_connect.php';
if (file_exists($db_path)) {
    require_once $db_path;
} else {
    http_response_code(500);
    echo "db_connect.php not found";
    exit;
}

// Now overwrite the headers for CSV download
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST');
header('Access-Control-Allow-Headers: Content-Type');
header('Content-Type: text/csv; charset=utf-8');
header('Content-Disposition: attachment; filename=Attendance_Export_' . date("Y-m-d") . '.csv');

// Get parameters
$filter_date = isset($_GET['date']) ? $_GET['date'] : date("Y-m-d");
$showroom = isset($_GET['showroom']) ? $_GET['showroom'] : 'All';

// Create a file pointer connected to the output stream
$output = fopen('php://output', 'w');

// Output the column headings
fputcsv($output, [
    'Date', 
    'Salesman ID', 
    'Salesman Name',
    'Showroom', 
    'Current Status', 
    'Morning In Time', 
    'Morning In Photo', 
    'Break Out Time', 
    'Break Out Photo', 
    'Re-Entry Time', 
    'Re-Entry Photo', 
    'Final Out Time', 
    'Final Out Photo', 
    'Extra Break Time (Sec)',
    'Late Entry',
    'Out of Location'
]);

// Build query
$sql = "SELECT a.*, s.name as salesman_name 
        FROM attendance a
        LEFT JOIN salesmen s ON a.salesman_id = s.salesman_id
        WHERE a.date = '$filter_date'";

if ($showroom !== 'All' && !empty($showroom)) {
    $showroom_safe = $conn->real_escape_string($showroom);
    $sql .= " AND a.showroom_name = '$showroom_safe'";
}

$sql .= " ORDER BY a.clock_in_time ASC";

$result = $conn->query($sql);

if ($result && $result->num_rows > 0) {
    while ($row = $result->fetch_assoc()) {
        fputcsv($output, [
            $row['date'],
            $row['salesman_id'],
            $row['salesman_name'] ?? 'Unknown',
            $row['showroom_name'],
            $row['status'],
            $row['clock_in_time'],
            $row['selfie_url'] ? "https://skyblue-raven-196549.hostingersite.com/" . $row['selfie_url'] : "",
            $row['break_out_time'] ?? '',
            $row['clock_out_selfie_url'] ? "https://skyblue-raven-196549.hostingersite.com/" . $row['clock_out_selfie_url'] : "",
            $row['re_entry_time'] ?? '',
            $row['reentry_selfie_url'] ? "https://skyblue-raven-196549.hostingersite.com/" . $row['reentry_selfie_url'] : "",
            $row['clock_out_time'] ?? '',
            $row['final_out_selfie_url'] ? "https://skyblue-raven-196549.hostingersite.com/" . $row['final_out_selfie_url'] : "",
            $row['extra_break_time'] ?? '0',
            $row['is_late'] == 1 ? 'Yes' : 'No',
            $row['is_out_of_location'] == 1 ? 'Yes' : 'No'
        ]);
    }
}

fclose($output);
$conn->close();
?>

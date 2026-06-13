<?php
// slfm_api/billing_counter/get_late_arrivals_excel.php
// PURPOSE: Generates a CSV list of employees who arrived late between 09:30 AM and 10:00 AM.
// COLUMNS: Date, Salesman ID, Name, Showroom, In Time

error_reporting(E_ERROR | E_PARSE);
ini_set('display_errors', 0);

header("Content-Type: text/csv");
header("Content-Disposition: attachment; filename=late_arrivals_report.csv");
header("Access-Control-Allow-Origin: *");
date_default_timezone_set('Asia/Kolkata');

// 🔌 DB CONNECT
$db_path_current = __DIR__ . '/db_connect.php';
$db_path_parent = __DIR__ . '/../db_connect.php';

if (file_exists($db_path_current)) {
    require_once $db_path_current;
} elseif (file_exists($db_path_parent)) {
    require_once $db_path_parent;
} else {
    echo "Error: db_connect.php not found";
    exit;
}

$start_date = $_POST['start_date'] ?? $_GET['start_date'] ?? date('Y-m-d');
$end_date   = $_POST['end_date']   ?? $_GET['end_date']   ?? date('Y-m-d');
$showroom   = $_POST['showroom']   ?? $_GET['showroom']   ?? 'All';

// Construct SQL query
// Note: We check specifically for clock_in_time between 09:30 and 10:00
$sql = "SELECT a.date, a.salesman_id, s.name, a.showroom_name, a.clock_in_time 
        FROM attendance a
        JOIN salesmen s ON a.salesman_id = s.salesman_id
        WHERE a.date BETWEEN '$start_date' AND '$end_date'
        AND a.clock_in_time BETWEEN '09:30:00' AND '10:00:59'";

if ($showroom !== 'All') {
    $showroom_safe = $conn->real_escape_string($showroom);
    $sql .= " AND a.showroom_name = '$showroom_safe'";
}

$sql .= " ORDER BY a.date DESC, a.clock_in_time ASC";

$result = $conn->query($sql);

// Open output stream for CSV
$output = fopen('php://output', 'w');

// Write Headers
fputcsv($output, ['Date', 'Salesman ID', 'Name', 'Showroom', 'Clock-In Time']);

if ($result && $result->num_rows > 0) {
    while ($row = $result->fetch_assoc()) {
        fputcsv($output, [
            $row['date'],
            $row['salesman_id'],
            $row['name'],
            $row['showroom_name'],
            $row['clock_in_time']
        ]);
    }
} else {
    fputcsv($output, ['No late arrivals found for the given criteria (09:30 AM - 10:00 AM).']);
}

fclose($output);
$conn->close();
?>

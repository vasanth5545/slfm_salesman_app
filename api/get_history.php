<?php
header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");

// 1. DB Connect
require_once 'db_connect.php';

// 2. Get Inputs
$date = $_GET['date'] ?? date('Y-m-d');
$showroom = $_GET['showroom'] ?? '';
$search = $_GET['search'] ?? '';

// 3. Build Query
$where_clauses = ["a.date = ?"];
$params = [$date];
$types = "s";

if (!empty($showroom)) {
    $where_clauses[] = "s.showroom_name = ?";
    $params[] = $showroom;
    $types .= "s";
}

if (!empty($search)) {
    $where_clauses[] = "(s.name LIKE ? OR s.salesman_id LIKE ?)";
    $search_param = "%$search%";
    $params[] = $search_param;
    $params[] = $search_param;
    $types .= "ss";
}

$where_sql = implode(" AND ", $where_clauses);

$sql = "SELECT a.*, s.name as salesman_name, s.showroom_name 
        FROM attendance a 
        LEFT JOIN salesmen s ON a.salesman_id = s.salesman_id 
        WHERE $where_sql 
        ORDER BY a.clock_in_time DESC";

$stmt = $conn->prepare($sql);
$stmt->bind_param($types, ...$params);
$stmt->execute();
$result = $stmt->get_result();

$records = [];
while ($row = $result->fetch_assoc()) {
    $records[] = [
        "salesman_id" => $row['salesman_id'],
        "salesman_name" => $row['salesman_name'],
        "showroom" => $row['showroom_name'],
        "date" => $row['date'],
        "clockIn" => $row['clock_in_time'] ? date('h:i A', strtotime($row['clock_in_time'])) : '--:--',
        "clockOut" => $row['clock_out_time'] ? date('h:i A', strtotime($row['clock_out_time'])) : '--:--',
        "status" => (isset($row['modification_reason']) && strpos($row['modification_reason'], 'M/O SO HALF DAY') !== false) ? "M/O SO HALF DAY" : $row['status'],
        "is_late" => (bool) $row['is_late'],
        "location" => $row['location_name'] ?? 'Showroom'
    ];
}

// 4. Return Data
echo json_encode([
    "success" => true,
    "status" => "success",
    "data" => $records,
    "date" => $date,
    "total" => count($records)
]);

$stmt->close();
$conn->close();
?>
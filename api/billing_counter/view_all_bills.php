<?php
// billing_counter/view_all_bills.php
// Fetches all bills for the admin/billing view with filters

header("Content-Type: application/json");
require '../db_connect.php';

$status_filter = isset($_POST['status']) ? $conn->real_escape_string($_POST['status']) : ''; // 'Pending', 'Printed', etc.
$date_filter = isset($_POST['date']) ? $conn->real_escape_string($_POST['date']) : ''; // 'YYYY-MM-DD'

$sql = "SELECT b.*, s.name as salesman_name 
        FROM bills b 
        LEFT JOIN salesmen s ON b.salesman_id = s.salesman_id 
        WHERE 1=1";

if (!empty($status_filter) && $status_filter != 'All') {
    $sql .= " AND b.status = '$status_filter'";
}

if (!empty($date_filter)) {
    $sql .= " AND DATE(b.created_at) = '$date_filter'";
}

$sql .= " ORDER BY b.created_at DESC";

$result = $conn->query($sql);
$bills = [];

if ($result) {
    while($row = $result->fetch_assoc()) {
        $bills[] = $row;
    }
}

echo json_encode(["status" => "success", "data" => $bills]);

$conn->close();
?>
<?php
// billing_counter/update_bill_status.php
// Updates the status of a specific bill (e.g., Pending -> Printed)

header("Content-Type: application/json");
require '../db_connect.php';

$order_id = isset($_POST['order_id']) ? $conn->real_escape_string($_POST['order_id']) : '';
$new_status = isset($_POST['status']) ? $conn->real_escape_string($_POST['status']) : ''; // 'Printed', 'Cancelled'

if (empty($order_id) || empty($new_status)) {
    echo json_encode(["status" => "error", "message" => "Order ID and Status are required"]);
    exit;
}

$sql = "UPDATE bills SET status = '$new_status' WHERE order_id = '$order_id'";

if ($conn->query($sql) === TRUE) {
    // Optional: If cancelled, you might want to restock items here logic-wise
    
    echo json_encode(["status" => "success", "message" => "Bill updated successfully"]);
} else {
    echo json_encode(["status" => "error", "message" => "Database error: " . $conn->error]);
}

$conn->close();
?>
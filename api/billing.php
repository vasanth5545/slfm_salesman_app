<?php
// billing.php
// Handles order creation and retrieving bill history

header("Content-Type: application/json");
require 'db_connect.php';

$action = isset($_POST['action']) ? $_POST['action'] : ''; // 'create_order', 'get_bills'

if ($action == 'create_order') {
    $salesman_id = isset($_POST['salesman_id']) ? $conn->real_escape_string($_POST['salesman_id']) : '';
    $customer_name = isset($_POST['customer_name']) ? $conn->real_escape_string($_POST['customer_name']) : '';
    $customer_phone = isset($_POST['customer_phone']) ? $conn->real_escape_string($_POST['customer_phone']) : '';
    $customer_address = isset($_POST['customer_address']) ? $conn->real_escape_string($_POST['customer_address']) : '';
    $product_os_code = isset($_POST['product_os_code']) ? $conn->real_escape_string($_POST['product_os_code']) : '';
    $final_price = isset($_POST['final_price']) ? $_POST['final_price'] : 0;

    // Generate unique Order ID (e.g., ORD + timestamp)
    $order_id = 'ORD' . round(microtime(true) * 1000);

    // Simple validation
    if (empty($salesman_id) || empty($customer_name) || empty($product_os_code)) {
        echo json_encode(["status" => "error", "message" => "Missing required fields"]);
        exit;
    }

    // Insert new bill
    $sql = "INSERT INTO bills (order_id, salesman_id, customer_name, customer_phone, customer_address, product_os_code, final_price, status) 
            VALUES ('$order_id', '$salesman_id', '$customer_name', '$customer_phone', '$customer_address', '$product_os_code', '$final_price', 'Pending')";

    if ($conn->query($sql) === TRUE) {
        echo json_encode([
            "status" => "success", 
            "message" => "Order created successfully",
            "data" => ["order_id" => $order_id]
        ]);
    } else {
        echo json_encode(["status" => "error", "message" => "Database error: " . $conn->error]);
    }

} elseif ($action == 'get_bills') {
    $salesman_id = isset($_POST['salesman_id']) ? $conn->real_escape_string($_POST['salesman_id']) : '';
    
    // Fetch bills for this salesman, newest first
    $sql = "SELECT b.*, p.name as product_name 
            FROM bills b 
            LEFT JOIN products p ON b.product_os_code = p.os_code 
            WHERE b.salesman_id = '$salesman_id' 
            ORDER BY b.created_at DESC";
            
    $result = $conn->query($sql);
    
    $bills = [];
    if ($result) {
        while($row = $result->fetch_assoc()) {
            $bills[] = $row;
        }
    }
    
    echo json_encode(["status" => "success", "data" => $bills]);

} else {
    echo json_encode(["status" => "error", "message" => "Invalid action"]);
}

$conn->close();
?>
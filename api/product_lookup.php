<?php
// product_lookup.php
// Search product details by OS Code and log the history

header("Content-Type: application/json");
require 'db_connect.php';

$os_code = isset($_POST['os_code']) ? $conn->real_escape_string($_POST['os_code']) : '';
$salesman_id = isset($_POST['salesman_id']) ? $conn->real_escape_string($_POST['salesman_id']) : '';

if (empty($os_code)) {
    echo json_encode(["status" => "error", "message" => "OS Code is required"]);
    exit;
}

// 1. Fetch product details
$sql = "SELECT * FROM products WHERE os_code = '$os_code'";
$result = $conn->query($sql);

if ($result && $result->num_rows > 0) {
    $product = $result->fetch_assoc();

    // 2. Log this lookup in history (only if found)
    if (!empty($salesman_id)) {
        $log_sql = "INSERT INTO lookup_history (salesman_id, product_os_code) VALUES ('$salesman_id', '$os_code')";
        $conn->query($log_sql);
    }

    echo json_encode([
        "status" => "success",
        "data" => $product
    ]);
} else {
    echo json_encode([
        "status" => "error",
        "message" => "Product not found for code: " . $os_code
    ]);
}

$conn->close();
?>
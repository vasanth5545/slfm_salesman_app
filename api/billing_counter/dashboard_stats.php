<?php
// billing_counter/dashboard_stats.php
// Aggregates statistics including Walking Customers for Billing App Dashboard

header("Content-Type: application/json");
require '../db_connect.php';

$response = [];

// 1. Pending Bills Count (Orders ready for billing)
$pending_res = $conn->query("SELECT COUNT(*) as count FROM bills WHERE status = 'Pending'");
$response['pending_bills'] = $pending_res ? $pending_res->fetch_assoc()['count'] : 0;

// 2. Printed Bills (Today)
$today = date('Y-m-d');
$printed_res = $conn->query("SELECT COUNT(*) as count FROM bills WHERE status = 'Printed' AND DATE(created_at) = '$today'");
$response['printed_today'] = $printed_res ? $printed_res->fetch_assoc()['count'] : 0;

// 3. Total Sales Value (Today)
$sales_res = $conn->query("SELECT SUM(final_price) as total FROM bills WHERE status = 'Printed' AND DATE(created_at) = '$today'");
$sales_row = $sales_res ? $sales_res->fetch_assoc() : null;
$response['total_sales_today'] = $sales_row['total'] ?? 0;

// 4. Active Staff Count
$staff_res = $conn->query("SELECT COUNT(*) as count FROM salesmen WHERE status = 'Active'");
$response['active_staff'] = $staff_res ? $staff_res->fetch_assoc()['count'] : 0;

// --- 🔥 WALKING CUSTOMER STATS (NEW) ---

// 5. Total Pending Walking Customers (Anyone waiting for followup)
$walk_pending_res = $conn->query("SELECT COUNT(*) as count FROM walking_customers WHERE status = 'Pending'");
$response['walking_pending'] = $walk_pending_res ? $walk_pending_res->fetch_assoc()['count'] : 0;

// 6. Walking Customers Billed TODAY (Finished Today)
$walk_billed_res = $conn->query("SELECT COUNT(*) as count FROM walking_customers WHERE status = 'Billed' AND DATE(billed_at) = '$today'");
$response['walking_billed_today'] = $walk_billed_res ? $walk_billed_res->fetch_assoc()['count'] : 0;

echo json_encode(["status" => "success", "data" => $response]);

$conn->close();
?>
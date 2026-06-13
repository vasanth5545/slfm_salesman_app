<?php
// slfm_api/billing_counter/admin_leave.php

error_reporting(E_ALL);
ini_set('display_errors', 0); // Hide errors from output, only JSON

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST");
header("Access-Control-Allow-Headers: Content-Type");

date_default_timezone_set('Asia/Kolkata');

// 2. DB Connection (Robust)
// Tries current dir first, then parent dir
$db_found = false;
$possible_paths = [
    __DIR__ . '/db_connect.php',     
    __DIR__ . '/../db_connect.php' 
];
foreach ($possible_paths as $path) {
    if (file_exists($path)) {
        require $path;
        $db_found = true;
        break;
    }
}

if (!$db_found) {
    echo json_encode(["status" => "error", "message" => "db_connect.php not found"]);
    exit;
}

$json_data = json_decode(file_get_contents('php://input'), true);
$action = $json_data['action'] ?? $_POST['action'] ?? '';

// --- 1. GET PENDING LEAVE REQUESTS (With Showroom Name) ---
if ($action == 'get_pending_requests') {

    // DEBUG: First check total count
    $countSql = "SELECT COUNT(*) as total FROM leave_requests";
    $countRes = $conn->query($countSql);
    $totalRows = ($countRes && $row = $countRes->fetch_assoc()) ? $row['total'] : 0;

    // Use LOWER() for case-insensitive check and trim
    // JOIN with salesmen table to get name AND showroom_name
    $sql = "SELECT lr.id, lr.salesman_id, lr.leave_date, lr.leave_type, lr.reason, lr.status, lr.created_at, 
                   s.name as salesman_name, s.showroom_name
            FROM leave_requests lr
            LEFT JOIN salesmen s ON lr.salesman_id = s.salesman_id
            WHERE LOWER(TRIM(lr.status)) = 'pending'
            ORDER BY lr.created_at DESC";

    $result = $conn->query($sql);
    $requests = [];

    if ($result) {
        while ($row = $result->fetch_assoc()) {
            $requests[] = $row;
        }
        echo json_encode([
            "status" => "success", 
            "data" => $requests,
            "debug_total_rows" => $totalRows, // Helps debug if table is empty
            "debug_message" => "Found " . count($requests) . " pending requests out of $totalRows total."
        ]);
    } else {
        echo json_encode(["status" => "error", "message" => "SQL Error: " . $conn->error]);
    }
}

// --- 2. GET CANCEL REQUESTS (With Showroom Name) ---
elseif ($action == 'get_cancel_requests') {
    // JOIN with salesmen table to get showroom_name
    // JOIN with leave_requests to get leave_date and leave_type
    $sql = "SELECT lcr.id, lcr.salesman_id, lcr.salesman_name, lcr.leave_id, lcr.cancel_reason, lcr.created_at,
                   s.showroom_name,
                   lr.leave_date, lr.leave_type
            FROM leave_cancel_requests lcr
            LEFT JOIN salesmen s ON lcr.salesman_id = s.salesman_id
            LEFT JOIN leave_requests lr ON lcr.leave_id = lr.id
            ORDER BY lcr.created_at DESC";

    $result = $conn->query($sql);
    $requests = [];

    if ($result) {
        while ($row = $result->fetch_assoc()) {
            $requests[] = $row;
        }
        echo json_encode(["status" => "success", "data" => $requests]);
    } else {
        echo json_encode(["status" => "error", "message" => "SQL Error: " . $conn->error]);
    }
}

// --- 2.5 GET ALL REQUESTS (HISTORY) ---
// THIS Was Missing Previously
elseif ($action == 'get_all_requests') {
    // Fetch EVERYTHING (Pending, Approved, Rejected)
    // JOIN for salesman name, showroom name
    $sql = "SELECT lr.id, lr.salesman_id, lr.leave_date, lr.leave_type, lr.reason, lr.status, lr.created_at, 
                   s.name as salesman_name, s.showroom_name
            FROM leave_requests lr
            LEFT JOIN salesmen s ON lr.salesman_id = s.salesman_id
            ORDER BY lr.created_at DESC";

    $result = $conn->query($sql);
    $requests = [];

    if ($result) {
        while ($row = $result->fetch_assoc()) {
            $requests[] = $row;
        }
        echo json_encode(["status" => "success", "data" => $requests]);
    } else {
        echo json_encode(["status" => "error", "message" => "SQL Error: " . $conn->error]);
    }
}

// --- 3. UPDATE LEAVE STATUS (Approve/Reject Leave) ---
elseif ($action == 'update_status') {
    $leave_id = $json_data['leave_id'] ?? $_POST['leave_id'] ?? '';
    $new_status = $json_data['status'] ?? $_POST['status'] ?? ''; 

    if (empty($leave_id) || empty($new_status)) {
        echo json_encode(["status" => "error", "message" => "Missing ID or Status"]);
        exit;
    }

    $sql = "UPDATE leave_requests SET status = ? WHERE id = ?";
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("ss", $new_status, $leave_id);

    if ($stmt->execute()) {
        echo json_encode(["status" => "success", "message" => "Leave $new_status Successfully!"]);
    } else {
        echo json_encode(["status" => "error", "message" => "Update Failed: " . $stmt->error]);
    }
}

// --- 4. PROCESS CANCEL REQUEST (Approve/Reject Cancellation) ---
elseif ($action == 'process_cancel_request') {
    $cancel_id = $json_data['cancel_id'] ?? $_POST['cancel_id'] ?? '';
    // Decision is effectively always 'Approve' based on UI, but we support both
    $decision  = $json_data['decision'] ?? 'Approve'; 

    if (empty($cancel_id)) {
        echo json_encode(["status" => "error", "message" => "Missing Cancel ID"]);
        exit;
    }

    // First, find the related leave_id from the cancel request
    $findSql = "SELECT leave_id FROM leave_cancel_requests WHERE id = ?";
    $stmt = $conn->prepare($findSql);
    $stmt->bind_param("s", $cancel_id);
    $stmt->execute();
    $res = $stmt->get_result();

    if ($res->num_rows == 0) {
        echo json_encode(["status" => "error", "message" => "Cancel Request Not Found"]);
        exit;
    }

    $row = $res->fetch_assoc();
    $leave_id = $row['leave_id'];

    if ($decision == 'Approve') {
        // 1. DELETE the Leave Request entirely (As per user request)
        // Instead of marking 'Rejected', we wipe it so they can re-apply or it's gone.
        $deleteLeaveSql = "DELETE FROM leave_requests WHERE id = ?";
        $delLeaveStmt = $conn->prepare($deleteLeaveSql);
        $delLeaveStmt->bind_param("s", $leave_id);
        $delLeaveStmt->execute();

        // 2. Delete the cancel request
        $delSql = "DELETE FROM leave_cancel_requests WHERE id = ?";
        $delStmt = $conn->prepare($delSql);
        $delStmt->bind_param("s", $cancel_id);
        $delStmt->execute();

        echo json_encode(["status" => "success", "message" => "Leave Request Deleted & Cancelled Successfully"]);

    } else {
        // If Rejecting the CANCELLATION (Keeping the leave) 
        // Just delete the request, leave status remains 'Pending' or 'Approved'
        $delSql = "DELETE FROM leave_cancel_requests WHERE id = ?";
        $delStmt = $conn->prepare($delSql);
        $delStmt->bind_param("s", $cancel_id);
        $delStmt->execute();

        echo json_encode(["status" => "success", "message" => "Cancellation Request Rejected"]);
    }
}

// --- 5. GET NOTIFICATION COUNTS (For Dashboard) ---
elseif ($action == 'get_notification_counts') {
    // Count Pending Leaves
    $leaveSql = "SELECT COUNT(*) as count FROM leave_requests WHERE LOWER(TRIM(status)) = 'pending'";
    $leaveRes = $conn->query($leaveSql);
    $leaveCount = ($leaveRes && $row = $leaveRes->fetch_assoc()) ? (int)$row['count'] : 0;

    // Count Cancel Requests (All are effectively pending action until deleted/processed)
    $cancelSql = "SELECT COUNT(*) as count FROM leave_cancel_requests";
    $cancelRes = $conn->query($cancelSql);
    $cancelCount = ($cancelRes && $row = $cancelRes->fetch_assoc()) ? (int)$row['count'] : 0;

    echo json_encode([
        "status" => "success", 
        "data" => [
            "pending_leaves" => $leaveCount,
            "cancel_requests" => $cancelCount,
            "total" => $leaveCount + $cancelCount
        ]
    ]);
} else {
    echo json_encode(["status" => "error", "message" => "Invalid Action"]);
}

$conn->close();
?>

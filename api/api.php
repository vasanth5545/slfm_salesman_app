<?php
/**
 * Master API - Combines all dashboard and management functions into one file.
 * Logic: Use ?action=... to call different functions.
 */

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");
date_default_timezone_set('Asia/Kolkata');

// 1. DB Connect
require_once 'db_connect.php';

// 2. Get Input
$json_data = json_decode(file_get_contents('php://input'), true);
$action = $_GET['action'] ?? $json_data['action'] ?? $_POST['action'] ?? '';

if (empty($action)) {
    echo json_encode(["success" => false, "message" => "No action specified"]);
    exit;
}

switch ($action) {
    case 'login':
        handleLogin($conn, $json_data);
        break;
        
    case 'get_dashboard':
        handleDashboard($conn, $json_data);
        break;
        
    case 'get_reports':
        handleReports($conn, $json_data);
        break;
        
    case 'get_showrooms':
        handleGetShowrooms($conn);
        break;
        
    case 'get_users':
        handleGetUsers($conn);
        break;
        
    case 'get_staff':
        handleGetStaff($conn, $json_data);
        break;
        
    case 'sync_face':
        handleSyncFace($conn, $json_data);
        break;
        
    default:
        echo json_encode(["success" => false, "message" => "Invalid action: $action"]);
        break;
}

// --- HANDLERS ---

function handleLogin($conn, $json_data) {
    $showroom_name = $json_data['showroom_name'] ?? $_POST['showroom_name'] ?? '';
    $password = $json_data['password'] ?? $_POST['password'] ?? '';

    if (empty($showroom_name) || empty($password)) {
        echo json_encode(["success" => false, "message" => "Name and Password are required"]);
        return;
    }

    // Query billing_staff by staff_id or name
    $stmt = $conn->prepare("SELECT id, staff_id, name, showroom, role FROM billing_staff WHERE (staff_id = ? OR name = ?) AND password_hash = ?");
    $stmt->bind_param("sss", $showroom_name, $showroom_name, $password);
    $stmt->execute();
    $result = $stmt->get_result();

    if ($result->num_rows > 0) {
        $staff = $result->fetch_assoc();
        // Fallback to name if showroom is empty
        $showroomName = !empty($staff['showroom']) ? $staff['showroom'] : $staff['name'];
        echo json_encode([
            "success" => true,
            "message" => "Login successful",
            "showroom" => [
                "id" => $staff['id'],
                "name" => $showroomName,
                "staff_id" => $staff['staff_id'],
                "role" => $staff['role']
            ]
        ]);
    } else {
        echo json_encode(["success" => false, "message" => "Invalid staff ID or password"]);
    }
    $stmt->close();
}

function handleDashboard($conn, $json_data) {
    $showroom_name = $json_data['showroom_name'] ?? $_GET['showroom_name'] ?? '';
    if (empty($showroom_name)) {
        echo json_encode(["success" => false, "message" => "Showroom name is required"]);
        return;
    }

    $today = date('Y-m-d');
    
    // 1. Showroom Info
    $stmt = $conn->prepare("SELECT name, role FROM billing_staff WHERE showroom = ? OR name = ? LIMIT 1");
    $stmt->bind_param("ss", $showroom_name, $showroom_name);
    $stmt->execute();
    $staff_res = $stmt->get_result();
    
    if ($staff_res->num_rows > 0) {
        $staff = $staff_res->fetch_assoc();
        $sh_info = [
            "name" => $showroom_name,
            "manager_name" => $staff['name'],
            "contact_number" => "",
            "address" => ""
        ];
    } else {
        $sh_info = [
            "name" => $showroom_name,
            "manager_name" => "Manager",
            "contact_number" => "",
            "address" => ""
        ];
    }
    $stmt->close();

    // 2. Staff with Today's Attendance
    $staff_sql = "
        SELECT s.salesman_id, s.name, s.status as profile_status, a.clock_in_time, a.clock_out_time, 
               a.status as attendance_status, a.is_late,
               (SELECT COUNT(*) FROM attendance WHERE salesman_id = s.salesman_id AND status IN ('Present', 'Half Day') AND DATE_FORMAT(date, '%Y-%m') = DATE_FORMAT(CURRENT_DATE, '%Y-%m')) as attendance_count
        FROM salesmen s
        LEFT JOIN attendance a ON s.salesman_id = a.salesman_id AND a.date = '$today'
        WHERE s.showroom_name = ?
        ORDER BY s.name ASC";
    
    $stmt = $conn->prepare($staff_sql);
    $stmt->bind_param("s", $showroom_name);
    $stmt->execute();
    $result = $stmt->get_result();

    $staff_list = [];
    $stats = ["total" => 0, "present" => 0, "half_day" => 0, "late" => 0, "absent" => 0, "on_leave" => 0];

    while($row = $result->fetch_assoc()) {
        $stats["total"]++;
        $status = $row['attendance_status'] ?? 'Absent';
        if ($status == 'Present') $stats['present']++;
        else if ($status == 'Half Day') $stats['half_day']++;
        else if ($status == 'On Leave') $stats['on_leave']++;
        if ($row['is_late'] == 1 && $status == 'Present') $stats['late']++;
        if ($status == 'Absent') $stats['absent']++;

        $staff_list[] = [
            "salesman_id" => $row['salesman_id'],
            "name" => $row['name'],
            "clock_in" => $row['clock_in_time'] ? date('h:i A', strtotime($row['clock_in_time'])) : null,
            "clock_out" => $row['clock_out_time'] ? date('h:i A', strtotime($row['clock_out_time'])) : null,
            "status" => $status,
            "is_late" => (bool)$row['is_late'],
            "attendance" => $row['attendance_count'] ?? 0
        ];
    }
    $stmt->close();

    echo json_encode([
        "success" => true,
        "data" => ["showroom" => $sh_info, "stats" => $stats, "staff" => $staff_list, "date" => date('l, d F Y')]
    ]);
}

function handleReports($conn, $json_data) {
    $month = $_GET['month'] ?? $json_data['month'] ?? date('Y-m');
    $showroom = $_GET['showroom'] ?? $json_data['showroom'] ?? '';

    $response = [
        "success" => true,
        "summary" => ["present" => 0, "absent" => 0, "on_leave" => 0, "late" => 0],
        "today" => ["present" => 0, "absent" => 0, "on_leave" => 0, "late" => 0],
        "trend" => [],
        "staff_performance" => []
    ];

    $today_date = date('Y-m-d');
    $filter = !empty($showroom) ? " AND showroom_name = '" . $conn->real_escape_string($showroom) . "'" : "";

    // Today's stats
    $att_res = $conn->query("SELECT COUNT(IF(status IN ('Present', 'Half Day'), 1, NULL)) as present, COUNT(IF(is_late = 1, 1, NULL)) as late FROM attendance WHERE date = '$today_date' $filter");
    if ($row = $att_res->fetch_assoc()) {
        $response['today']['present'] = (int)$row['present'];
        $response['today']['late'] = (int)$row['late'];
    }

    $staff_res = $conn->query("SELECT COUNT(*) as total FROM salesmen" . (!empty($showroom) ? " WHERE showroom_name = '" . $conn->real_escape_string($showroom) . "'" : ""));
    $total_staff = ($row = $staff_res->fetch_assoc()) ? (int)$row['total'] : 0;
    $response['today']['absent'] = max(0, $total_staff - $response['today']['present']);

    // Monthly stats
    $monthly_sql = "SELECT SUM(total_present) as p, SUM(total_absent) as a, SUM(total_half_days) as h FROM salesman_monthly_performance WHERE report_month = '$month'";
    if (!empty($showroom)) {
        $monthly_sql = "SELECT SUM(p.total_present) as p, SUM(p.total_absent) as a, SUM(p.total_half_days) as h FROM salesman_monthly_performance p JOIN salesmen s ON p.salesman_id = s.salesman_id WHERE p.report_month = '$month' AND s.showroom_name = '$showroom'";
    }
    $res = $conn->query($monthly_sql);
    if ($row = $res->fetch_assoc()) {
        $response['summary']['present'] = (int)$row['p'];
        $response['summary']['absent'] = (int)$row['a'];
        $response['summary']['late'] = (int)$row['h'];
    }

    // Performance list
    $perf_sql = "SELECT s.name, s.salesman_id, p.attendance_percentage FROM salesmen s LEFT JOIN salesman_monthly_performance p ON s.salesman_id = p.salesman_id AND p.report_month = '$month' " . (!empty($showroom) ? " WHERE s.showroom_name = '$showroom'" : "") . " ORDER BY p.attendance_percentage DESC";
    $p_res = $conn->query($perf_sql);
    while ($row = $p_res->fetch_assoc()) {
        $perc = (float)($row['attendance_percentage'] ?? 0);
        $response['staff_performance'][] = [
            "name" => $row['name'], "id" => $row['salesman_id'], "attendance" => $perc . "%",
            "status" => ($perc < 75 ? "At Risk" : ($perc < 90 ? "Warning" : "On Track")),
            "trend" => ($perc >= 90 ? "up" : "down")
        ];
    }

    echo json_encode($response);
}

function handleGetShowrooms($conn) {
    $result = $conn->query("SELECT DISTINCT showroom_name FROM salesmen ORDER BY showroom_name ASC");
    $list = [];
    while($row = $result->fetch_assoc()) $list[] = $row['showroom_name'];
    echo json_encode(["success" => true, "showrooms" => $list]);
}

function handleGetStaff($conn, $json_data) {
    $showroom = $_GET['showroom'] ?? $json_data['showroom'] ?? '';
    if (empty($showroom)) {
        echo json_encode(["success" => false, "message" => "Showroom name is required"]);
        return;
    }
    $stmt = $conn->prepare("SELECT salesman_id, name, (face_id IS NOT NULL) as is_registered FROM salesmen WHERE showroom_name = ? ORDER BY name ASC");
    $stmt->bind_param("s", $showroom);
    $stmt->execute();
    $res = $stmt->get_result();
    $list = [];
    while($row = $res->fetch_assoc()) $list[] = $row;
    echo json_encode(["success" => true, "staff" => $list]);
    $stmt->close();
}

function handleSyncFace($conn, $json_data) {
    $salesman_id = $_POST['salesman_id'] ?? $json_data['salesman_id'] ?? '';
    $face_id = $_POST['face_id'] ?? $json_data['face_id'] ?? $_POST['face_embedding'] ?? $json_data['face_embedding'] ?? '';
    if (empty($salesman_id) || empty($face_id)) {
        echo json_encode(["success" => false, "message" => "Salesman ID and embedding are required"]);
        return;
    }
    $embedding_json = is_string($face_id) ? $face_id : json_encode($face_id);
    $stmt = $conn->prepare("UPDATE salesmen SET face_id = ? WHERE salesman_id = ?");
    $stmt->bind_param("ss", $embedding_json, $salesman_id);
    if ($stmt->execute()) echo json_encode(["success" => true, "message" => "Face registered successfully"]);
    else echo json_encode(["success" => false, "message" => "Database update failed"]);
    $stmt->close();
}

function handleGetUsers($conn) {
    $sql = "SELECT salesman_id, name, showroom_name, face_id FROM salesmen WHERE face_id IS NOT NULL";
    $result = $conn->query($sql);
    $users = [];
    while ($row = $result->fetch_assoc()) {
        // Removed ID length restriction to ensure all valid staff are synced
        // if (strlen($id) >= 13 && is_numeric($id)) continue;
        $row['face_id'] = json_decode($row['face_id']);
        $users[] = $row;
    }
    echo json_encode(["success" => true, "users" => $users]);
}

$conn->close();
?>

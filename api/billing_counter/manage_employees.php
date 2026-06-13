<?php
// billing_counter/manage_employees.php
// Handles CRUD operations for employees (salesmen)

header("Content-Type: application/json");
require '../db_connect.php'; // Reuse shared connection

$action = isset($_POST['action']) ? $_POST['action'] : ''; // 'add', 'update', 'list', 'create_table'

// NEW: Action to create the table directly via API if needed, or just for reference
if ($action == 'create_table') {
    $sql = "CREATE TABLE IF NOT EXISTS salesmen (
        id INT AUTO_INCREMENT PRIMARY KEY,
        salesman_id VARCHAR(20) NOT NULL UNIQUE, -- e.g., SM001
        name VARCHAR(100) NOT NULL,
        password_hash VARCHAR(255) NOT NULL, -- In a real app, use password hashing
        status ENUM('Active', 'Suspended') DEFAULT 'Active',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )";

    if ($conn->query($sql) === TRUE) {
        echo json_encode(["status" => "success", "message" => "Table 'salesmen' created successfully"]);
    } else {
        echo json_encode(["status" => "error", "message" => "Error creating table: " . $conn->error]);
    }
    $conn->close();
    exit();
}

if ($action == 'add') {
    $salesman_id = isset($_POST['salesman_id']) ? $conn->real_escape_string($_POST['salesman_id']) : '';
    $name = isset($_POST['name']) ? $conn->real_escape_string($_POST['name']) : '';
    $password = isset($_POST['password']) ? $_POST['password'] : ''; // Hash this in production
    
    if (empty($salesman_id) || empty($name)) {
        echo json_encode(["status" => "error", "message" => "ID and Name are required"]);
        exit;
    }

    // Check if ID exists
    $check_sql = "SELECT id FROM salesmen WHERE salesman_id = '$salesman_id'";
    if ($conn->query($check_sql)->num_rows > 0) {
        echo json_encode(["status" => "error", "message" => "Salesman ID already exists"]);
    } else {
        $sql = "INSERT INTO salesmen (salesman_id, name, password_hash, status) 
                VALUES ('$salesman_id', '$name', '$password', 'Active')";
        
        if ($conn->query($sql) === TRUE) {
            echo json_encode(["status" => "success", "message" => "Employee added successfully"]);
        } else {
            echo json_encode(["status" => "error", "message" => "Database error: " . $conn->error]);
        }
    }

} elseif ($action == 'update') {
    $salesman_id = isset($_POST['salesman_id']) ? trim($conn->real_escape_string($_POST['salesman_id'])) : '';
    $status_input = isset($_POST['status']) ? trim($_POST['status']) : '';
    
    // Normalize status: Always store as 'Active' or 'Suspended'
    $status = ucfirst(strtolower($status_input));

    if (empty($salesman_id)) {
        echo json_encode(["status" => "error", "message" => "Salesman ID is required"]);
        exit;
    }

    // 1. UPDATE MYSQL with relieving_date
    // Use CASE-INSENSITIVE check by using normalized $status
    if ($status === 'Suspended') {
        $relieving_date = date('Y-m-d');
        $sql = "UPDATE salesmen SET status = '$status', relieving_date = '$relieving_date' WHERE salesman_id = '$salesman_id'";
    } else {
        $sql = "UPDATE salesmen SET status = '$status', relieving_date = NULL WHERE salesman_id = '$salesman_id'";
    }
    
    if ($conn->query($sql) === TRUE) {
        
        // 2. TRIGGER FIREBASE RTDB FOR REAL-TIME LOGOUT
        $FIREBASE_RTDB_URL = "https://admin-decd9-default-rtdb.asia-southeast1.firebasedatabase.app";
        $FIREBASE_DB_SECRET = "y9O4hN0n1Od4HuPf8co9uaRT2t750HUOYnhTaJJ3";
        
        $rtdb_path = "/salesmen_status/" . urlencode(stripslashes($salesman_id)) . ".json";
        $rtdb_full_url = $FIREBASE_RTDB_URL . $rtdb_path . "?auth=" . $FIREBASE_DB_SECRET;
        
        // Data to write (Using normalized $status)
        $rtdb_data = json_encode([
            "status" => $status,
            "updated_at" => round(microtime(true) * 1000),
            "updated_by" => "admin_panel"
        ]);
        
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $rtdb_full_url);
        curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "PATCH");
        curl_setopt($ch, CURLOPT_POSTFIELDS, $rtdb_data);
        curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 5);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        
        $response = curl_exec($ch);
        $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($http_code == 200) {
            echo json_encode([
                "status" => "success", 
                "message" => "Employee status updated to $status, Firebase signaled successfully",
                "relieving_date" => ($status === 'Suspended' ? date('Y-m-d') : 'Cleared')
            ]);
        } else {
            echo json_encode([
                "status" => "warning", 
                "message" => "Database updated to $status, but Firebase signal failed (HTTP $http_code). Check your internet or Firebase secret.",
                "firebase_response" => $response
            ]);
        }
    } else {
        echo json_encode(["status" => "error", "message" => "Database error: " . $conn->error]);
    }

} elseif ($action == 'list') {
    $sql = "SELECT id, salesman_id, name, status, created_at FROM salesmen ORDER BY name ASC";
    $result = $conn->query($sql);
    
    $employees = [];
    if ($result) {
        while($row = $result->fetch_assoc()) {
            $employees[] = $row;
        }
    }
    echo json_encode(["status" => "success", "data" => $employees]);

} else {
    echo json_encode(["status" => "error", "message" => "Invalid action"]);
}

$conn->close();
?>
<?php
// slfm_backend_scripts/add_salesman.php
// PURPOSE: Adds a new salesman to the database.

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST");
header("Access-Control-Allow-Headers: Content-Type");

require_once __DIR__ . '/db_connect.php';

// JSON Input
$json_data = json_decode(file_get_contents('php://input'), true);

// 🎰 RANDOM ID GENERATION (SM + 3 Digits)
function generateUniqueId($conn) {
    do {
        $rand = rand(100, 999);
        $new_id = "SM" . $rand;
        $check = $conn->query("SELECT id FROM salesmen WHERE salesman_id = '$new_id'");
    } while ($check->num_rows > 0); 
    return $new_id;
}

// --- LOGIC: SINGLE VS BULK ---

// CASE 1: BULK ADD (If "users" array is present)
if (isset($json_data['users']) && is_array($json_data['users'])) {
    
    $results = [];
    $success_count = 0;
    
    foreach ($json_data['users'] as $user) {
        $name = $user['name'] ?? null;
        $password = $user['password'] ?? 'slfm2026'; // Default Updated
        $showroom = $user['showroom_name'] ?? 'Main Branch';
        $address = $user['showroom_address'] ?? 'Mannargudi'; // New Field
        $gender = $user['gender'] ?? 'Male';
        $phone = $user['phone'] ?? '';

        if (!$name) {
            $results[] = ["name" => "Unknown", "status" => "error", "message" => "Name missing"];
            continue;
        }

        $salesman_id = generateUniqueId($conn);

        // Determine Shift End Time based on Gender
        $shift_end = (strtolower($gender) == 'female') ? '20:00:00' : '21:00:00';

        $sql = "INSERT INTO salesmen (salesman_id, name, phone, password_hash, showroom_name, showroom_address, gender, status, allow_late_entry, shift_end_time) 
                VALUES ('$salesman_id', '$name', '$phone', '$password', '$showroom', '$address', '$gender', 'Active', 0, '$shift_end')";

        if ($conn->query($sql) === TRUE) {
            $success_count++;
            $results[] = ["name" => $name, "salesman_id" => $salesman_id, "status" => "success"];
        } else {
            $results[] = ["name" => $name, "status" => "error", "message" => $conn->error];
        }
    }
    
    echo json_encode([
        "status" => "completed",
        "mode" => "bulk",
        "total_added" => $success_count,
        "details" => $results
    ]);

} 
// CASE 2: SINGLE ADD (Legacy / Simple)
else {
    $name = $json_data['name'] ?? null;
    $phone = $json_data['phone'] ?? null;
    $password = $json_data['password'] ?? null; 
    $showroom = $json_data['showroom_name'] ?? 'Main Branch';
    $address = $json_data['showroom_address'] ?? 'Mannargudi'; // New Field
    $gender = $json_data['gender'] ?? 'Male';

    if (!$name || !$password) {
        echo json_encode(["status" => "error", "message" => "Name and Password required"]);
        exit;
    }

    $salesman_id = generateUniqueId($conn);

    // Determine Shift End Time based on Gender
    $shift_end = (strtolower($gender) == 'female') ? '20:00:00' : '21:00:00';

    $sql = "INSERT INTO salesmen (salesman_id, name, phone, password_hash, showroom_name, showroom_address, gender, status, allow_late_entry, shift_end_time) 
            VALUES ('$salesman_id', '$name', '$phone', '$password', '$showroom', '$address', '$gender', 'Active', 0, '$shift_end')";

    if ($conn->query($sql) === TRUE) {
        echo json_encode([
            "status" => "success", 
            "mode" => "single",
            "message" => "Salesman Created Successfully",
            "data" => [
                "salesman_id" => $salesman_id,
                "name" => $name,
                "showroom" => $showroom
            ]
        ]);
    } else {
        echo json_encode(["status" => "error", "message" => "DB Error: " . $conn->error]);
    }
}

$conn->close();
?>

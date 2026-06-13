<?php
// get_service_reports.php
// get_service_reports.php
error_reporting(0);
ini_set('display_errors', 0);

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: POST");
header("Access-Control-Allow-Headers: Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With");

require_once 'db_connect.php';
// Re-ensure errors are hidden after including db_connect
error_reporting(0);
ini_set('display_errors', 0);

date_default_timezone_set('Asia/Kolkata');

$data = json_decode(file_get_contents("php://input"));

if (!empty($data->showroom_name)) {
    $showroom_name = $conn->real_escape_string($data->showroom_name);

    $sql = "SELECT * FROM service_reports WHERE showroom_name = '$showroom_name' ORDER BY created_at DESC";
    
    // Optionally filter by date or status if provided
    if (!empty($data->date)) {
        $date = $conn->real_escape_string($data->date);
        $sql = "SELECT * FROM service_reports WHERE showroom_name = '$showroom_name' AND DATE(created_at) = '$date' ORDER BY created_at DESC";
    }

    $result = $conn->query($sql);
    $reports = array();

    if ($result === false) {
        echo json_encode(array("status" => "error", "message" => "SQL Error: " . $conn->error));
        exit;
    }

    if ($result->num_rows > 0) {
        while($row = $result->fetch_assoc()) {
            $reports[] = $row;
        }
    }

    echo json_encode(array("status" => "success", "data" => $reports));
} else {
    http_response_code(400);
    echo json_encode(array("status" => "error", "message" => "Showroom name is required."));
}

$conn->close();
?>

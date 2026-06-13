<?php
// save_service_report.php
// save_service_report.php
error_reporting(0);
ini_set('display_errors', 0);

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: POST");
header("Access-Control-Allow-Headers: Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With");

require_once 'db_connect.php';
error_reporting(0);
ini_set('display_errors', 0);

date_default_timezone_set('Asia/Kolkata');

$data = json_decode(file_get_contents("php://input"));

if (
    !empty($data->service_id) &&
    !empty($data->showroom_name) &&
    !empty($data->status)
) {
    $service_id = $conn->real_escape_string($data->service_id);
    $showroom_name = $conn->real_escape_string($data->showroom_name);
    $status = $conn->real_escape_string($data->status);
    
    // Optional fields
    $toll_free_id = !empty($data->toll_free_id) ? $conn->real_escape_string($data->toll_free_id) : '';
    $customer_details = !empty($data->customer_details) ? $conn->real_escape_string($data->customer_details) : '';
    $fault_details = !empty($data->fault_details) ? $conn->real_escape_string($data->fault_details) : '';
    $remark = !empty($data->remark) ? $conn->real_escape_string($data->remark) : '';

    $now = date('Y-m-d H:i:s');

    // Check if service_id already exists
    $checkSql = "SELECT id FROM service_reports WHERE service_id = '$service_id'";
    $result = $conn->query($checkSql);

    if ($result === false) {
        echo json_encode(array("status" => "error", "message" => "SQL Error: " . $conn->error . ". Make sure the table exists."));
        exit;
    }

    if ($result->num_rows > 0) {
        // Update existing record
        $updateSql = "UPDATE service_reports SET 
                        toll_free_id = '$toll_free_id',
                        customer_details = '$customer_details',
                        fault_details = '$fault_details',
                        remark = '$remark',
                        status = '$status',
                        updated_at = '$now'
                      WHERE service_id = '$service_id'";
        
        if ($conn->query($updateSql) === TRUE) {
            echo json_encode(array("status" => "success", "message" => "Service report updated successfully.", "service_id" => $service_id));
        } else {
            echo json_encode(array("status" => "error", "message" => "Failed to update service report: " . $conn->error));
        }
    } else {
        // Insert new record
        $insertSql = "INSERT INTO service_reports (service_id, toll_free_id, customer_details, fault_details, remark, status, showroom_name, created_at, updated_at) 
                      VALUES ('$service_id', '$toll_free_id', '$customer_details', '$fault_details', '$remark', '$status', '$showroom_name', '$now', '$now')";
        
        if ($conn->query($insertSql) === TRUE) {
            echo json_encode(array("status" => "success", "message" => "Service report saved successfully.", "service_id" => $service_id));
        } else {
            echo json_encode(array("status" => "error", "message" => "Failed to save service report: " . $conn->error));
        }
    }
} else {
    echo json_encode(array("status" => "error", "message" => "Incomplete data provided."));
}

$conn->close();
?>

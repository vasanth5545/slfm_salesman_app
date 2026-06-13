<?php
// FILE: api/upload_profile.php
// PURPOSE: Handles salesman profile photo upload and updates the database.

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");

require_once __DIR__ . '/db_connect.php';

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

$input = file_get_contents('php://input');
$data = json_decode($input, true);

if (!$data) {
    echo json_encode(['status' => 'error', 'message' => 'Invalid JSON input']);
    exit;
}

$salesman_id = $data['salesman_id'] ?? '';
$base64 = $data['image'] ?? '';
$showroom = $data['showroom'] ?? 'Main Branch';
$animal = $data['avatar_animal'] ?? '';
$clear_photo = isset($data['clear_photo']) && ($data['clear_photo'] === 'true' || $data['clear_photo'] === true);

if (empty($salesman_id)) {
    echo json_encode(['status' => 'error', 'message' => 'Missing salesman_id']);
    exit;
}

// Helper function to handle special reward logic with dynamic limits
function trackSpecialReward($conn, $salesman_id, $animal) {
    if (strtolower($animal) === 'scarface lion') {
        // 1. Get salesman's current billed count
        $scoreSql = "SELECT billed FROM salesmen WHERE salesman_id = ?";
        $scoreStmt = $conn->prepare($scoreSql);
        $scoreStmt->bind_param("s", $salesman_id);
        $scoreStmt->execute();
        $scoreRes = $scoreStmt->get_result();
        $row = $scoreRes->fetch_assoc();
        $currentBilled = $row ? (int)$row['billed'] : 0;

        // 2. Get dynamic limit from config
        $limitSql = "SELECT min_billed FROM special_rewards WHERE salesman_id IS NULL AND reward_name = 'Scarface'";
        $limitRes = $conn->query($limitSql);
        $limitRow = $limitRes->fetch_assoc();
        $minRequired = $limitRow ? (int)$limitRow['min_billed'] : 1000;

        // 3. Validation
        if ($currentBilled >= $minRequired) {
            $checkSql = "SELECT id FROM special_rewards WHERE salesman_id = ? AND reward_name = 'Scarface'";
            $checkStmt = $conn->prepare($checkSql);
            $checkStmt->bind_param("s", $salesman_id);
            $checkStmt->execute();
            $result = $checkStmt->get_result();
            
            if ($result->num_rows == 0) {
                $insertSql = "INSERT INTO special_rewards (salesman_id, reward_name) VALUES (?, 'Scarface')";
                $insertStmt = $conn->prepare($insertSql);
                $insertStmt->bind_param("s", $salesman_id);
                $insertStmt->execute();
            }
        }
    }
}

// 1. Handle Photo Clearing
if ($clear_photo) {
    $sql = "UPDATE salesmen SET profile_photo = '', avatar_animal = ? WHERE salesman_id = ?";
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("ss", $animal, $salesman_id);
    if ($stmt->execute()) {
        trackSpecialReward($conn, $salesman_id, $animal);
        echo json_encode(['status' => 'success', 'message' => 'Photo removed, animal updated', 'profile_photo' => '', 'avatar_animal' => $animal]);
    } else {
        echo json_encode(['status' => 'error', 'message' => 'Database update failed']);
    }
    exit;
}

// 2. Handle New Photo Upload
if (!empty($base64)) {
    // Base64 Cleaning
    if (strpos($base64, ',') !== false) {
        $parts = explode(',', $base64);
        $base64 = $parts[1];
    }
    $base64 = str_replace(' ', '+', $base64);

    // Directory - upload/profile/showroom/
    $safe_showroom = preg_replace('/[^A-Za-z0-9\-]/', '_', $showroom);
    $dir = "upload/profile/$safe_showroom/";

    if (!is_dir("../" . $dir)) {
        mkdir("../" . $dir, 0777, true);
    }

    // Filename SMXXX_PROFILE_ANIMALNAME.JPG
    $safe_animal = preg_replace('/[^A-Za-z0-9\-]/', '_', $animal);
    $filename = $salesman_id . "_PROFILE_" . strtoupper($safe_animal) . ".JPG";
    $relative_filepath = $dir . $filename;
    $absolute_filepath = "../" . $relative_filepath;

    $decoded_image = base64_decode($base64);

    if (file_put_contents($absolute_filepath, $decoded_image)) {
        $sql = "UPDATE salesmen SET profile_photo = ?, avatar_animal = ? WHERE salesman_id = ?";
        $stmt = $conn->prepare($sql);
        $stmt->bind_param("sss", $relative_filepath, $animal, $salesman_id);

        if ($stmt->execute()) {
            trackSpecialReward($conn, $salesman_id, $animal);
            echo json_encode([
                'status' => 'success',
                'profile_photo' => $relative_filepath,
                'avatar_animal' => $animal,
                'message' => 'Profile photo updated successfully'
            ]);
        } else {
            echo json_encode(['status' => 'error', 'message' => 'Database update failed']);
        }
    } else {
        echo json_encode(['status' => 'error', 'message' => 'Failed to save image file']);
    }
}
// 3. Handle Animal Only Update
else if (!empty($animal)) {
    $sql = "UPDATE salesmen SET avatar_animal = ? WHERE salesman_id = ?";
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("ss", $animal, $salesman_id);
    if ($stmt->execute()) {
        trackSpecialReward($conn, $salesman_id, $animal);
        echo json_encode(['status' => 'success', 'message' => 'Animal updated', 'profile_photo' => null, 'avatar_animal' => $animal]);
    } else {
        echo json_encode(['status' => 'error', 'message' => 'Database update failed']);
    }
} else {
    echo json_encode(['status' => 'error', 'message' => 'Nothing to update']);
}

$conn->close();
?>
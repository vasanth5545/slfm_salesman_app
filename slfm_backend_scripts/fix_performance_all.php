<?php
// slfm_backend_scripts/fix_performance_all.php
// PURPOSE: Force re-calculate performance for ALL salesmen for the current month.
// Run this ONCE to fix the "Incomplete Day" issue in the Summary Table.

require_once 'db_connect.php';

// 1. Get All Salesmen
$sql = "SELECT salesman_id FROM salesmen";
$result = $conn->query($sql);

echo "<h1>Starting Bulk Performance Fix...</h1>";
echo "<pre>";

// URL helper (Points to the LOCAL update_performance.php relative to this script)
// Actually, we can just REQUIRE the logic internally to avoid HTTP timeout issues.
// But `update_performance.php` expects input via POST/JSON.
// Let's just refactor slightly: We will simulate the call.

$base_url = "http://" . $_SERVER['HTTP_HOST'] . dirname($_SERVER['PHP_SELF']) . "/update_salesman_summary.php";

if ($result->num_rows > 0) {
    while($row = $result->fetch_assoc()) {
        $sid = $row['salesman_id'];
        echo "Processing Salesman: <b>$sid</b> ... ";
        
        // Call update_performance.php using cURL
        $ch = curl_init($base_url);
        $payload = json_encode(array("salesman_id" => $sid));
        
        curl_setopt($ch, CURLOPT_POSTFIELDS, $payload);
        curl_setopt($ch, CURLOPT_HTTPHEADER, array('Content-Type:application/json'));
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        
        $response = curl_exec($ch);
        $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        if ($http_code == 200) {
            echo "DONE. <br>";
        } else {
            echo "FAILED (HTTP $http_code). <br>";
        }
        
        // Flush output to browser immediately
        flush();
        ob_flush();
    }
} else {
    echo "No salesmen found.";
}

echo "</pre>";
echo "<h2>All Completed.</h2>";
$conn->close();
?>

<?php
// FILE: api/get_leaderboard.php
// PURPOSE: Fetches the gamified leaderboard data based on walking customers.
// Ranks salesmen by total "Billed" walking customers.
// TIE-BREAKER: When billed count is equal, the salesman who achieved it EARLIER ranks higher.
// Uses MIN(billed_at) — whoever got their first bill earliest (or whoever reached the count first depending on logic). User requested MIN(date).

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
require_once __DIR__ . '/db_connect.php';

$sql = "
    SELECT 
        s.salesman_id AS empId,
        s.name AS name,
        s.showroom_name AS showroom_name,
        s.profile_photo AS profile_photo,
        s.avatar_animal AS avatar_animal,
        s.status AS status,
        s.role AS role,
        COALESCE(SUM(CASE WHEN w.status = 'Billed' THEN 1 ELSE 0 END), 0) AS score,
        COALESCE(SUM(CASE WHEN w.status = 'Pending' THEN 1 ELSE 0 END), 0) AS pendingCount,
        MIN(CASE WHEN w.status = 'Billed' THEN w.billed_at ELSE NULL END) AS last_billed_at
    FROM salesmen s
    LEFT JOIN walking_customers w ON s.salesman_id = w.salesman_id
    WHERE s.status = 'Active' 
      AND LOWER(s.role) IN ('salesman', 'promoter', 'sales manager')
      AND LOWER(s.showroom_name) NOT LIKE '%godown%'
      AND LOWER(s.showroom_name) != 'kutty chutty'
      AND LOWER(s.showroom_name) != 'office'
    GROUP BY s.salesman_id
    ORDER BY score DESC, last_billed_at ASC
";

$result = $conn->query($sql);
$leaderboard = [];
$rank = 1;

if ($result && $result->num_rows > 0) {
    while ($row = $result->fetch_assoc()) {
        $row['rank'] = $rank++;
        $row['emoji'] = 'lion'; // Default, Flutter will override for top 3
        $leaderboard[] = $row;
    }
}

// 2. Fetch Reward Configurations (e.g., Scarface Limit)
$rewards_config = [
    "scarface_limit" => 1000 // Default fallback
];
$config_res = $conn->query("SELECT reward_name, min_billed FROM special_rewards WHERE salesman_id IS NULL");
if ($config_res) {
    while ($config_row = $config_res->fetch_assoc()) {
        if ($config_row['reward_name'] === 'Scarface') {
            $rewards_config['scarface_limit'] = (int)$config_row['min_billed'];
        }
    }
}

echo json_encode([
    "status" => "success",
    "rewards_config" => $rewards_config,
    "data" => $leaderboard
]);

$conn->close();
?>

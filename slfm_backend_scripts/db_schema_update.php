<?php
// slfm_backend_scripts/db_schema_update.php
// PURPOSE: Run ONE TIME to update your database structure.
// 1. Creates 'holidays' table.
// 2. Adds 'total_days_consumed' column to 'salesman_monthly_performance'.
// 3. Adds 'allow_late_entry' column to 'salesmen'.
// 4. Adds 'excluded_dates' column to 'salesman_monthly_performance'.

header("Content-Type: text/plain");
require_once __DIR__ . '/db_connect.php';

echo "🚀 Starting Database Update...\n\n";

// 1. Create HOLIDAYS Table
$sql_holidays = "CREATE TABLE IF NOT EXISTS `holidays` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `holiday_date` date NOT NULL,
  `reason` varchar(255) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `holiday_date` (`holiday_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci";

if ($conn->query($sql_holidays) === TRUE) {
    echo "✅ Table 'holidays' created/checked.\n";
} else {
    echo "❌ Error creating 'holidays': " . $conn->error . "\n";
}

// 2. Add 'total_days_consumed' to 'salesman_monthly_performance'
$check_col = "SHOW COLUMNS FROM `salesman_monthly_performance` LIKE 'total_days_consumed'";
$res = $conn->query($check_col);

if ($res && $res->num_rows == 0) {
    $sql_alter = "ALTER TABLE `salesman_monthly_performance` 
                  ADD COLUMN `total_days_consumed` decimal(5,2) DEFAULT 0.00 AFTER `attendance_percentage`";
    
    if ($conn->query($sql_alter) === TRUE) {
        echo "✅ Column 'total_days_consumed' added successfully.\n";
    } else {
        echo "❌ Error adding column 'total_days_consumed': " . $conn->error . "\n";
    }
} else {
    echo "ℹ️ Column 'total_days_consumed' already exists.\n";
}

// 2.1 Add 'excluded_dates' to 'salesman_monthly_performance' (🔥 NEW)
$check_excl = "SHOW COLUMNS FROM `salesman_monthly_performance` LIKE 'excluded_dates'";
$res_excl = $conn->query($check_excl);

if ($res_excl && $res_excl->num_rows == 0) {
    $sql_alter2 = "ALTER TABLE `salesman_monthly_performance` 
                   ADD COLUMN `excluded_dates` TEXT DEFAULT NULL AFTER `report_month`";
    
    if ($conn->query($sql_alter2) === TRUE) {
        echo "✅ Column 'excluded_dates' added successfully.\n";
    } else {
        echo "❌ Error adding column 'excluded_dates': " . $conn->error . "\n";
    }
} else {
    echo "ℹ️ Column 'excluded_dates' already exists.\n";
}

// 3. Add 'allow_late_entry' to 'salesmen' (Task 2: Manual Override)
$table_salesmen = "salesmen";
$column_override = "allow_late_entry";
$check_override = "SHOW COLUMNS FROM $table_salesmen LIKE '$column_override'";
$res_override = $conn->query($check_override);

if ($res_override && $res_override->num_rows == 0) {
    $sql_override = "ALTER TABLE $table_salesmen ADD COLUMN $column_override TINYINT(1) DEFAULT 0 AFTER shift_end_time";
    if ($conn->query($sql_override) === TRUE) {
        echo "✅ Column 'allow_late_entry' added successfully.\n";
    } else {
        echo "❌ Error adding column 'allow_late_entry': " . $conn->error . "\n";
    }
} else {
    echo "ℹ️ Column 'allow_late_entry' already exists.\n";
}

echo "\n✨ Database Update Complete. You can now run the App/Logic.";
$conn->close();
?>

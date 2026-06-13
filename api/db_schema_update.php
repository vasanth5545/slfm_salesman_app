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

// 4. Add Device Tracking Columns (🔥 NEW: To solve mobile name and model missing issue)
$device_cols = [
    'primary_device_id' => 'varchar(255) DEFAULT NULL AFTER current_lng',
    'primary_device_model' => 'varchar(255) DEFAULT NULL AFTER primary_device_id',
    'is_device_locked' => 'tinyint(1) DEFAULT 0 AFTER primary_device_model'
];

foreach ($device_cols as $col_name => $col_def) {
    $check_col = "SHOW COLUMNS FROM `$table_salesmen` LIKE '$col_name'";
    $res_col = $conn->query($check_col);
    if ($res_col && $res_col->num_rows == 0) {
        $sql_add = "ALTER TABLE `$table_salesmen` ADD COLUMN `$col_name` $col_def";
        if ($conn->query($sql_add) === TRUE) {
            echo "✅ Column '$col_name' added successfully.\n";
        } else {
            echo "❌ Error adding column '$col_name': " . $conn->error . "\n";
        }
    } else {
        echo "ℹ️ Column '$col_name' already exists.\n";
    }
}

// 5. Create Service Reports Table
$table_service = "service_reports";
$sql_service = "CREATE TABLE IF NOT EXISTS `$table_service` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `service_id` varchar(100) NOT NULL,
    `toll_free_id` varchar(100) DEFAULT NULL,
    `customer_details` text DEFAULT NULL,
    `fault_details` text DEFAULT NULL,
    `remark` text DEFAULT NULL,
    `status` enum('Pending','Finished') DEFAULT 'Pending',
    `showroom_name` varchar(100) NOT NULL,
    `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
    `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
    PRIMARY KEY (`id`),
    UNIQUE KEY `service_id_unique` (`service_id`)
)";
if ($conn->query($sql_service) === TRUE) {
    echo "✅ Table '$table_service' checked/created successfully.\n";
} else {
    echo "❌ Error creating table '$table_service': " . $conn->error . "\n";
}

// 6. Update Feature Control for Multi-Showroom support
$table_fc = "feature_control";
$check_fc_showroom = "SHOW COLUMNS FROM `$table_fc` LIKE 'showroom_name'";
$res_fc_showroom = $conn->query($check_fc_showroom);

if ($res_fc_showroom && $res_fc_showroom->num_rows == 0) {
    $sql_fc_alter = "ALTER TABLE `$table_fc` 
                     ADD COLUMN `showroom_name` varchar(100) DEFAULT 'All Showrooms' AFTER `feature_name`";
    if ($conn->query($sql_fc_alter) === TRUE) {
        echo "✅ Column 'showroom_name' added to '$table_fc'.\n";
        
        // Update index to be composite (feature_name, showroom_name)
        // First drop old index if it's named 'feature_name' or just unique
        $conn->query("ALTER TABLE `$table_fc` DROP INDEX `feature_name` ");
        $conn->query("ALTER TABLE `$table_fc` ADD UNIQUE KEY `feature_showroom_unique` (`feature_name`, `showroom_name`) ");
        echo "✅ Composite UNIQUE KEY (feature_name, showroom_name) created.\n";
    } else {
        echo "❌ Error updating '$table_fc': " . $conn->error . "\n";
    }
} else {
    echo "ℹ️ Table '$table_fc' already has showroom support.\n";
    // Double check the index anyway
    $res_idx = $conn->query("SHOW INDEX FROM `$table_fc` WHERE Key_name = 'feature_showroom_unique'");
    if ($res_idx && $res_idx->num_rows == 0) {
        $conn->query("ALTER TABLE `$table_fc` DROP INDEX IF EXISTS `feature_name` ");
        $conn->query("ALTER TABLE `$table_fc` ADD UNIQUE KEY `feature_showroom_unique` (`feature_name`, `showroom_name`) ");
        echo "✅ Fixed UNIQUE KEY for showroom support.\n";
    }
}

// 7. Add 'face_id' to 'salesmen' (For Face Recognition Sync)
$column_face = "face_id";
$check_face = "SHOW COLUMNS FROM `$table_salesmen` LIKE '$column_face'";
$res_face = $conn->query($check_face);

if ($res_face && $res_face->num_rows == 0) {
    $sql_face = "ALTER TABLE `$table_salesmen` ADD COLUMN `$column_face` TEXT DEFAULT NULL AFTER `avatar_animal`";
    if ($conn->query($sql_face) === TRUE) {
        echo "✅ Column 'face_id' added successfully.\n";
    } else {
        echo "❌ Error adding column 'face_id': " . $conn->error . "\n";
    }
} else {
    echo "ℹ️ Column 'face_id' already exists.\n";
}

echo "\n✨ Database Update Complete. You can now run the App/Logic.";
$conn->close();
?>
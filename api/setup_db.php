<?php
// setup_db.php
// RUN THIS ONCE: To restore/import the Database Structure & Data you provided.

header("Content-Type: application/json");
require 'db_connect.php';

// The SQL Dump you provided
$sql = "
SET SQL_MODE = \"NO_AUTO_VALUE_ON_ZERO\";
START TRANSACTION;
SET time_zone = \"+00:00\";

-- Create Tables if not exists
CREATE TABLE IF NOT EXISTS `attendance` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `salesman_id` varchar(20) NOT NULL,
  `salesman_name` varchar(100) DEFAULT NULL,
  `showroom_name` varchar(100) DEFAULT NULL,
  `date` date NOT NULL,
  `clock_in_time` timestamp NULL DEFAULT NULL,
  `clock_out_time` timestamp NULL DEFAULT NULL,
  `selfie_url` varchar(255) DEFAULT NULL,
  `status` enum('Present','Absent','On Leave','Half Day') DEFAULT 'Absent',
  `is_late` tinyint(1) DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `latitude` varchar(50) DEFAULT NULL,
  `longitude` varchar(50) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `salesman_id` (`salesman_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `billing_staff` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `staff_id` varchar(50) NOT NULL,
  `name` varchar(100) NOT NULL,
  `password_hash` varchar(255) NOT NULL,
  `role` enum('Admin','Staff') DEFAULT 'Staff',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `staff_id` (`staff_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `bills` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `order_id` varchar(50) NOT NULL,
  `salesman_id` varchar(20) NOT NULL,
  `customer_name` varchar(100) NOT NULL,
  `customer_phone` varchar(15) NOT NULL,
  `customer_address` text DEFAULT NULL,
  `product_os_code` varchar(50) NOT NULL,
  `final_price` decimal(10,2) NOT NULL,
  `status` enum('Pending','Printed','Cancelled') DEFAULT 'Pending',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `order_id` (`order_id`),
  KEY `salesman_id` (`salesman_id`),
  KEY `product_os_code` (`product_os_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `damage_reports` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `salesman_id` varchar(50) NOT NULL,
  `os_code` varchar(100) NOT NULL,
  `brand` varchar(100) DEFAULT NULL,
  `model` varchar(100) DEFAULT NULL,
  `rate` varchar(50) DEFAULT NULL,
  `description` text DEFAULT NULL,
  `images` text DEFAULT NULL,
  `status` varchar(20) DEFAULT 'Pending',
  `created_at` datetime DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `feature_control` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `feature_name` varchar(50) NOT NULL,
  `is_active` tinyint(1) DEFAULT 1,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `feature_name` (`feature_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `leave_cancel_requests` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `salesman_id` varchar(50) DEFAULT NULL,
  `salesman_name` varchar(100) DEFAULT NULL,
  `leave_id` int(11) NOT NULL,
  `cancel_reason` text DEFAULT NULL,
  `created_at` datetime DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `leave_requests` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `salesman_id` varchar(20) NOT NULL,
  `leave_date` date NOT NULL,
  `leave_type` enum('Full Day','Half Day') DEFAULT 'Full Day',
  `reason` text NOT NULL,
  `status` enum('Pending','Approved','Rejected') DEFAULT 'Pending',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `salesman_id` (`salesman_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `location_history` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `salesman_id` varchar(50) NOT NULL,
  `latitude` decimal(10,8) NOT NULL,
  `longitude` decimal(11,8) NOT NULL,
  `timestamp` datetime DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `salesman_id` (`salesman_id`),
  KEY `timestamp` (`timestamp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `lookup_history` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `salesman_id` varchar(20) NOT NULL,
  `product_os_code` varchar(50) NOT NULL,
  `searched_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `salesman_id` (`salesman_id`),
  KEY `product_os_code` (`product_os_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `products` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `os_code` varchar(50) NOT NULL,
  `name` varchar(255) NOT NULL,
  `brand` varchar(100) DEFAULT NULL,
  `category` varchar(100) DEFAULT NULL,
  `mrp` decimal(10,2) NOT NULL,
  `offer_price` decimal(10,2) DEFAULT NULL,
  `mop` decimal(10,2) DEFAULT NULL,
  `stock_count` int(11) DEFAULT 0,
  `image_url` varchar(255) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `os_code` (`os_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `salesmen` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `salesman_id` varchar(20) NOT NULL,
  `name` varchar(100) NOT NULL,
  `gender` enum('Male','Female') DEFAULT 'Male',
  `password_hash` varchar(255) NOT NULL,
  `showroom_name` varchar(100) DEFAULT 'Main Branch',
  `showroom_address` text DEFAULT NULL,
  `status` enum('Active','Suspended') DEFAULT 'Active',
  `shift_start_time` time DEFAULT '09:30:00',
  `shift_end_time` time DEFAULT '21:30:00',
  `half_day_start` time DEFAULT '09:30:00',
  `half_day_end` time DEFAULT '15:00:00',
  `last_sync` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `is_tracking` int(11) DEFAULT 0,
  `tracking_expiry` datetime DEFAULT NULL,
  `current_lat` decimal(10,8) DEFAULT NULL,
  `current_lng` decimal(10,8) DEFAULT NULL,
  `last_location_update` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `salesman_id` (`salesman_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `stock_checks` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `salesman_id` varchar(20) NOT NULL,
  `product_os_code` varchar(50) NOT NULL,
  `scanned_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `salesman_id` (`salesman_id`),
  KEY `product_os_code` (`product_os_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `walking_customers` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `salesman_id` varchar(50) NOT NULL,
  `customer_name` varchar(100) NOT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `product_interest` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `feedback_text` text DEFAULT NULL,
  `feedback_by` varchar(100) DEFAULT NULL,
  `feedback_date` datetime DEFAULT NULL,
  `bill_photo` varchar(255) DEFAULT NULL,
  `status` varchar(20) DEFAULT 'Pending',
  `billed_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- Insert Feature Control Defaults
INSERT IGNORE INTO `feature_control` (`id`, `feature_name`, `is_active`) VALUES
(1, 'walking_customer', 1),
(2, 'damage_report', 1);

-- Insert Default Admin
INSERT IGNORE INTO `billing_staff` (`id`, `staff_id`, `name`, `password_hash`, `role`) VALUES
(1, 'admin', 'Super Admin', 'slfm2025', 'Admin');

COMMIT;
";

// Execute Multi Query
if ($conn->multi_query($sql)) {
    do {
        // Store first result set
        if ($result = $conn->store_result()) {
            $result->free();
        }
    } while ($conn->more_results() && $conn->next_result());
    echo json_encode(["status" => "success", "message" => "Database Setup/Restore Completed Successfully."]);
} else {
    echo json_encode(["status" => "error", "message" => "SQL Execution Error: " . $conn->error]);
}

$conn->close();
?>
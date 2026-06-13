<?php
require_once 'api/db_connect.php';

$sql = "ALTER TABLE `attendance` 
        DROP COLUMN IF EXISTS `break_out_time`, 
        DROP COLUMN IF EXISTS `re_entry_time`, 
        DROP COLUMN IF EXISTS `break_fallback_status`, 
        DROP COLUMN IF EXISTS `extra_break_time`";

if ($conn->query($sql)) {
    echo "SUCCESS: Legacy columns removed from attendance table.\n";
} else {
    echo "ERROR: " . $conn->error . "\n";
}
?>

<?php
// Enable Error Suppression for Clean Output
error_reporting(E_ERROR | E_PARSE);
ini_set('display_errors', 0);

// Open output stream EARLY to handle headers even on errors
ob_clean();

// ✅ CSV format-ku maathiyachu (frontend CSV-ah thaan download pannuthu)
header("Content-Type: text/csv; charset=utf-8");
header("Content-Disposition: attachment; filename=early_arrivals_report.csv");
header("Access-Control-Allow-Origin: *");
header("Cache-Control: no-cache, no-store, must-revalidate");
header("Pragma: no-cache");
header("Expires: 0");

date_default_timezone_set('Asia/Kolkata');

// ✅ Output UTF-8 BOM for Excel
echo "\xEF\xBB\xBF";

// 🔌 DB CONNECT
$db_found = false;
$possible_paths = [__DIR__ . '/db_connect.php', __DIR__ . '/../db_connect.php'];
foreach ($possible_paths as $path) {
    if (file_exists($path)) {
        require_once $path;
        $db_found = true;
        break;
    }
}

// Open output stream for CSV
$output = fopen('php://output', 'w');

if (!$db_found) {
    fputcsv($output, ["Error", "db_connect.php not found"]);
    fclose($output);
    exit;
}

$start_date = $_POST['start_date'] ?? $_GET['start_date'] ?? date('Y-m-d');
$end_date   = $_POST['end_date']   ?? $_GET['end_date']   ?? date('Y-m-d');
$showroom   = $_POST['showroom']   ?? $_GET['showroom']   ?? 'All';

// ✅ Validate date format
if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $start_date) || 
    !preg_match('/^\d{4}-\d{2}-\d{2}$/', $end_date)) {
    fputcsv($output, ["Error", "Invalid Date Format (Use YYYY-MM-DD)"]);
    fclose($output);
    exit;
}

// ✅ Fetch Data
$sql = "SELECT a.date, a.salesman_id, s.name, s.showroom_name, a.clock_in_time, a.clock_out_time, a.admin_approval 
        FROM attendance a
        JOIN salesmen s ON a.salesman_id = s.salesman_id
        WHERE a.date BETWEEN ? AND ?";

if ($showroom !== 'All') {
    $sql .= " AND s.showroom_name = ?";
}

$sql .= " ORDER BY a.date DESC, a.clock_in_time ASC";

$stmt = $conn->prepare($sql);
if (!$stmt) {
    fputcsv($output, ["Error", "Database Error: {$conn->error}"]);
    fclose($output);
    exit;
}

if ($showroom !== 'All') {
    $stmt->bind_param("sss", $start_date, $end_date, $showroom);
} else {
    $stmt->bind_param("ss", $start_date, $end_date);
}

$stmt->execute();
$result = $stmt->get_result();

// Data-va Showroom vechu group panna array
$grouped_data = [];

if ($result && $result->num_rows > 0) {
    while ($row = $result->fetch_assoc()) {
        
        $clock_in = $row['clock_in_time'];
        $clock_out = $row['clock_out_time'];
        
        if (empty($clock_in)) continue; // Skip if no clock-in time

        // ✅ Safely parse time using PHP which handles '09:11 AM' perfectly
        $in_time_unix = strtotime($clock_in);
        $cutoff_time_unix = strtotime('09:30:59');

        // Check if Clocked in Before or At 09:30:59
        if ($in_time_unix && $in_time_unix <= $cutoff_time_unix) {
            
            // ✅ Check if clocked out after 6 PM or still present
            $is_valid_out_time = false;
            if (empty($clock_out) || $clock_out === '00:00:00') {
                $is_valid_out_time = true; // Still Present
            } else {
                $out_time_unix = strtotime($clock_out);
                $six_pm_unix = strtotime('18:00:00'); // 6:00 PM
                if ($out_time_unix && $out_time_unix >= $six_pm_unix) {
                    $is_valid_out_time = true; // Clocked out after 6 PM
                }
            }

            if ($is_valid_out_time) {
                $out_time_display = (!empty($clock_out) && $clock_out !== '00:00:00') 
                            ? date('h:i A', strtotime($clock_out)) 
                            : "Still Present";

                $sr_name = $row['showroom_name'] ?? 'Main Branch';
                
                // Showroom thirichu data append panrom
                $grouped_data[$sr_name][] = [
                    'date' => $row['date'],
                    'emp_id' => $row['salesman_id'],
                    'name' => $row['name'],
                    'in_time' => $in_time_unix,
                    'out_time' => $out_time_display
                ];
            }
        }
    }
}

// ✅ PURE CSV TABLE GENERATION (Side-by-Side Logic)
if (empty($grouped_data)) {
    fputcsv($output, ["No early arrivals found"]);
} else {
    $showrooms = array_keys($grouped_data);
    $max_rows = 0;
    
    // Yentha showroom-la athigamana rows irukku nu kandupudikka
    foreach ($grouped_data as $sr => $emps) {
        if (count($emps) > $max_rows) {
            $max_rows = count($emps);
        }
    }

    // ROW 1: Titles for each showroom
    $title_row = [];
    foreach ($showrooms as $sr) {
        $title_row[] = "EARLY ARRIVALS - " . strtoupper($sr);
        array_push($title_row, "", "", "", "", ""); // 5 empty columns for aligning
        $title_row[] = ""; // 1 spacing column between tables
    }
    fputcsv($output, $title_row);

    // ROW 2: Headers for each showroom
    $col_row = [];
    foreach ($showrooms as $sr) {
        array_push($col_row, "Date", "Salesman ID", "Name", "Showroom", "Clock-In Time", "Clock-Out Time", "");
    }
    fputcsv($output, $col_row);

    // DATA ROWS: side-by-side printing
    for ($i = 0; $i < $max_rows; $i++) {
        $data_row = [];
        foreach ($showrooms as $sr) {
            if (isset($grouped_data[$sr][$i])) {
                $emp = $grouped_data[$sr][$i];
                array_push($data_row,
                    " " . date('d-m-Y', strtotime($emp['date'])),
                    $emp['emp_id'],
                    $emp['name'],
                    $sr,
                    " " . date('h:i A', $emp['in_time']),
                    " " . $emp['out_time'],
                    "" // spacing column
                );
            } else {
                // Intha showroom-la data theernthu pocha empty cells add pannanum
                array_push($data_row, "", "", "", "", "", "", "");
            }
        }
        fputcsv($output, $data_row);
    }
}

// ✅ Close everything
fclose($output);
if ($stmt) {
    $stmt->close();
}
$conn->close();
?>
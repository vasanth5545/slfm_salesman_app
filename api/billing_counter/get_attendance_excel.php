<?php
// slfm_api/billing_counter/get_attendance_excel.php
// PURPOSE: Generates a CSV matrix of attendance data for direct Excel viewing.
// FEATURES: Side-by-Side Layout (Left: Main Attendance grouped by Showroom | Right: M/O List, Leave Reports & Extra Manual Table)

// ✅ TEMPORARY FIX: Error veliya theriya E_ALL set pannirukom (500 error-a kandupudikka)
error_reporting(E_ALL);
ini_set('display_errors', 1);

// ✅ FIX: Buffer iruntha mattum clean pannanum (Ilati 500 error varum)
if (ob_get_level() > 0) {
    ob_clean();
}

date_default_timezone_set('Asia/Kolkata');

// ✅ FIX: Dynamic File Name with Timestamp to prevent Browser Caching
$timestamp = date('d-m-Y_h-i-A');
$filename = "attendance_report_{$timestamp}.xls";

// ✅ FIX: Simplified Headers (Pazhaya headers + Puthu filename)
header("Content-Type: application/vnd.ms-excel; charset=utf-8");
header("Content-Disposition: attachment; filename=\"{$filename}\"");
header("Access-Control-Allow-Origin: *");
header("Cache-Control: no-cache, no-store, must-revalidate");
header("Pragma: no-cache");
header("Expires: 0");

// ✅ UTF-8 BOM for Excel Compatibility
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

if (!$db_found) {
    echo "Sl.No,Error\n1,db_connect.php kandittilla";
    exit;
}

$start_date = $_POST['start_date'] ?? $_GET['start_date'] ?? date('Y-m-01');
$end_date = $_POST['end_date'] ?? $_GET['end_date'] ?? date('Y-m-t');
$showroom = $_POST['showroom'] ?? $_GET['showroom'] ?? 'All';
$current_date = date('Y-m-d');

// ✅ Date format validate cheyyunnu
if (
    !preg_match('/^\d{4}-\d{2}-\d{2}$/', $start_date) ||
    !preg_match('/^\d{4}-\d{2}-\d{2}$/', $end_date)
) {
    echo "Sl.No,Error\n1,Thettaya Date Format (YYYY-MM-DD upayogikkuka)";
    exit;
}

// Dynamic dates generate cheyyunnu
try {
    $period = new DatePeriod(
        new DateTime($start_date),
        new DateInterval('P1D'),
        (new DateTime($end_date))->modify('+1 day')
    );
} catch (Exception $e) {
    echo "Sl.No,Error\n1,Thettaya Date Range";
    exit;
}

$dates = [];
foreach ($period as $dt) {
    if ($dt->format('Y-m-d') <= $current_date) {
        $dates[] = $dt->format('Y-m-d');
    }
}

// Holidays fetch cheyyunnu
$holidays = [];
$h_sql = "SELECT holiday_date FROM holidays WHERE holiday_date BETWEEN ? AND ?";
$h_stmt = $conn->prepare($h_sql);
if ($h_stmt) {
    $h_stmt->bind_param("ss", $start_date, $end_date);
    $h_stmt->execute();
    $h_res = $h_stmt->get_result();
    while ($h_row = $h_res->fetch_assoc()) {
        $holidays[] = $h_row['holiday_date'];
    }
    $h_stmt->close();
} else {
    error_log("Holiday query error: " . $conn->error);
}

// ✅ UPDATE: Fetch employees who were active during the selected month
$salesmen_sql = "SELECT salesman_id, name, phone, IFNULL(role, 'Salesman') as role, showroom_name, created_at, status, relieving_date 
                 FROM salesmen 
                 WHERE DATE(created_at) <= ? 
                 AND (status = 'Active' OR (relieving_date IS NOT NULL AND relieving_date != '0000-00-00' AND DATE(relieving_date) >= ?))";

if ($showroom !== 'All') {
    $salesmen_sql .= " AND showroom_name = ?";
}
$salesmen_sql .= " ORDER BY showroom_name ASC, name ASC";

$salesmen_stmt = $conn->prepare($salesmen_sql);
if (!$salesmen_stmt) {
    echo "Sl.No,Error\n1,Database Error: {$conn->error}";
    exit;
}

// Bind Parameters for the query
if ($showroom !== 'All') {
    $salesmen_stmt->bind_param("sss", $end_date, $start_date, $showroom);
} else {
    $salesmen_stmt->bind_param("ss", $end_date, $start_date);
}

$salesmen_stmt->execute();
$salesmen_res = $salesmen_stmt->get_result();

// ==========================================
// ✅ MASTER LAYOUT TABLE (Side-by-side aayi vekkan)
// ==========================================
echo "<table border='0' cellpadding='0' cellspacing='0'>";
echo "<tr>";

// ------------------------------------------
// 🟢 LEFT COLUMN: MAIN ATTENDANCE MATRIX (Grouped by Showroom)
// ------------------------------------------
echo "<td valign='top'>";

// M/O, Leave, and New Daily Details Arrays
$mo_records = [];
$leave_records = [];
$relieved_records = [];
$daily_details = []; // Array to hold Daily details format data

// Salesmen data showroom-wise group cheyyunnu
$grouped_salesmen = [];
if ($salesmen_res && $salesmen_res->num_rows > 0) {
    while ($salesman = $salesmen_res->fetch_assoc()) {
        $sr_name = $salesman['showroom_name'] ?? 'Main Branch';
        $grouped_salesmen[$sr_name][] = $salesman;
    }
}

if (empty($grouped_salesmen)) {
    echo "<table border='1'><tr><td colspan='10'>Records onnum kandittilla</td></tr></table>";
} else {
    // Showroom-wise loop
    foreach ($grouped_salesmen as $showroom_group_name => $employees) {
        echo "<table border='1'>";

        // Headers ezhuthunnu
        $headers = ['Sl.No', 'Salesman Name', 'Phone Number', 'Date of Joining', 'Date of Relieving', 'Role', 'Showroom'];
        foreach ($dates as $date) {
            $headers[] = date('d', strtotime($date));
        }
        $headers = array_merge($headers, ['Total Present', 'Total Leave/Absent', 'Total Half Day', 'Total Days Worked', 'Total Working Days']);

        echo "<tr style='background-color: #f2f2f2; font-weight: bold;'>";
        foreach ($headers as $header) {
            echo "<th>{$header}</th>";
        }
        echo "</tr>";

        $sl_no = 1;

        foreach ($employees as $salesman) {
            $sid = $salesman['salesman_id'];
            $name = $salesman['name'];
            $phone = !empty($salesman['phone']) ? $salesman['phone'] : '-';
            $role_val = $salesman['role'] ?? 'Salesman';
            $showroom_name = $salesman['showroom_name'] ?? 'Main Branch';

            $join_date_only = !empty($salesman['created_at']) ? date('Y-m-d', strtotime($salesman['created_at'])) : '2000-01-01';

            $rel_date_db = $salesman['relieving_date'] ?? '';
            $rel_date_only = (!empty($rel_date_db) && $rel_date_db !== '0000-00-00' && $rel_date_db !== '0000-00-00 00:00:00') ? date('Y-m-d', strtotime($rel_date_db)) : '-';

            $display_doj = ($join_date_only !== '2000-01-01') ? date('d-m-Y', strtotime($join_date_only)) : '-';
            $display_dor = ($rel_date_only !== '-') ? date('d-m-Y', strtotime($rel_date_only)) : '-';

            $target_month = date('Y-m', strtotime($start_date));
            $emp_rel_month = ($rel_date_only !== '-') ? date('Y-m', strtotime($rel_date_only)) : '-';

            if ($emp_rel_month === $target_month) {
                $relieved_records[] = [
                    'name' => $name,
                    'doj' => $display_doj,
                    'dor' => $display_dor
                ];
            }

            // ✅ FIX: Removed ORDER BY to avoid SQL syntax issues. Array overwriting will handle duplicates automatically.
            $att_rows_sql = "SELECT date, status, clock_in_time, clock_out_time 
                             FROM attendance 
                             WHERE salesman_id = ? 
                             AND date BETWEEN ? AND ?";
            $att_stmt = $conn->prepare($att_rows_sql);

            if (!$att_stmt) {
                continue;
            }

            $att_stmt->bind_param("sss", $sid, $start_date, $end_date);
            $att_stmt->execute();
            $att_rows_res = $att_stmt->get_result();

            $attendance_lookup = [];
            if ($att_rows_res) {
                while ($row = $att_rows_res->fetch_assoc()) {
                    $attendance_lookup[$row['date']] = $row;
                }
            }

            $row_data = [$sl_no++, $name, $phone, $display_doj, $display_dor, $role_val, $showroom_name];

            $present_count = 0;
            $half_day_count = 0;
            $absent_leave_count = 0;
            $total_working_days = 0;

            $leave_dates_arr = [];

            foreach ($dates as $date) {
                $cell_val = '-';
                $r_in = '';
                $r_out = '';

                // Not joined yet
                if ($date < $join_date_only) {
                    $cell_val = 'N/A';
                    $row_data[] = $cell_val;
                    $daily_details[$date][] = ['name' => $name, 'role' => $role_val, 'showroom' => $showroom_name, 'status' => $cell_val, 'in_time' => '', 'out_time' => ''];
                    continue;
                }

                // Already Relieved
                if ($rel_date_only !== '-' && $date > $rel_date_only) {
                    $cell_val = 'N/A';
                    $row_data[] = $cell_val;
                    $daily_details[$date][] = ['name' => $name, 'role' => $role_val, 'showroom' => $showroom_name, 'status' => $cell_val, 'in_time' => '', 'out_time' => ''];
                    continue;
                }

                if (!in_array($date, $holidays)) {
                    $total_working_days++;
                }

                if (isset($attendance_lookup[$date])) {
                    $att = $attendance_lookup[$date];
                    $status_lower = strtolower($att['status']);
                    $r_in = $att['clock_in_time'];
                    $r_out = $att['clock_out_time'];

                    if ($date != $current_date && !empty($r_in) && empty($r_out)) {
                        if ($status_lower == 'present' || $status_lower == 'half day') {
                            $cell_val = 'M/O';
                            $row_data[] = $cell_val;

                            $mo_records[] = [
                                'name' => $name,
                                'phone' => $phone,
                                'showroom' => $showroom_name,
                                'role' => $role_val,
                                'date' => date('d-m-Y', strtotime($date))
                            ];

                            $daily_details[$date][] = ['name' => $name, 'role' => $role_val, 'showroom' => $showroom_name, 'status' => $cell_val, 'in_time' => $r_in, 'out_time' => $r_out];
                            continue;
                        }
                    }

                    if (in_array($date, $holidays)) {
                        $cell_val = 'Holiday';
                        $row_data[] = $cell_val;
                        $daily_details[$date][] = ['name' => $name, 'role' => $role_val, 'showroom' => $showroom_name, 'status' => $cell_val, 'in_time' => $r_in, 'out_time' => $r_out];
                        continue;
                    }

                    if ($status_lower == 'present') {
                        $cell_val = 'P';
                        $present_count++;
                    } elseif ($status_lower == 'half day' || strpos($status_lower, 'half') !== false) {
                        $cell_val = 'H';
                        $half_day_count++;
                    } elseif (strpos($status_lower, 'leave') !== false) {
                        $cell_val = 'L';
                        $absent_leave_count++;
                    } else {
                        $cell_val = 'A';
                        $absent_leave_count++;
                    }
                } else {
                    if (in_array($date, $holidays)) {
                        $cell_val = 'Holiday';
                    } else {
                        $cell_val = 'A';
                        $absent_leave_count++;
                    }
                }

                $row_data[] = $cell_val;

                // ✅ Track details for the new Table format
                $daily_details[$date][] = ['name' => $name, 'role' => $role_val, 'showroom' => $showroom_name, 'status' => $cell_val, 'in_time' => $r_in, 'out_time' => $r_out];

                // FN/AN Leave Dates track
                $day_num = date('j', strtotime($date));
                if ($cell_val === 'L' || $cell_val === 'A') {
                    $leave_dates_arr[] = $day_num;
                } elseif ($cell_val === 'H') {
                    $r_in_for_half = isset($attendance_lookup[$date]['clock_in_time']) ? $attendance_lookup[$date]['clock_in_time'] : '';
                    if (!empty($r_in_for_half)) {
                        $in_time = strtotime($r_in_for_half);
                        $in_time_only = date('H:i:s', $in_time);
                        if ($in_time_only <= '10:00:59') {
                            $leave_dates_arr[] = $day_num . 'FN';
                        } else {
                            $leave_dates_arr[] = $day_num . 'AN';
                        }
                    } else {
                        $stat = isset($attendance_lookup[$date]) ? strtolower($attendance_lookup[$date]['status']) : '';
                        if (strpos($stat, 'fn') !== false) {
                            $leave_dates_arr[] = $day_num . 'FN';
                        } elseif (strpos($stat, 'an') !== false) {
                            $leave_dates_arr[] = $day_num . 'AN';
                        } else {
                            $leave_dates_arr[] = $day_num . '(Half)';
                        }
                    }
                }
            }

            $adjusted_present = $present_count + ($half_day_count * 0.5);
            $adjusted_leave_absent = $absent_leave_count + ($half_day_count * 0.5);

            $row_data[] = $adjusted_present;
            $row_data[] = $adjusted_leave_absent;
            $row_data[] = $half_day_count;
            $row_data[] = $adjusted_present;
            $row_data[] = $total_working_days;

            if ($adjusted_leave_absent > 0) {
                $leave_records[] = [
                    'name' => $name,
                    'showroom' => $showroom_name,
                    'leave_dates' => implode(', ', $leave_dates_arr),
                    'total_leave' => $adjusted_leave_absent
                ];
            }

            // HTML Row Output
            echo "<tr>";
            foreach ($row_data as $index => $cell) {
                if ($cell === 'N/A') {
                    echo "<td style='background-color: #ffcccc; color: #cc0000; font-weight: bold; text-align: center;'>{$cell}</td>";
                } elseif ($cell === 'M/O') {
                    echo "<td style='background-color: #ffe5b4; color: #ff8c00; font-weight: bold; text-align: center;'>{$cell}</td>";
                } elseif ($cell === 'A') {
                    echo "<td style='color: red; font-weight: bold; text-align: center;'>{$cell}</td>";
                } elseif ($cell === 'P' || $cell === 'H' || $cell === 'L' || $cell === 'Holiday') {
                    echo "<td style='text-align: center;'>{$cell}</td>";
                } else {
                    if ($index === 2 && $cell !== '-') {
                        echo "<td style='mso-number-format:\"\@\"; text-align: left;'>{$cell}</td>";
                    } else {
                        echo "<td>{$cell}</td>";
                    }
                }
            }
            echo "</tr>";

            if ($att_stmt) {
                $att_stmt->close();
            }
        }

        echo "</table><br><br>"; // Spacing between each showroom table
    }
}

if ($salesmen_stmt) {
    $salesmen_stmt->close();
}

echo "</td>"; // Left Column avasanikkunnu

// ------------------------------------------
// 🟢 SPACER COLUMN
// ------------------------------------------
echo "<td style='width: 40px;'>&nbsp;</td>";

// ------------------------------------------
// 🟢 RIGHT COLUMN: M/O & LEAVE REPORTS
// ------------------------------------------
echo "<td valign='top'>";

// ✅ 1. Missed Out (M/O) Table 
if (isset($mo_records) && count($mo_records) > 0) {
    echo "<table border='1'>";
    echo "<tr><td colspan='7' style='font-family: sans-serif; font-size: 16px; font-weight: bold; background-color: #f2f2f2; text-align: center;'>Missed Out (M/O) List</td></tr>";
    echo "<tr style='background-color: #e6e6e6; font-weight: bold;'>";
    echo "<th>Sl.No</th><th>Name</th><th>Phone Number</th><th>Showroom</th><th>Role</th><th>Date</th><th>Status</th>";
    echo "</tr>";

    $mo_sl_no = 1;
    foreach ($mo_records as $mo) {
        echo "<tr>";
        echo "<td style='text-align: center;'>" . $mo_sl_no++ . "</td>";
        echo "<td>{$mo['name']}</td>";
        echo "<td style='mso-number-format:\"\@\"; text-align: left;'>{$mo['phone']}</td>";
        echo "<td>{$mo['showroom']}</td>";
        echo "<td>{$mo['role']}</td>";
        echo "<td style='text-align: center;'>{$mo['date']}</td>";
        echo "<td style='background-color: #ffe5b4; color: #ff8c00; font-weight: bold; text-align: center;'>M/O</td>";
        echo "</tr>";
    }
    echo "</table><br><br>";
}

$display_month = strtoupper(date('F', strtotime($start_date)));

// ✅ 2. Leave Attendance Report Tables
if (isset($leave_records) && count($leave_records) > 0) {
    $leave_by_showroom = [];
    foreach ($leave_records as $lr) {
        $leave_by_showroom[$lr['showroom']][] = $lr;
    }

    foreach ($leave_by_showroom as $sr_name => $sr_records) {
        $display_showroom = strtoupper($sr_name);

        echo "<table border='1'>";
        echo "<tr><td colspan='4' style='font-weight: bold; text-align: center; background-color: #ffff00; font-size: 16px;'>LEAVE ATTENDANCE <span style='color: red;'>{$display_showroom}</span> REPORT OF {$display_month} MONTH</td></tr>";

        echo "<tr style='background-color: #f2f2f2; font-weight: bold;'>";
        echo "<th>Sl.No</th>";
        echo "<th>EMPLOYEE NAME</th>";
        echo "<th>DATE OF LEAVE</th>";
        echo "<th>NO. OF DAYS LEAVE</th>";
        echo "</tr>";

        $lr_sl = 1;
        foreach ($sr_records as $lr) {
            echo "<tr>";
            echo "<td style='text-align: center;'>" . $lr_sl++ . "</td>";
            echo "<td>" . htmlspecialchars($lr['name']) . "</td>";
            echo "<td style='text-align: left;'>" . $lr['leave_dates'] . "</td>";
            echo "<td style='text-align: center; font-weight: bold;'>" . $lr['total_leave'] . "</td>";
            echo "</tr>";
        }
        echo "</table><br><br>";
    }
}

// ✅ 3. Extra Table (Relieving Employees Details)
echo "<table border='1'>";
echo "<tr><td colspan='4' style='font-weight: bold; text-align: center; background-color: #ffff99; font-size: 16px; height: 30px;'>RELIEVING EMPLOYEES DETAILS OF {$display_month} MONTH</td></tr>";
echo "<tr style='background-color: #f2f2f2; font-weight: bold;'>";
echo "<th>Sl.No</th>";
echo "<th>EMPLOYEE NAME</th>";
echo "<th>DATE OF JOINING</th>";
echo "<th>DATE OF RELIEVING</th>";
echo "</tr>";

if (count($relieved_records) > 0) {
    $rr_sl = 1;
    foreach ($relieved_records as $rr) {
        $doj_formatted = ($rr['doj'] !== '-' && $rr['doj'] !== 'N/A') ? date('d.m.y', strtotime($rr['doj'])) : '';
        $dor_formatted = ($rr['dor'] !== '-' && $rr['dor'] !== 'N/A') ? 'DOR: ' . date('d.m.y', strtotime($rr['dor'])) : '';

        echo "<tr>";
        echo "<td style='text-align: center; height: 25px;'>" . $rr_sl++ . "</td>";
        echo "<td>" . htmlspecialchars($rr['name']) . "</td>";
        echo "<td style='text-align: center;'>" . $doj_formatted . "</td>";
        echo "<td style='text-align: left;'>" . $dor_formatted . "</td>";
        echo "</tr>";
    }
} else {
    echo "<tr><td colspan='4' style='text-align: center; height: 25px;'>No Relieving Employees found</td></tr>";
}
echo "</table><br><br>";

echo "</td>"; // Right Column avasanikkunnu
echo "</tr>";
echo "</table>"; // Master Layout Table avasanikkunnu


// =========================================================================
// 🟢 NEW: DAILY ATTENDANCE DETAILED TABLE (Triggered for EVERY Date in Range)
// =========================================================================

foreach ($dates as $date) {
    $day_number = date('j', strtotime($date));
    $formatted_date = date('d-m-Y', strtotime($date));

    // Showroom & Promoters vechu data group panrom
    $grouped_details = [];
    $promoter_details = []; // ⭐️ NEW: Separate array for Promoters

    if (isset($daily_details[$date])) {
        foreach ($daily_details[$date] as $detail) {
            // Check if role contains 'promoter' (case-insensitive)
            if (stripos($detail['role'], 'promoter') !== false) {
                $promoter_details[] = $detail;
            } else {
                $grouped_details[$detail['showroom']][] = $detail;
            }
        }
    }

    if (!empty($grouped_details) || !empty($promoter_details)) {
        echo "<br><br>";
        // Pakkathu pakkathula (Side-by-Side) table kondu vara outer table create panrom
        echo "<table border='0' cellpadding='0' cellspacing='0'><tr>";

        // 1️⃣ Loop through Regular Showroom Employees
        foreach ($grouped_details as $sr_name => $employees) {
            echo "<td valign='top'>";
            echo "<table border='1' cellpadding='3' cellspacing='0'>";

            $display_sr = strtoupper($sr_name);
            // Header title-la Showroom name-um add aagirukkum for clarity
            echo "<tr><td colspan='7' style='font-family: sans-serif; font-size: 16px; font-weight: bold; background-color: #d9edf7; text-align: center;'>DAILY ATTENDANCE - {$formatted_date} ({$display_sr})</td></tr>";

            // Exact columns from your image
            echo "<tr style='background-color: #f2f2f2; font-weight: bold;'>";
            echo "<th>Sl.No</th>";
            echo "<th>Salesman Name</th>";
            echo "<th>Role</th>";
            echo "<th>Showroom</th>";
            echo "<th>{$day_number}</th>";
            echo "<th>In time</th>";
            echo "<th>out time</th>";
            echo "</tr>";

            $d_sl = 1;
            foreach ($employees as $detail) {
                // Formatting times to readable AM/PM format, empty if no record
                $in_val = !empty($detail['in_time']) ? date('h:i A', strtotime($detail['in_time'])) : '';
                $out_val = !empty($detail['out_time']) ? date('h:i A', strtotime($detail['out_time'])) : '';
                $status = $detail['status'];

                echo "<tr>";
                echo "<td style='text-align: center;'>" . $d_sl++ . "</td>";
                echo "<td>{$detail['name']}</td>";
                echo "<td>{$detail['role']}</td>";
                echo "<td>{$detail['showroom']}</td>";

                // Status column with explicit colors matching your image
                if ($status === 'A') {
                    echo "<td style='color: red; font-weight: bold; text-align: center;'>A</td>";
                } elseif ($status === 'M/O') {
                    echo "<td style='color: #ff8c00; font-weight: bold; text-align: center;'>M/O</td>";
                } elseif ($status === 'N/A') {
                    echo "<td style='background-color: #ffcccc; color: #cc0000; font-weight: bold; text-align: center;'>N/A</td>";
                } elseif ($status === 'Holiday') {
                    echo "<td style='background-color: #ffffcc; font-weight: bold; text-align: center;'>Holiday</td>";
                } else {
                    echo "<td style='text-align: center;'>{$status}</td>";
                }

                echo "<td style='text-align: center; mso-number-format:\"\@\";'>{$in_val}</td>";
                echo "<td style='text-align: center; mso-number-format:\"\@\";'>{$out_val}</td>";
                echo "</tr>";
            }

            echo "</table>";
            echo "</td>";

            // Oru showroom table-kum innoru table-kum idaiyila spacing
            echo "<td style='width: 30px;'>&nbsp;</td>";
        }

        // 2️⃣ ⭐️ NEW: Separate Promoter Table Generation
        if (!empty($promoter_details)) {
            echo "<td valign='top'>";
            echo "<table border='1' cellpadding='3' cellspacing='0'>";

            echo "<tr><td colspan='6' style='font-family: sans-serif; font-size: 16px; font-weight: bold; background-color: #dff0d8; text-align: center;'>DAILY ATTENDANCE - {$formatted_date} (PROMOTERS)</td></tr>";

            // Requested specific columns for Promoter Table
            echo "<tr style='background-color: #f2f2f2; font-weight: bold;'>";
            echo "<th>Sl.No</th>";
            echo "<th>Salesman Name</th>";
            echo "<th>Role</th>";
            echo "<th>Showroom</th>";
            echo "<th>in time</th>";
            echo "<th>out time</th>";
            echo "</tr>";

            $p_sl = 1;
            foreach ($promoter_details as $detail) {
                $in_val = !empty($detail['in_time']) ? date('h:i A', strtotime($detail['in_time'])) : '';
                $out_val = !empty($detail['out_time']) ? date('h:i A', strtotime($detail['out_time'])) : '';

                echo "<tr>";
                echo "<td style='text-align: center;'>" . $p_sl++ . "</td>";
                echo "<td>{$detail['name']}</td>";
                echo "<td>{$detail['role']}</td>";
                echo "<td>{$detail['showroom']}</td>";
                echo "<td style='text-align: center; mso-number-format:\"\@\";'>{$in_val}</td>";
                echo "<td style='text-align: center; mso-number-format:\"\@\";'>{$out_val}</td>";
                echo "</tr>";
            }

            echo "</table>";
            echo "</td>";
        }

        echo "</tr></table>"; // Outer side-by-side table ends
    }
}

$conn->close();
?>
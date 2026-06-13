# Backend Deployment Instructions

This folder contains the updated PHP scripts for the SLFM Salesman App with **Device Locking** and **Proxy Detection** features.

## Files
1. **`login.php`**: Handles user authentication and binds the device ID to the salesman on their first login.
2. **`attendance.php`**: Handles attendance marking (In/Out/Re-entry) and checks if the device matches the bound device. If not, it flags the record as "Suspicious" (Proxy).

## Deployment Steps
1. **Upload Files**: Upload `login.php` and `attendance.php` to your server's API directory (e.g., `slfm_api/`).
2. **Database Connection**: Ensure `db_connect.php` exists in the same directory.
   - If your `db_connect.php` is in a different location, update the `require 'db_connect.php';` line in both files.
3. **Permissions**: Ensure the `uploads/attendance/` directory has write permissions (777) so images can be saved.

## Features Implemented
- **Device Binding (Locking)**: 
  - When a salesman logs in for the first time with these new scripts, their `primary_device_id` will be saved in the database.
- **Proxy Detection**:
  - If a salesman tries to mark attendance from a different mobile, the system will **ALLOW** it (Battery Dead Policy) but mark it with `is_proxy_device = 1` in the database.
  - You can view this flag in your Admin Panel to penalize proxy attendance.
- **Anti-Spoofing (Flash Effect)**:
  - This is handled by the updated App (Frontend). The backend simply receives the photo.

## Database Requirements
Ensure your tables have the following columns (as per your schema):
- **`salesmen` table**: `primary_device_id`, `primary_device_model`, `is_device_locked`.
- **`attendance` table**: `device_id_used`, `device_model_used`, `is_proxy_device`.

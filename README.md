# 🛍️ SLFM Enterprise Sales Force Automation & POS App

A modern Flutter-based mobile application for **SLFM (Sri Lakshmi Fashion Mart)** attendance and workforce management. Built to streamline daily operations including attendance tracking, customer notes, POS billing, and real-time reporting.

---

## ✨ Features

### 📋 Attendance Management
- **Clock In / Clock Out** with selfie verification & GPS location
- **Re-entry support** — resume work within 1 hour of clock-out (Server-controlled time constraints)
- Watermarked attendance photos (Name, Showroom, Time)
- Real-time attendance status sync via **Firebase Firestore**
- Fault-tolerant offline queueing ensures attendance data is synced even after network loss.

### 💰 Billing & POS Operations
- High-speed POS scanning with offline fallback.
- Centralized real-time bill counters across multiple branches.
- Auto-sync architecture that handles duplicate offline records seamlessly.

### 🚶 Gamification & Leaderboard
- **Top 3 Podium Dashboard**: Animated real-time performance leaderboard (Lottie + Firebase RTDB).
- Live sales tracking and gamified target achievements.

### 📦 Stock Checking & Damage Reporting
- Real-time stock lookups, OS code scanning, and price adjustment tracking.
- Photo-verified damage reporting with automatic image compression and upload.

### 🚶 Walking Customer Notes
- Log walking (walk-in) customer interactions
- Track pending vs billed customers
- Offline-first with **SQLite** local storage + cloud sync

### 💬 Leave Management
- Apply for leave with reason & type selection
- Real-time approval/rejection status via Firestore listeners
- Holiday calendar integration

### 📊 Dashboard
- Live attendance status indicator
- Walking customer statistics
- Skeleton loading for smooth UX
- Pull-to-refresh sync

### ⚙️ Settings & More
- Dark / Light theme support
- In-app Privacy Policy
- App version check & forced update support
- Maintenance mode (Full / Partial) controlled via Firestore

---

## 🔒 Enterprise Security & Architecture

This application is hardened with bank-grade security protocols:
- **FreeRASP Integration**: Detects and blocks Rooting, Jailbreaking, and Hooking frameworks.
- **SSL Certificate Pinning**: Prevents Man-in-the-Middle (MITM) attacks globally.
- **Firebase App Check**: Secures backend cloud functions and database access.
- **Public Repository Sanitization**: This codebase has been sanitized for public portfolio showcase. All hardcoded production credentials, API URLs, and backend PHP/SQL configurations have been extracted into secure environment variables (`.env`, `db_config.php`) and dynamic build injections (`--dart-define`).

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| **Framework** | Flutter (Dart) |
| **State Management** | Provider + StreamSubscriptions |
| **Backend API** | PHP (Custom REST endpoints on Hostinger) + Firebase Cloud Functions |
| **Database (Server)** | MySQL / MariaDB |
| **Database (Local)** | SQLite (sqflite) + Hive (NoSQL for offline queues) |
| **Auth & Realtime** | Firebase Auth, Firestore, Firebase Realtime Database |
| **Storage** | Firebase Storage |
| **Location** | Geolocator + Google Maps |
| **Security** | FreeRASP, SSL Pinning, Flutter Secure Storage |

---

## 🚀 Version Update System (Split-per-ABI Support)

The app handles Play Store's `split-per-abi` versioning (+1000 for v7a, +2000 for v8a) using a **Normalization Logic**.

### 1. Build Number Normalization (`% 1000`)
To ensure compatibility between App Bundles (base version) and Split APKs (offset versions), the app normalizes the `versionCode`.
- **Logic**: `currentBuildBase = actualVersionCode % 1000`
- **Result**: `30`, `1030`, and `2030` are all treated as base version **30**.
- **File**: `lib/core/services/version_check_service.dart`

### 2. Backend Config (`api/apps/salesman/salesman_version.json`)
- **JSON Format**:
  ```json
  {
    "version": "4.3.0",
    "build_number": 30,
    "mandatory": false,
    "is_global": true
  }
  ```
- **Note**: Always use the **base build number** (e.g., 30, 31, 32) in this JSON.

### 3. Server-Side Logic (`api/check_version.php`)
- **ABI Detection**: Detects `v7a` or `v8a` from the app request.
- **Dynamic APK Selection**: Automatically provides the correct download link for the specific phone architecture.

---

## 📁 Project Structure

```text
lib/
├── core/                  # App config, themes, API URLs, constants
│   ├── database/          # SQLite local DB helper
│   └── services/          # HTTP client, version check, secure storage
├── presentation/          # UI Screens
│   ├── dashboard/         # Main dashboard + widgets
│   ├── attendance_screen/ # Clock in/out screen (Selfie + GPS)
│   ├── walking_notes/     # Walking customer management
│   ├── damage/            # Damage report screen
│   └── setting/           # Settings & Privacy Policy
│   └── login_screen/      # Login screen
├── routes/                # App route definitions
├── services/              # Secure storage service
├── widgets/               # Shared/reusable widgets
└── main.dart              # App entry point
```

---

## 🚀 Getting Started & Configuration

### Prerequisites
- Flutter SDK `>=3.10.0`
- Android Studio / VS Code
- Due to security sanitization, you must inject your own API environments using `--dart-define` to build the app successfully.

### Build Command
If building from terminal, inject the required environment variables:
```bash
flutter build apk \
  --dart-define=BASE_URL=your_api_url \
  --dart-define=FIREBASE_URL=your_firebase_function_url \
  --dart-define=ADMIN_PASSWORD=your_secure_password
```
*(Note: If testing locally via VS Code, use the provided `launch.json` configuration.)*

---

## 👨‍💻 Developer

**Vasanth** — Full-Stack Mobile Developer  
📧 vasanthvarman0@gmail.com | 🐙 [github.com/vasanth5545](https://github.com/vasanth5545)

---

## 📄 License

This project is proprietary software originally built for **Sri Lakshmi Fashion Mart (SLFM)**.  
The source code provided here is sanitized and intended strictly for portfolio demonstration purposes.
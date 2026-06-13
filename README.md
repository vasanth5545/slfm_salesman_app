# 🛍️ SLFM Attendance App

A modern Flutter-based mobile application for **SLFM (Sri Lakshmi Fashion Mart)** attendance and workforce management. Built to streamline daily operations including attendance tracking, customer notes, and real-time reporting.

---

## ✨ Features

### 📋 Attendance Management
- **Clock In / Clock Out** with selfie verification & GPS location
- **Re-entry support** — resume work within 1 hour of clock-out
- Watermarked attendance photos (Name, Showroom, Time)
- Real-time attendance status sync via **Firebase Firestore**

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

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| **Framework** | Flutter (Dart) |
| **State Management** | setState + StreamSubscription |
| **Backend API** | PHP (REST API on Hostinger) |
| **Database (Server)** | MariaDB / MySQL |
| **Database (Local)** | SQLite (sqflite) |
| **Auth & Realtime** | Firebase Auth, Firestore, RTDB |
| **Storage** | Firebase Storage |
| **Location** | Geolocator + Google Maps |
| **Security** | Flutter Secure Storage, App Check |

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

## 🚀 Getting Started

### Prerequisites
- Flutter SDK `>=3.0.0`
- Android Studio / VS Code
- Firebase project configured (`google-services.json`)

### Installation

1. Clone the repository to your local machine.
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the app:
   ```bash
   flutter run
   ```

---

## 🔧 Configuration

1. Place `google-services.json` in `android/app/`
2. Update API base URL in `lib/core/app_export.dart`
3. Configure Firebase App Check debug tokens for emulator testing

---

## 👨‍💻 Developer

**Vasanth** — Full Stack Developer  
📧 www.m.vasanth5545@gmail.com

---

## 📄 License

This project is proprietary software owned by **Sri Lakshmi Fashion Mart (SLFM)**.  
All rights reserved. Unauthorized distribution is prohibited.

a35d819
a35d819
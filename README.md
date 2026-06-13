# 🛍️ SLFM Enterprise Sales Force Automation & POS App

A comprehensive, offline-first Flutter mobile application developed for **Sri Lakshmi Fashion Mart (SLFM)** to streamline enterprise workforce management, POS billing operations, stock checking, and gamified performance tracking.

---

## ✨ Key Features

### 📋 Attendance & Workforce Management
- **Secure Clock In / Clock Out** with selfie verification & background GPS tracking.
- **Dynamic Re-entry System** — Server-controlled time constraints to resume work after breaks.
- Watermarked attendance proofs (Name, Showroom, Timestamp).
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
| **Backend API** | PHP (Custom REST endpoints) + Firebase Cloud Functions |
| **Database (Server)** | MySQL / MariaDB |
| **Database (Local)** | SQLite (sqflite) + Hive (NoSQL for offline queues) |
| **Auth & Realtime** | Firebase Auth, Firestore, Firebase Realtime Database |
| **Security** | FreeRASP, SSL Pinning, Flutter Secure Storage |

---

## 🚀 Running the Project

### Prerequisites
- Flutter SDK `>=3.10.0`
- Due to security sanitization, you must inject your own API environments using `--dart-define` to build the app successfully.

### Build Command
```bash
flutter build apk \
  --dart-define=BASE_URL=your_api_url \
  --dart-define=FIREBASE_URL=your_firebase_function_url \
  --dart-define=ADMIN_PASSWORD=your_secure_password
```

---

## 👨‍💻 Developer

**Vasanth** — Full-Stack Mobile Developer  
📧 vasanthvarman0@gmail.com | 🐙 [github.com/vasanth5545](https://github.com/vasanth5545)

---

## 📄 License

This project is proprietary software originally built for **Sri Lakshmi Fashion Mart (SLFM)**.  
The source code provided here is sanitized and intended strictly for portfolio demonstration purposes.
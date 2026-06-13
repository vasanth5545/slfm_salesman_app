# Privacy Policy for SLFM Attendance app

**Effective Date:** April 26, 2026

Welcome to the **SLFM Attendance app**. We are dedicated to protecting your privacy and ensuring the security of your professional data. This Privacy Policy clarifies our practices regarding the collection, use, and protection of information within our mobile application ("the App"), which is exclusively designed for employees and authorized sales personnel of **Sri Lakshmi Furniture Mart (SLFM)**.

This App is an enterprise tool involving operational tracking and professional authentication. **By using the App, you consent to the data practices described in this policy.**

---

## 1. Information We Collect

To facilitate core operational workflows, attendance tracking, and sales management, the App collects the following data:

### 1.1 Location Data (Precision GPS)
- **What we collect:** High-precision location data (latitude and longitude) in real-time. This occurs both in the **foreground** (while the app is open) and in the **background** (while the app is closed or not in use).
- **Status Logging:** The app actively logs location events, including timestamps of when location services are turned off, when permissions are revoked, or when battery optimization disrupts tracking. This data is visible to administrators to ensure compliance during duty hours.
- **Why we collect it:** Background tracking is a mandatory enterprise requirement to:
  - Log travel routes during duty hours for field visits.
  - Geofence-verify your presence at authorized showroom locations for clock-in and clock-out procedures.
- **Impact of Denial:** Since location verification is tied to payroll and attendance, denying this permission will disable the App's core functionality.

### 1.2 Camera and Biometrics
- **What we collect:** Live images captured exclusively through the App's camera.
- **Why we collect it:** 
  - **Identity Verification:** A mandatory live selfie is required for every clock-in, clock-out, and re-entry to prevent identity fraud.
  - **Operational Documentation:** Uploading photos of damaged inventory or customer billing proofs.
- **Data Protection:** We do **not** access your device's photo gallery without permission. All images are watermarked with metadata (Name, Showroom, Timestamp) and stored securely on Firebase Cloud Storage.

### 1.3 Device, Battery Optimization, and Foreground Services
- **Foreground Services:** The App requires continuous background execution (Foreground Service) to actively sync location and attendance data during duty hours without interruption.
- **Battery Optimization:** The App requires users to ignore or disable battery optimizations. This ensures the background tracking service is not killed by the Android OS while the salesman is in the field.
- **What we collect:** Unique Device Identifiers (Device ID, Model, OS version), Battery status, and Network connectivity logs.
- **Security Logic:** We utilize **Runtime Application Self-Protection (RASP)** via the FreeRASP SDK to detect rooted devices, emulators, or screen recording attempts to protect sensitive company data.

### 1.4 Phone Call Management
- **What we collect:** The App utilizes the phone's dialer function.
- **Why we collect it:** To allow salesmen to directly contact the showroom office, management, or assigned customers from within the App's interface for professional inquiries.

### 1.5 Push Notifications
- **What we collect:** Device tokens for Firebase Cloud Messaging (FCM).
- **Why we collect it:** To send critical operational alerts, attendance reminders, and management announcements directly to your device.

---

## 2. Internal Data Transparency & Leaderboards

As a performance-driven enterprise application, certain data is shared **internally** among SLFM employees:
- **Leaderboard Performance:** Your name, showroom branch, and total billed count (performance metric) are visible to your colleagues and management on the "Top 3 Champions" leaderboard and rankings.
- **Profile Customization:** Your chosen avatar animal and profile photo are visible to the team to foster a professional community environment.

---

## 3. Remote Attendance & Work Modes

The App supports advanced work modes:
- **Remote Attendance Toggle:** The management may enable/disable the ability to clock in remotely based on your professional assignment.
- **Syncing:** Any changes to your status are synced in real-time between the PHP backend and Firebase Realtime Database.

---

## 4. How We Secure and Store Your Data

We employ industry-leading security protocols:
- **Encryption:** Sensitive tokens are stored using **AES-256 equivalent encryption** via `EncryptedSharedPreferences` on Android and Keychain on iOS.
- **Cloud Infrastructure:** All data is hosted on **Google Firebase** and professional MariaDB servers, protected by robust App Check verification and security rules.
- **Transit Security:** All communication between the App and servers is strictly enforced over **HTTPS (TLS 1.2+)**.

---

## 5. Data Retention and Deletion

- **Retention:** Professional data (attendance history, billing logs) is retained for the duration of your employment plus a minimum of 7 years for auditing and tax compliance.
- **Account Termination:** Upon resignation or termination, access to the App is immediately revoked. Data deletion requests must be routed through the SLFM HR/IT Department.

---

## 6. Third-Party Services

We integrate with trusted providers:
- **Google Play Services:** For location accuracy and core system features.
- **Google Firebase:** For authentication, real-time database, and crash analytics.
- **Google Fonts:** For typography and UI rendering.

---

## 7. Contact Us

For questions regarding your data or this policy, please contact the SLFM IT Department:

**IT Administrator:** [vasanthvarman0@gmail.com](mailto:vasanthvarman0@gmail.com)  
**Registered Office:** SLFM, New Street, Mannargudi, Thiruvarur, Tamil Nadu, India.

---
*© 2026 Sri Lakshmi Furniture Mart. All Rights Reserved.*

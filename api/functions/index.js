const { onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const mysql = require("mysql2/promise");
const moment = require("moment-timezone");

admin.initializeApp();
const db = admin.firestore();
const TIMEZONE = "Asia/Kolkata";

// .env file ninda database credentials tegedukolluttade (Secure method)
const dbConfig = {
  host: process.env.DB_HOST || "localhost",
  user: process.env.DB_USER || "root",
  password: process.env.DB_PASSWORD || "",
  database: process.env.DB_NAME || "test_db",
  waitForConnections: true,
  connectionLimit: 15,
  queueLimit: 0,
};
const pool = mysql.createPool(dbConfig);

// .env file ninda Hostinger URL mattu API Key tegedukolluttade
const HOSTINGER_URL = process.env.HOSTINGER_UPLOAD_URL || "https://dummy-company.com/api/upload_image.php";
const UPLOAD_SECRET_KEY = process.env.UPLOAD_SECRET_KEY || "dummy_secret_key";

function getDistanceInMeters(lat1, lon1, lat2, lon2) {
  if (!lat1 || !lon1 || !lat2 || !lon2) return 99999;
  const earthRadius = 6371000;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) + Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return Math.round(earthRadius * c);
}

// 🔥 FIX: Securitygagi Secret Key yondige Image uploader
async function uploadToHostinger(base64Image, showroomName, filename, todayStr) {
  if (!base64Image) return null;

  try {
    const payload = {
      image: base64Image,
      showroom: showroomName,
      filename: filename,
      date: todayStr,
      secret_key: UPLOAD_SECRET_KEY // PHP backend gagi Security key
    };

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 15000);

    const response = await fetch(HOSTINGER_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      signal: controller.signal
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      console.error("Hostinger HTTP Error:", response.status, response.statusText);
      return null;
    }

    const result = await response.json();
    if (result.status === 'success') {
      return result.path;
    } else {
      console.error("Hostinger PHP Error:", result);
      return null;
    }
  } catch (err) {
    console.error("Upload error/Timeout:", err);
    return null;
  }
}

exports.login = onRequest({ cors: true, enforceAppCheck: false }, async (req, res) => {
  const data = req.method === "POST" ? req.body : req.query;
  const { salesman_id, password, device_id, device_model } = data;

  if (!salesman_id || !password) return res.json({ status: "error", message: "ID mattu Password agathya" });
  const sid = salesman_id.trim();

  try {
    const docRef = db.collection("salesmen").doc(sid);
    const docSnap = await docRef.get();

    if (!docSnap.exists) return res.json({ status: "error", message: "Tappada ID" });

    const row = docSnap.data();
    if (row.status !== "Active") return res.json({ status: "error", message: "Account suspend agide" });

    if (password === row.password_hash) {
      const updateData = { last_login: admin.firestore.FieldValue.serverTimestamp() };
      if (device_id && !row.primary_device_id) {
        updateData.primary_device_id = device_id;
        updateData.primary_device_model = device_model;
        updateData.is_device_locked = "1";
      }
      await docRef.update(updateData);
      const customToken = await admin.auth().createCustomToken(sid);
      return res.json({
        status: "success",
        message: "Login yashasviyagide",
        token: customToken,
        data: {
          id: row.id || sid,
          name: row.name,
          salesman_id: row.salesman_id || row.id || sid,
          showroom_name: row.showroom_name || "Main Branch",
          showroom_address: row.showroom_address || "",
        },
      });
    } else {
      return res.json({ status: "error", message: "Tappada password" });
    }
  } catch (err) {
    console.error(err);
    return res.json({ status: "error", message: err.toString() });
  }
});

exports.location_update = onRequest({ cors: true, enforceAppCheck: false }, async (req, res) => {
  return res.json({ status: "error", message: "DEPRECATED" });
});

exports.billing = onRequest({ cors: true, enforceAppCheck: false }, async (req, res) => {
  const data = req.method === "POST" ? req.body : req.query;
  const { action, salesman_id, customer_name, bill_amount, items } = data;
  try {
    const sid = (salesman_id || "").trim();
    if (action === "create_bill") {
      const billData = { salesman_id: sid, customer_name, bill_amount: parseFloat(bill_amount), items: items || [], created_at: admin.firestore.FieldValue.serverTimestamp() };
      const docRef = await db.collection("bills").add(billData);
      return res.json({ status: "success", message: "Bill srishtisalagide", bill_id: docRef.id });
    }
    return res.json({ status: "error", message: "Tappada action" });
  } catch (err) {
    return res.json({ status: "error", message: "DB Error" });
  }
});

// ============================================================================
// 4. ATTENDANCE API
// ============================================================================
exports.attendance = onRequest({ cors: true, enforceAppCheck: false }, async (req, res) => {
  const data = req.method === "POST" ? req.body : req.query;
  const { action, lat, lng, device_id, device_model } = data;

  const image_base64 = data.selfie_url || data.image_base64 || "";
  const salesman_id = data.salesman_id;

  try {
    const sid = (salesman_id || "").trim();
    if (!sid) return res.json({ status: "error", message: "Salesman ID agathya" });

    const now = moment().tz(TIMEZONE);
    const todayStr = now.format("YYYY-MM-DD");
    const currentTimeStr = now.format("HH:mm:ss");

    const docId = `${todayStr}_${sid}`;
    const docRef = db.collection("attendance").doc(docId);

    if (action === "get_history" || action === "get_summary") {
      return res.json({ status: "error", message: `DEPRECATED` });
    }

    const sRef = db.collection("salesmen").doc(sid);
    const sSnap = await sRef.get();
    if (!sSnap.exists) return res.json({ status: "error", message: "Salesman sigilla" });
    const salesman = sSnap.data();

    const shiftStart = salesman.shift_start_time || "09:30:00";
    const shiftEnd = salesman.shift_end_time || null;
    const customLateCutoff = salesman.custom_late_cutoff || null;
    const gender = (salesman.gender || "male").toLowerCase();
    const primaryDeviceId = salesman.primary_device_id || "";

    const allowLateEntry = salesman.allow_late_entry === true || salesman.allow_late_entry === "true" || parseInt(salesman.allow_late_entry || "0") === 1;

    const lateCutoffTime = customLateCutoff || "10:00:59";
    const leaveEntryCutoff = "15:00:59";
    const morningHalfOutStart = "14:30:00";
    const morningHalfOutEnd = "15:00:00";
    const standardExitTime = gender === "female" ? "20:00:00" : "21:00:00";
    const fullDayExitStart = (shiftEnd && shiftEnd < standardExitTime) ? shiftEnd : standardExitTime;
    const RESUME_LIMIT = 1;
    const ALLOWED_RADIUS = 100;

    let isProxyDevice = 0;
    const deviceIdUsed = (device_id || "").trim();
    const deviceModelUsed = (device_model || "").trim();
    if (primaryDeviceId && deviceIdUsed && primaryDeviceId !== deviceIdUsed) {
      isProxyDevice = 1;
    }

    let isOutOfLocation = 0;
    let locationDistance = 0;
    let adminApproval = null;
    const showroomName = salesman.showroom_name || "Main Branch";

    if (action === "clock_in" || action === "clock_out") {
      let shLat = null, shLng = null;
      try {
        const shSnap = await db.collection("showrooms").where("name", "==", showroomName).limit(1).get();
        if (!shSnap.empty) {
          const shData = shSnap.docs[0].data();
          shLat = parseFloat(shData.latitude);
          shLng = parseFloat(shData.longitude);
        }
      } catch (e) { console.warn("Showroom fetch error:", e.message); }

      const userLat = parseFloat(lat);
      const userLng = parseFloat(lng);

      if (userLat && userLng && shLat && shLng) {
        locationDistance = getDistanceInMeters(userLat, userLng, shLat, shLng);
        if (locationDistance > ALLOWED_RADIUS) {
          isOutOfLocation = 1;
          adminApproval = "Pending";
        }
      } else if (!userLat || !userLng) {
        isOutOfLocation = 1;
        locationDistance = 99999;
        adminApproval = "Pending";
      }
    }

    const safeName = (salesman.name || sid).replace(/[^A-Za-z0-9\-]/g, "_");
    const timeStrFile = now.format("YYYY_MM_DD_HH_mm_ss");

    if (action === "clock_in") {
      const attSnap = await docRef.get();

      if (attSnap.exists) {
        const existing = attSnap.data();
        const hasClockedOut = !!existing.clock_out_time;
        const hasClockedIn = !!existing.clock_in_time;
        const existingStatus = (existing.status || "").toLowerCase();

        if (hasClockedIn && !hasClockedOut && existingStatus !== "absent" &&
          existingStatus !== "leave" && existingStatus !== "on leave") {
          return res.json({ status: "error", message: "Ivattu agale clock in madidira! Prastuta status: " + existing.status });
        }

        if (hasClockedIn && hasClockedOut) {
          const lastOutTime = existing.clock_out_time.toDate ? existing.clock_out_time.toDate() : new Date(existing.clock_out_time);
          const diffMinutes = (now.toDate().getTime() - lastOutTime.getTime()) / (1000 * 60);
          const currentResumes = parseInt(existing.resume_count || "0");

          if (diffMinutes > 60) {
            return res.json({ status: "error", message: "Break 1 gantegekintha hecchagide. Re-entry anumatisi illa." });
          }
          if (currentTimeStr > "18:00:00" && !allowLateEntry) {
            return res.json({ status: "error", message: "Mugidide! Ivattu in time mattu out time hakidira! Nale matte prayatnisi. 🙏" });
          }
          if (currentResumes >= RESUME_LIMIT) {
            return res.json({ status: "error", message: `Quota hecchagide: Neevu agale break re-entry (${RESUME_LIMIT}) bari madidira.` });
          }

          let newStatus = "Present";
          if (!allowLateEntry) {
            const origInTime = existing.clock_in_time.toDate ? moment(existing.clock_in_time.toDate()).tz(TIMEZONE).format("HH:mm:ss") : moment(existing.clock_in_time).tz(TIMEZONE).format("HH:mm:ss");
            if (origInTime > leaveEntryCutoff) { newStatus = "Leave"; }
            else if (origInTime > lateCutoffTime) { newStatus = "Half Day"; }
          } else {
            newStatus = "Half Day"; 
          }

          let reentryImageUrl = null;
          if (image_base64) {
            const filename = `${safeName}_${sid}_${timeStrFile}_REENTRY.jpg`;
            reentryImageUrl = await uploadToHostinger(image_base64, showroomName, filename, todayStr);
          }

          const finalAdminApproval = isOutOfLocation === 1 ? "Pending" : (existing.admin_approval || null);

          await docRef.update({
            break_out_time: existing.clock_out_time,
            break_out_selfie_url: existing.clock_out_selfie_url || existing.out_selfie_url || null,
            clock_out_time: null,
            clock_out_selfie_url: null,
            out_selfie_url: null,
            status: newStatus,
            resume_count: currentResumes + 1,
            reentry_selfie_url: reentryImageUrl,
            reentry_time: admin.firestore.FieldValue.serverTimestamp(),
            device_id_used: deviceIdUsed || null,
            device_model_used: deviceModelUsed || null,
            is_proxy_device: isProxyDevice === 1,
            is_out_of_location: isOutOfLocation.toString(),
            location_distance: locationDistance.toString(),
            admin_approval: finalAdminApproval,
            updated_at: admin.firestore.FieldValue.serverTimestamp()
          });

          const perfData = await calculateAndStorePerformance(sid, todayStr.slice(0, 7));
          const msg = isOutOfLocation === 1 ? "Kelasa munde variside (Out of Location - Pending Admin Approval)." : `Kelasa munde variside (${currentResumes + 1}/${RESUME_LIMIT}). Status: ${newStatus}.`;
          return res.json({ status: "success", message: msg, action: "resume", image_url: reentryImageUrl, performance_data: perfData });
        }
      }

      let status = "Present";
      let isLate = 0;

      if (currentTimeStr > leaveEntryCutoff) {
        if (allowLateEntry) {
          status = "Half Day"; 
          isLate = 1;
        } else {
          return res.json({ status: "error", message: "Login samaya mugidide (3:00 PM). Quota mugidide. Admin annu samparkisi." });
        }
      } else if (currentTimeStr > lateCutoffTime) {
        status = "Half Day";
        isLate = 1;
      } else if (currentTimeStr > shiftStart) {
        isLate = 1;
      }

      let imageUrl = null;
      if (image_base64) {
        const filename = `${safeName}_${sid}_${timeStrFile}_IN.jpg`;
        imageUrl = await uploadToHostinger(image_base64, showroomName, filename, todayStr);
      }

      const targetDateObj = moment.tz(todayStr, "YYYY-MM-DD", TIMEZONE).startOf('day').toDate();

      await docRef.set({
        admin_approval: adminApproval,
        attendance_uid: null,
        clock_in_time: admin.firestore.FieldValue.serverTimestamp(),
        clock_out_selfie_url: null,
        clock_out_time: null,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        date: admin.firestore.Timestamp.fromDate(targetDateObj),
        device_id_used: deviceIdUsed || null,
        device_model_used: deviceModelUsed || null,
        final_out_selfie_url: null,
        is_late: isLate === 1,
        is_out_of_location: isOutOfLocation.toString(),
        is_proxy_device: isProxyDevice === 1,
        is_seen_by_admin: "0",
        late_entry_approved: allowLateEntry, 
        latitude: parseFloat(lat) || null,
        location_distance: locationDistance.toString(),
        longitude: parseFloat(lng) || null,
        modification_reason: null,
        modified_by: null,
        out_latitude: null,
        out_longitude: null,
        reentry_selfie_url: null,
        resume_count: 0,
        salesman_id: sid,
        salesman_name: salesman.name,
        selfie_url: imageUrl,
        showroom_name: showroomName,
        status: status,
        updated_at: admin.firestore.FieldValue.serverTimestamp()
      });

      const perfData = await calculateAndStorePerformance(sid, todayStr.slice(0, 7));
      const outLocMsg = `Nimma location sariyilla. Aadaru neevu ${status} aagi mark madalagide. OK!!`;
      const msg = isOutOfLocation === 1 ? outLocMsg : `Clock In madide (${status})`;

      return res.json({ status: "success", message: msg, image_url: imageUrl, performance_data: perfData });

    } else if (action === "clock_out") {
      const attSnap = await docRef.get();
      if (!attSnap.exists) { return res.json({ status: "error", message: "Ivattu neevu clock in madilla!" }); }

      const existing = attSnap.data();
      if (!existing.clock_in_time || existing.clock_out_time) {
        return res.json({ status: "error", message: "Ivattu neevu clock in madilla athava agale clock out madidira!" });
      }

      let finalStatus = existing.status || "Present";
      const clockInTime = existing.clock_in_time.toDate ? existing.clock_in_time.toDate() : new Date(existing.clock_in_time);
      const inTimeStr = moment(clockInTime).tz(TIMEZONE).format("HH:mm:ss");

      // 🔥 FIX: lowercase status
      let safeStatus = finalStatus.toLowerCase().trim();

      if (safeStatus === "present" || safeStatus === "half day") {
        const afternoonStartVal = "15:00:59";
        if (inTimeStr > afternoonStartVal) {
          if (currentTimeStr < fullDayExitStart) { finalStatus = "Leave"; }
        } else {
          if (currentTimeStr < morningHalfOutStart) { 
              finalStatus = "Leave"; 
          }
          else if (currentTimeStr >= morningHalfOutStart && currentTimeStr <= morningHalfOutEnd) { 
              finalStatus = "Half Day"; 
          }
          else if (currentTimeStr < fullDayExitStart) {
            if (safeStatus === "half day") { 
                finalStatus = "Leave"; 
            } else { 
                finalStatus = "Half Day"; 
            }
          }
        }
      }

      let imageUrl = null;
      if (image_base64) {
        const filename = `${safeName}_${sid}_${timeStrFile}_OUT.jpg`;
        imageUrl = await uploadToHostinger(image_base64, showroomName, filename, todayStr);
      }

      const outIsOut = isOutOfLocation === 1 ? 1 : (existing.is_out_of_location === "1" ? 1 : 0);
      const outDistance = isOutOfLocation === 1 ? locationDistance : (parseInt(existing.location_distance) || 0);
      const outAdminApproval = isOutOfLocation === 1 ? "Pending" : (existing.admin_approval || null);
      const resumeCount = parseInt(existing.resume_count || "0");
      const imageField = resumeCount > 0 ? "final_out_selfie_url" : "clock_out_selfie_url";

      const updateData = {
        clock_out_time: admin.firestore.FieldValue.serverTimestamp(),
        out_latitude: parseFloat(lat) || null,
        out_longitude: parseFloat(lng) || null,
        status: finalStatus,
        is_out_of_location: outIsOut.toString(),
        location_distance: outDistance.toString(),
        admin_approval: outAdminApproval,
        updated_at: admin.firestore.FieldValue.serverTimestamp()
      };
      updateData[imageField] = imageUrl;

      await docRef.update(updateData);

      const msg = isOutOfLocation === 1 ? "Clock Out madide (Out of Location - Pending Approval)" : `Clock Out madide. Status: ${finalStatus}`;
      return res.json({ status: "success", message: msg, final_status: finalStatus, image_url: imageUrl });

    } else if (action === "get_status") {
      const attSnap = await docRef.get();
      if (!attSnap.exists) return res.json({ status: "success", clocked_in: false });
      const d = attSnap.data();
      return res.json({
        status: "success", clocked_in: !!d.clock_in_time, data: {
          ...d,
          resume_count: parseInt(d.resume_count || "0"),
          reentry_selfie_url: d.reentry_selfie_url || null
        }
      });
    }
    return res.json({ status: "error", message: "Tappada action" });
  } catch (err) {
    console.error("Attendance Main Error:", err);
    return res.json({ status: "error", message: "DB Error" });
  }
});

// ============================================================================
// 5. LEAVE API (Firestore Only)
// ============================================================================
exports.leave = onRequest({ cors: true, enforceAppCheck: false }, async (req, res) => {
  const data = req.method === "POST" ? req.body : req.query;
  const { action, salesman_id } = data;

  if (!salesman_id) {
    return res.json({ status: "error", message: "Salesman ID agathya" });
  }

  const todayStr = moment().tz(TIMEZONE).format("YYYY-MM-DD");
  const currentTimeStr = moment().tz(TIMEZONE).format("HH:mm");

  try {
    const sid = salesman_id.trim();

    if (action === "apply" || action === "apply_leave") {
      const { date, type = "Full Day", reason } = data;
      const applyDate = date || data.leave_date;

      if (!applyDate || !reason) {
        return res.json({ status: "error", message: "Dianka mattu karana agathya" });
      }

      if (applyDate < todayStr) {
        return res.json({ status: "error", message: "Hinde hoda dinagalige leave apply madalu sadhyavilla." });
      }

      if (applyDate === todayStr && currentTimeStr >= "10:00") {
        return res.json({ status: "error", message: "Samaya mugidide! 10:00 AM munche apply madi." });
      }

      const monthStartObj = moment.tz(todayStr, "YYYY-MM-DD", TIMEZONE).startOf("month").toDate();
      const monthEndObj = moment.tz(todayStr, "YYYY-MM-DD", TIMEZONE).endOf("month").toDate();

      const leavesSnap = await db.collection("leave_requests")
        .where("salesman_id", "==", sid)
        .where("leave_date", ">=", admin.firestore.Timestamp.fromDate(monthStartObj))
        .where("leave_date", "<=", admin.firestore.Timestamp.fromDate(monthEndObj))
        .get();

      let currentLeaveDays = 0;
      leavesSnap.forEach(doc => {
        const lData = doc.data();
        if (lData.status !== "Rejected" && lData.status !== "Cancelled") {
          if (lData.leave_type === "Full Day") currentLeaveDays += 1.0;
          if (lData.leave_type === "Half Day") currentLeaveDays += 0.5;
        }
      });

      const leaveStatus = currentLeaveDays < 4 ? "Approved" : "Pending";
      const statusMessage = currentLeaveDays < 4 ? "Approved" : "Pending (Awaiting Admin Approval)";

      const firestoreDocId = `${applyDate.replace(/-/g, "_")}_${sid}`;
      const docRef = db.collection("leave_requests").doc(firestoreDocId);
      const docSnap = await docRef.get();

      if (docSnap.exists && docSnap.data().status !== "Rejected" && docSnap.data().status !== "Cancelled") {
        return res.json({ status: "error", message: "Ee dinakke agale leave apply madalagide." });
      }

      const leaveDateTs = admin.firestore.Timestamp.fromDate(moment.tz(applyDate, "YYYY-MM-DD", TIMEZONE).startOf('day').toDate());

      await docRef.set({
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        leave_date: leaveDateTs,
        leave_type: type,
        reason: reason,
        salesman_id: sid,
        status: leaveStatus,
        updated_at: admin.firestore.FieldValue.serverTimestamp()
      });

      const newLeaveValue = type === "Full Day" ? 1.0 : 0.5;
      const newTotal = currentLeaveDays + newLeaveValue;
      const remaining = 4 - newTotal;

      const remainingMsg = remaining > 0 ? ` Remaining: ${remaining.toFixed(1)} days` : " (Limit reached. Further requests need admin approval)";

      return res.json({
        status: "success",
        message: `Leave ${statusMessage}!${remainingMsg}`,
        remaining_days: Math.max(0, remaining)
      });
    }

    else if (action === "get_my_leaves" || action === "get_history") {
      return res.json({
        status: "error",
        message: "DEPRECATED: Mobile app MUST use Firebase Client SDK (cloud_firestore) locally. Cloud Functions GET disabled for cost optimization."
      });
    }

    else if (action === "upgrade_half_leaves") {
      if (currentTimeStr < "15:00") {
        return res.json({ status: "info", message: "Too early - upgrade happens after 3:00 PM" });
      }

      const attDocId = `${todayStr}_${sid}`;
      const attSnap = await db.collection("attendance").doc(attDocId).get();
      if (attSnap.exists && attSnap.data().clock_in_time != null) {
        return res.json({ status: "info", message: "Clock-in sigide — upgrade agathya illa" });
      }

      const leaveDocId = `${todayStr.replace(/-/g, "_")}_${sid}`;
      const leaveRef = db.collection("leave_requests").doc(leaveDocId);
      const leaveSnap = await leaveRef.get();

      if (leaveSnap.exists) {
        const lData = leaveSnap.data();
        if (lData.leave_type === "Half Day" && (lData.status === "Approved" || lData.status === "Pending")) {
          await leaveRef.update({
            leave_type: "Full Day",
            updated_at: admin.firestore.FieldValue.serverTimestamp()
          });
          return res.json({ status: "success", message: "Half Day yannu Full Day ge upgrade madalagide", upgraded: true });
        }
      }
      return res.json({ status: "success", message: "Upgrade madalu Half Day leave illa", upgraded: false });
    }

    else if (action === "cancel_leave" || action === "request_cancellation") {
      const leave_id = data.leave_id;
      const messageReason = data.message || data.reason || "User Cancelled";

      if (!leave_id) return res.json({ status: "error", message: "ID agathya" });

      const docRef = db.collection("leave_requests").doc(leave_id);
      const docSnap = await docRef.get();

      if (docSnap.exists) {
        const leaveData = docSnap.data();
        const leaveDateFormatted = moment(leaveData.leave_date.toDate()).tz(TIMEZONE).format("YYYY-MM-DD");

        if (leaveDateFormatted >= todayStr) {
          await docRef.update({ status: "Cancelled", updated_at: admin.firestore.FieldValue.serverTimestamp() });

          const sSnap = await db.collection("salesmen").doc(sid).get();
          const salesman_name = sSnap.exists ? sSnap.data().name : sid;

          await db.collection("leave_cancel_requests").add({
            salesman_id: sid,
            salesman_name: salesman_name,
            leave_id: leave_id,
            cancel_reason: messageReason,
            created_at: admin.firestore.FieldValue.serverTimestamp()
          });

          return res.json({ status: "success", message: "Leave raddagide mattu hesarinondige save agide!" });
        } else {
          return res.json({ status: "error", message: "Hinde hoda leave raddumadalu sadhyavilla" });
        }
      } else {
        return res.json({ status: "error", message: "Leave sigilla" });
      }
    }

    else if (action === "admin_process_cancel") {
      const { cancel_id, decision } = data;
      if (!cancel_id || !decision) return res.json({ status: "error", message: "Cancel ID mattu Decision agathya" });

      const cancelRef = db.collection("leave_cancel_requests").doc(cancel_id);
      const cancelSnap = await cancelRef.get();
      if (!cancelSnap.exists) return res.json({ status: "error", message: "Cancel request sigilla" });

      const originalLeaveRef = db.collection("leave_requests").doc(cancelSnap.data().leave_id);

      if (decision === "Approve") {
        const batch = db.batch();
        batch.delete(originalLeaveRef);
        batch.delete(cancelRef);
        await batch.commit();
        return res.json({ status: "success", message: "Cancellation anumatislagide: Recordgalannu delete madalagide" });
      } else if (decision === "Reject") {
        await cancelRef.delete();
        return res.json({ status: "success", message: "Cancellation tiraskarisalagide: Cancel request delete madalagide" });
      }
      return res.json({ status: "error", message: "Decision 'Approve' athava 'Reject' agirabeku" });
    }

    return res.json({ status: "error", message: "Tappada action" });
  } catch (err) {
    console.error(err);
    return res.json({ status: "error", message: "DB Error: " + err.message });
  }
});

// ============================================================================
// 17. SCHEDULED AUTO-ABSENT (Runs daily at 10:15 AM IST) ⏰
// ============================================================================
exports.scheduledMarkAbsent = onSchedule({
  schedule: "15 10 * * *",
  timeZone: "Asia/Kolkata",
  retryCount: 1,
}, async (event) => {
  try {
    const now = moment().tz(TIMEZONE);
    const currentTime = now.format("HH:mm:ss");
    const includeToday = currentTime >= "10:00:00";
    const todayStr = now.format("YYYY-MM-DD");

    const RECOVERY_END_DATE = "2026-03-29"; // Give 2 days buffer for safety
    const lookbackDays = (todayStr <= RECOVERY_END_DATE) ? 7 : 0;

    const oldestDateStr = moment().tz(TIMEZONE).subtract(includeToday ? lookbackDays : lookbackDays + 1, "days").format("YYYY-MM-DD");
    const newestDateStr = moment().tz(TIMEZONE).subtract(includeToday ? 0 : 1, "days").format("YYYY-MM-DD");

    const oldestDateObj = moment.tz(oldestDateStr, "YYYY-MM-DD", TIMEZONE).startOf('day').toDate();
    const newestDateObj = moment.tz(newestDateStr, "YYYY-MM-DD", TIMEZONE).endOf('day').toDate();

    console.log(`[scheduledMarkAbsent] Mode: ${lookbackDays === 0 ? 'DAILY EXACT' : '7-DAY RECOVERY'} | Sweep from ${oldestDateStr} to ${newestDateStr}`);

    const salesmenSnap = await db.collection("salesmen").where("status", "==", "Active").get();
    if (salesmenSnap.empty) return;

    const attSnap = await db.collection("attendance")
      .where("date", ">=", admin.firestore.Timestamp.fromDate(oldestDateObj))
      .where("date", "<=", admin.firestore.Timestamp.fromDate(newestDateObj))
      .get();
    const attMap = {};
    attSnap.forEach(doc => attMap[doc.id] = true);

    const leaveSnap = await db.collection("leave_requests")
      .where("leave_date", ">=", oldestDateStr)
      .where("leave_date", "<=", newestDateStr)
      .get();
    const leaveMap = {};
    leaveSnap.forEach(doc => {
      const data = doc.data();
      if (data.status === "Approved") {
        leaveMap[`${data.salesman_id}_${data.leave_date}`] = true;
      }
    });

    const holSnap = await db.collection("holidays")
      .where("holiday_date", ">=", oldestDateStr)
      .where("holiday_date", "<=", newestDateStr)
      .get();
    const holidayMap = {};
    holSnap.forEach(doc => holidayMap[doc.data().holiday_date] = true);

    const datesToProcess = [];
    for (let i = includeToday ? 0 : 1; i <= lookbackDays; i++) {
      datesToProcess.push(moment().tz(TIMEZONE).subtract(i, "days").format("YYYY-MM-DD"));
    }

    const batchOps = [];
    let absentCount = 0, leaveCount = 0;

    for (const sDoc of salesmenSnap.docs) {
      const sid = sDoc.id;
      const sData = sDoc.data();
      const joinDate = sData.created_at ? moment(sData.created_at.toDate ? sData.created_at.toDate() : sData.created_at).tz(TIMEZONE).format("YYYY-MM-DD") : "2000-01-01";

      for (const targetDate of datesToProcess) {
        if (holidayMap[targetDate]) continue;
        if (targetDate < joinDate) continue;

        const attId = `${targetDate}_${sid}`;

        if (!attMap[attId]) {
          const hasLeave = leaveMap[`${sid}_${targetDate}`] || false;

          const targetDateObjToSave = moment.tz(targetDate, "YYYY-MM-DD", TIMEZONE).startOf('day').toDate();

          batchOps.push({
            ref: db.collection("attendance").doc(attId),
            data: {
              admin_approval: null,
              attendance_uid: null,
              clock_in_time: null,
              clock_out_selfie_url: null,
              clock_out_time: null,
              created_at: admin.firestore.FieldValue.serverTimestamp(),
              date: admin.firestore.Timestamp.fromDate(targetDateObjToSave),
              device_id_used: null,
              device_model_used: null,
              final_out_selfie_url: null,
              is_late: false,
              is_out_of_location: "0",
              is_proxy_device: false,
              is_seen_by_admin: "0",
              late_entry_approved: false,
              latitude: null,
              location_distance: "0",
              longitude: null,
              modification_reason: null,
              modified_by: null,
              out_latitude: null,
              out_longitude: null,
              reentry_selfie_url: null,
              resume_count: 0,
              salesman_id: sid,
              salesman_name: sData.name || sid,
              selfie_url: null,
              showroom_name: sData.showroom_name || "Main Branch",
              status: hasLeave ? "On Leave" : "Absent",
              updated_at: admin.firestore.FieldValue.serverTimestamp()
            }
          });
          if (hasLeave) leaveCount++; else absentCount++;
        }
      }
    }

    const BATCH_LIMIT = 450;
    for (let i = 0; i < batchOps.length; i += BATCH_LIMIT) {
      const chunk = batchOps.slice(i, i + BATCH_LIMIT);
      const batch = db.batch();
      chunk.forEach(op => batch.set(op.ref, op.data));
      await batch.commit();
    }

    console.log(`[scheduledMarkAbsent] Batch complete! Absent: ${absentCount}, Leaves: ${leaveCount}`);
  } catch (err) {
    console.error("[scheduledMarkAbsent] Error:", err);
  }
});

// ============================================================================
// PERFORMANCE CALCULATION HELPER 📊
// ============================================================================
async function calculateAndStorePerformance(sid, currentMonth) {
  try {
    const todayMoment = moment().tz(TIMEZONE);
    const currentDate = todayMoment.format("YYYY-MM-DD");
    const currentDay = todayMoment.date();
    const currentWeekStart = todayMoment.clone().startOf('isoWeek').format("YYYY-MM-DD");
    const currentWeekEnd = todayMoment.clone().endOf('isoWeek').format("YYYY-MM-DD");

    function calculateHours(start, end) {
      if (!start || !end) return 0;
      const t1 = start.toDate ? start.toDate().getTime() : new Date(start).getTime();
      const t2 = end.toDate ? end.toDate().getTime() : new Date(end).getTime();
      return Math.abs(t2 - t1) / 3600000;
    }

    function formatHours(decimalHours) {
      const h = Math.floor(decimalHours);
      const m = Math.floor((decimalHours - h) * 60);
      const s = Math.round((((decimalHours - h) * 60) - m) * 60);
      return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
    }

    const monthStartObj = moment.tz(currentMonth, "YYYY-MM", TIMEZONE).startOf('month').toDate();
    const monthEndObj = moment.tz(currentMonth, "YYYY-MM", TIMEZONE).endOf('month').toDate();

    let total_present = 0, total_half_days = 0, total_leaves_recorded = 0, total_absent = 0;
    let excluded_dates = [];
    let total_hours_month_decimal = 0, weekly_hours_decimal = 0, today_hours_decimal = 0;

    const attSnap = await db.collection("attendance")
      .where("salesman_id", "==", sid)
      .where("date", ">=", admin.firestore.Timestamp.fromDate(monthStartObj))
      .where("date", "<=", admin.firestore.Timestamp.fromDate(monthEndObj))
      .get();

    attSnap.forEach(doc => {
      const row = doc.data();
      if (!row.date) return;
      const dateStr = moment(row.date.toDate ? row.date.toDate() : row.date).tz(TIMEZONE).format("YYYY-MM-DD");
      const inTime = row.clock_in_time || null;
      const outTime = row.clock_out_time || null;
      const statusLower = (row.status || "").toLowerCase().trim();

      if (dateStr !== currentDate && inTime && !outTime) {
        if (statusLower === 'present' || statusLower === 'half day' || statusLower === 'late') {
          excluded_dates.push(dateStr);
          return;
        }
      }

      if (statusLower === 'present' || statusLower === 'late') total_present++;
      else if (statusLower === 'half day') total_half_days++;
      else if (statusLower.includes('leave') || statusLower === 'approved') total_leaves_recorded++;
      else if (statusLower === 'absent' || statusLower.includes('absent')) total_absent++;

      let hours = 0;
      if (inTime && outTime) {
        hours = calculateHours(inTime, outTime);
      } else if (inTime && dateStr === currentDate) {
        hours = calculateHours(inTime, admin.firestore.Timestamp.now());
      }

      total_hours_month_decimal += hours;
      if (dateStr >= currentWeekStart && dateStr <= currentWeekEnd) {
        weekly_hours_decimal += hours;
      }
      if (dateStr === currentDate) {
        today_hours_decimal += hours;
      }
    });

    const holSnap = await db.collection("holidays")
      .where("holiday_date", ">=", `${currentMonth}-01`)
      .where("holiday_date", "<=", currentDate)
      .get();
    const holidays_count = holSnap.size;

    const leaveSnap = await db.collection("leave_requests")
      .where("salesman_id", "==", sid)
      .where("leave_date", ">=", admin.firestore.Timestamp.fromDate(monthStartObj))
      .where("leave_date", "<=", admin.firestore.Timestamp.fromDate(monthEndObj))
      .where("status", "==", "Approved")
      .get();

    let approved_leave_days = 0;
    leaveSnap.forEach(doc => {
      const lType = doc.data().leave_type;
      if (lType === 'Full Day') approved_leave_days += 1.0;
      else if (lType === 'Half Day') approved_leave_days += 0.5;
    });

    const attendance_leave_count = total_leaves_recorded + total_absent;
    const total_leave_days = Math.max(approved_leave_days, attendance_leave_count);
    const effective_present = total_present + (total_half_days * 0.5);
    const total_worked_days = effective_present;
    const total_days_consumed = total_leave_days + (total_half_days * 0.5);

    let working_days_so_far = currentDay - total_leave_days - holidays_count - excluded_dates.length;
    if (working_days_so_far <= 0) working_days_so_far = 1;

    let attendance_percentage = (effective_present / working_days_so_far) * 100;
    if (attendance_percentage > 100) attendance_percentage = 100;

    const sSnap = await db.collection("salesmen").doc(sid).get();
    const salesman = sSnap.data() || {};
    const sName = salesman.name || sid;
    const sShowroom = salesman.showroom_name || "Main Branch";

    const summaryData = {
      salesman_id: sid,
      salesman_name: sName,
      showroom_name: sShowroom,
      report_month: currentMonth,
      attendance_percentage: parseFloat(attendance_percentage.toFixed(2)),
      attendance_rate: parseFloat(attendance_percentage.toFixed(2)),
      month_hours: formatHours(total_hours_month_decimal),
      week_hours: formatHours(weekly_hours_decimal),
      total_leaves_used: parseFloat(total_days_consumed.toFixed(2)),
      today_working_hours: formatHours(today_hours_decimal),
      total_working_hours: formatHours(total_hours_month_decimal),
      weekly_working_hours: formatHours(weekly_hours_decimal),
      total_days_consumed: parseFloat(total_days_consumed.toFixed(2)),
      total_worked_days: parseFloat(total_worked_days.toFixed(2)),
      total_present,
      total_absent,
      total_half_days,
      total_full_leaves: total_leaves_recorded,
      excluded_dates: excluded_dates,
      leave_details: null,
      last_updated: admin.firestore.FieldValue.serverTimestamp()
    };

    const summaryRef = db.collection("salesman_monthly_performance").doc(`${currentMonth}_${sid}`);
    await summaryRef.set(summaryData, { merge: true });
    return summaryData;
  } catch (err) {
    console.error(`[calculateAndStorePerformance] Error for ${sid}:`, err);
    return null;
  }
}

// ----------------------------------------------------------------------------
// ASYNC TRIGGER: Sync Performance on every attendance update
// ----------------------------------------------------------------------------
exports.onAttendanceWrite = onDocumentWritten("attendance/{docId}", async (event) => {
  const data = (event.data.after ? event.data.after.data() : null) || (event.data.before ? event.data.before.data() : null);
  if (!data || !data.salesman_id) return;
  const currentMonth = moment().tz(TIMEZONE).format("YYYY-MM");
  await calculateAndStorePerformance(data.salesman_id, currentMonth);
});

// ============================================================================
// TEMPORARY CLEANUP SCRIPT
// ============================================================================
exports.cleanupWrongAttendance = onRequest({ cors: true }, async (req, res) => {
  try {
    const snap = await db.collection("attendance").get();
    const batchOps = [];
    let deleteCount = 0;

    snap.forEach(doc => {
      if (doc.id.startsWith("SM")) {
        batchOps.push(doc.ref);
        deleteCount++;
      }
    });

    if (deleteCount === 0) {
      return res.json({ status: "success", message: "Tappada documents sigilla!" });
    }

    const BATCH_LIMIT = 450;
    for (let i = 0; i < batchOps.length; i += BATCH_LIMIT) {
      const chunk = batchOps.slice(i, i + BATCH_LIMIT);
      const batch = db.batch();
      chunk.forEach(ref => batch.delete(ref));
      await batch.commit();
    }

    return res.json({ status: "success", message: `Ottu ${deleteCount} documentgalannu delete madalagide! 🔥` });
  } catch (err) {
    console.error(err);
    return res.json({ status: "error", message: err.toString() });
  }
});
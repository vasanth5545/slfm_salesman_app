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
const HOSTINGER_URL = process.env.HOSTINGER_UPLOAD_URL || "https://skyblue-raven-196549.hostingersite.com/api/upload_image.php";
const UPLOAD_SECRET_KEY = process.env.UPLOAD_SECRET_KEY || "Rajendran_Vasanthvarman_White_Fire_Team_@_SLFM_Team_CEO";

function getDistanceInMeters(lat1, lon1, lat2, lon2) {
    if (!lat1 || !lon1 || !lat2 || !lon2) return 99999;
    const earthRadius = 6371000;
    const dLat = ((lat2 - lat1) * Math.PI) / 180;
    const dLon = ((lon2 - lon1) * Math.PI) / 180;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) + Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return Math.round(earthRadius * c);
}

// 🔥 FIX: Image uploader with Secret Key for security
async function uploadToHostinger(base64Image, showroomName, filename, todayStr) {
    if (!base64Image) return null;

    try {
        const payload = {
            image: base64Image,
            showroom: showroomName,
            filename: filename,
            date: todayStr,
            secret_key: UPLOAD_SECRET_KEY // Security key for PHP backend
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

    if (!salesman_id || !password) return res.json({ status: "error", message: "ID and Password required" });
    const sid = salesman_id.trim();

    try {
        const docRef = db.collection("salesmen").doc(sid);
        const docSnap = await docRef.get();

        if (!docSnap.exists) return res.json({ status: "error", message: "Invalid ID" });

        const row = docSnap.data();
        if (row.status !== "Active") return res.json({ status: "error", message: "Account Suspended" });

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
                message: "Login successful",
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
            return res.json({ status: "error", message: "Incorrect Password" });
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
            return res.json({ status: "success", message: "Bill Created", bill_id: docRef.id });
        }
        return res.json({ status: "error", message: "Invalid action" });
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
        if (!sid) return res.json({ status: "error", message: "Salesman ID Required" });

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
        if (!sSnap.exists) return res.json({ status: "error", message: "Salesman not found" });
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
                    return res.json({ status: "error", message: "Already Clocked In today! Current status: " + existing.status });
                }

                if (hasClockedIn && hasClockedOut) {
                    const lastOutTime = existing.clock_out_time.toDate ? existing.clock_out_time.toDate() : new Date(existing.clock_out_time);
                    const diffMinutes = (now.toDate().getTime() - lastOutTime.getTime()) / (1000 * 60);
                    const currentResumes = parseInt(existing.resume_count || "0");

                    if (diffMinutes > 60) {
                        return res.json({ status: "error", message: "Break exceeded 1 Hour. Re-entry not allowed, but your existing status is maintained." });
                    }
                    if (currentTimeStr > "18:00:00" && !allowLateEntry) {
                        return res.json({ status: "error", message: "முடிந்தது! இன்று In time மற்றும் Out time போட்டு விட்டீர்கள்! நாளை மீண்டும் முயற்சிக்கவும். 🙏" });
                    }
                    if (currentResumes >= RESUME_LIMIT) {
                        return res.json({ status: "error", message: `Quota Exceeded: You have verified Break Re-entry (${RESUME_LIMIT}) times today. Cannot enter again.` });
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
                    const msg = isOutOfLocation === 1 ? "Resumed Work (Out of Location - Pending Admin Approval)." : `Resumed Work (${currentResumes + 1}/${RESUME_LIMIT}). Status: ${newStatus}.`;
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
                    return res.json({ status: "error", message: "Login Time Ended (3:00 PM). Quota Finished. Contact Admin." });
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
            const outLocMsg = `Unga location sariyalla. Ennalum ningal ${status} aayi mark cheythittundu. OK!!`;
            const msg = isOutOfLocation === 1 ? outLocMsg : `Clocked In (${status})`;

            return res.json({ status: "success", message: msg, image_url: imageUrl, performance_data: perfData });

        } else if (action === "clock_out") {
            const attSnap = await docRef.get();
            if (!attSnap.exists) { return res.json({ status: "error", message: "You haven't clocked in today!" }); }

            const existing = attSnap.data();
            if (!existing.clock_in_time || existing.clock_out_time) {
                return res.json({ status: "error", message: "You haven't clocked in today or already clocked out!" });
            }

            let finalStatus = existing.status || "Present";
            const clockInTime = existing.clock_in_time.toDate ? existing.clock_in_time.toDate() : new Date(existing.clock_in_time);
            const inTimeStr = moment(clockInTime).tz(TIMEZONE).format("HH:mm:ss");

            // 🔥 FIX: Check panrathukku munnadi ellathayum small letters-ku maathidunnu
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
                        // 🔥 FIX: lowercase status use cheyth check cheyyunnu
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

            const msg = isOutOfLocation === 1 ? "Clocked Out (Out of Location - Pending Approval)" : `Clocked Out. Status: ${finalStatus}`;
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
        return res.json({ status: "error", message: "Invalid action" });
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
        return res.json({ status: "error", message: "Salesman ID Required" });
    }

    const todayStr = moment().tz(TIMEZONE).format("YYYY-MM-DD");
    const currentTimeStr = moment().tz(TIMEZONE).format("HH:mm");

    try {
        const sid = salesman_id.trim();

        if (action === "apply" || action === "apply_leave") {
            const { date, type = "Full Day", reason } = data;
            const applyDate = date || data.leave_date;

            if (!applyDate || !reason) {
                return res.json({ status: "error", message: "Date and Reason required" });
            }

            if (applyDate < todayStr) {
                return res.json({ status: "error", message: "Kazinja thiyathiyil leave edukkuvan sadhyamalla." });
            }

            if (applyDate === todayStr && currentTimeStr >= "10:00") {
                return res.json({ status: "error", message: "Samayam kazhinju! 10:00 AM-nu munpe apply cheyyuka." });
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
                return res.json({ status: "error", message: "Ee theeyathiyil nerathe thanne leave apply cheythittundu." });
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
                return res.json({ status: "info", message: "Clock-in found — no upgrade needed" });
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
                    return res.json({ status: "success", message: "Half Day upgraded to Full Day", upgraded: true });
                }
            }
            return res.json({ status: "success", message: "No Half Day leaves to upgrade", upgraded: false });
        }

        else if (action === "cancel_leave" || action === "request_cancellation") {
            const leave_id = data.leave_id;
            const messageReason = data.message || data.reason || "User Cancelled";

            if (!leave_id) return res.json({ status: "error", message: "ID required" });

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

                    return res.json({ status: "success", message: "Leave Cancelled & Saved with Name!" });
                } else {
                    return res.json({ status: "error", message: "Cannot cancel past leaves" });
                }
            } else {
                return res.json({ status: "error", message: "Leave not found" });
            }
        }

        else if (action === "admin_process_cancel") {
            const { cancel_id, decision } = data;
            if (!cancel_id || !decision) return res.json({ status: "error", message: "Cancel ID and Decision Required" });

            const cancelRef = db.collection("leave_cancel_requests").doc(cancel_id);
            const cancelSnap = await cancelRef.get();
            if (!cancelSnap.exists) return res.json({ status: "error", message: "Cancel request not found" });

            const originalLeaveRef = db.collection("leave_requests").doc(cancelSnap.data().leave_id);

            if (decision === "Approve") {
                const batch = db.batch();
                batch.delete(originalLeaveRef);
                batch.delete(cancelRef);
                await batch.commit();
                return res.json({ status: "success", message: "Cancellation Approved: Records deleted" });
            } else if (decision === "Reject") {
                await cancelRef.delete();
                return res.json({ status: "success", message: "Cancellation Rejected: Cancel request deleted" });
            }
            return res.json({ status: "error", message: "Decision must be 'Approve' or 'Reject'" });
        }

        return res.json({ status: "error", message: "Invalid action" });
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

// ----------------------------------------------------------------------------
// ASYNC TRIGGER: Sync Attendance & Performance on Leave Status Change
// ----------------------------------------------------------------------------
exports.onLeaveWrite = onDocumentWritten("leave_requests/{docId}", async (event) => {
    const afterData = event.data.after ? event.data.after.data() : null;
    const beforeData = event.data.before ? event.data.before.data() : null;

    if (!afterData || !afterData.salesman_id) return;

    const oldStatus = beforeData ? beforeData.status : null;
    const newStatus = afterData.status;

    if (oldStatus !== newStatus && (newStatus === "Approved" || newStatus === "Pending" || newStatus === "Rejected" || newStatus === "Cancelled")) {
        const sid = afterData.salesman_id;
        let leaveDateStr = "";

        if (afterData.leave_date && afterData.leave_date.toDate) {
            leaveDateStr = moment(afterData.leave_date.toDate()).tz(TIMEZONE).format("YYYY-MM-DD");
        } else {
            const parts = event.params.docId.split("_");
            if (parts.length >= 3) {
                leaveDateStr = `${parts[0]}-${parts[1]}-${parts[2]}`;
            }
        }

        if (leaveDateStr) {
            try {
                const attDocId = `${leaveDateStr}_${sid}`;
                const attRef = db.collection("attendance").doc(attDocId);
                const attSnap = await attRef.get();

                let shouldManuallyCalculate = true;

                if (attSnap.exists) {
                    const aData = attSnap.data();
                    if (newStatus === "Approved") {
                        if (aData.status === "Absent") {
                            await attRef.update({
                                status: "On Leave",
                                updated_at: admin.firestore.FieldValue.serverTimestamp()
                            });
                            shouldManuallyCalculate = false;
                        }
                    } else if (newStatus === "Rejected" || newStatus === "Cancelled" || newStatus === "Pending") {
                        if (aData.status === "On Leave" || aData.status === "Leave" || aData.status === "Approved") {
                            if (!aData.clock_in_time) {
                                await attRef.update({
                                    status: "Absent",
                                    updated_at: admin.firestore.FieldValue.serverTimestamp()
                                });
                                shouldManuallyCalculate = false;
                            }
                        }
                    }
                }

                if (shouldManuallyCalculate) {
                    const currentMonth = moment(leaveDateStr, "YYYY-MM-DD").tz(TIMEZONE).format("YYYY-MM");
                    await calculateAndStorePerformance(sid, currentMonth);
                }
            } catch (err) {
                console.error(`Error in onLeaveWrite for ${sid}:`, err);
            }
        }
    }
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
            return res.json({ status: "success", message: "Thettaya Documents onnumilla!" });
        }

        const BATCH_LIMIT = 450;
        for (let i = 0; i < batchOps.length; i += BATCH_LIMIT) {
            const chunk = batchOps.slice(i, i + BATCH_LIMIT);
            const batch = db.batch();
            chunk.forEach(ref => batch.delete(ref));
            await batch.commit();
        }

        return res.json({ status: "success", message: `Aake ${deleteCount} documents delete cheythu! 🔥` });
    } catch (err) {
        console.error(err);
        return res.json({ status: "error", message: err.toString() });
    }
});

// ============================================================================
// 18. WALKING CUSTOMER API (🔥 MERGED TYPO COLLECTIONS & FIXED ID FORMAT)
// ============================================================================
exports.walking_customer = onRequest({ cors: true, enforceAppCheck: false }, async (req, res) => {
    try {
        const data = req.method === "POST" ? req.body : req.query;
        const { action } = data;

        // 🔥 Helper: walking_customers Collection-ல் Document Reference-ஐ எடுக்க
        async function findWalkingDoc(docId) {
            let docRef = db.collection('walking_customers').doc(docId);
            let snap = await docRef.get();
            if (snap.exists) return docRef;

            docRef = db.collection('walking_customer').doc(docId);
            snap = await docRef.get();
            if (snap.exists) return docRef;

            return null;
        }

        // --- 1. GET DASHBOARD STATS ---
        if (action === 'get_stats') {
            const { salesman_id } = data;
            if (!salesman_id) return res.json({ status: 'error', message: 'Salesman ID Required' });

            const snap1 = await db.collection('walking_customers')
                .where('salesman_id', '==', salesman_id).get();
            const snap2 = await db.collection('walking_customer')
                .where('salesman_id', '==', salesman_id).get();

            let pending = 0, billed = 0;
            const countStats = (doc) => {
                if (doc.data().status === 'Pending') pending++;
                if (doc.data().status === 'Billed') billed++;
            };

            snap1.forEach(countStats);
            snap2.forEach(countStats);

            return res.json({ status: 'success', data: { pending, billed } });
        }

        // --- 2. ADD WALKING ---
        if (action === 'add_walking') {
            const { salesman_id, customer_name, phone, product_interest } = data;
            if (!salesman_id || !customer_name) return res.json({ status: 'error', message: 'Name is required' });

            const now = moment().tz(TIMEZONE);

            // 🔥 EXACT OLD FORMAT: SM834_20260218_21_01 (SalesmanID_YYYYMMDD_HH_mm)
            const timeStr = now.format('YYYYMMDD_HH_mm');
            const docId = `${salesman_id}_${timeStr}`;

            // இனி புதிய டேட்டா எல்லாமே சரியான Collection-ல் (walking_customers) மட்டுமே சேவ் ஆகும்
            await db.collection('walking_customers').doc(docId).set({
                id: Date.now(), // Fallback Numeric ID
                salesman_id,
                customer_name,
                phone: phone || "",
                product_interest: product_interest || "",
                status: 'Pending',
                created_at: admin.firestore.FieldValue.serverTimestamp(),
                bill_photo: null,
                billed_at: null,
                feedback_text: null,
                feedback_by: null,
                feedback_date: null
            });

            return res.json({ status: 'success', message: 'Saved Successfully' });
        }

        // --- 3. GET MY WALKINGS ---
        if (action === 'get_my_walkings') {
            const { salesman_id } = data;

            const snap1 = await db.collection('walking_customers')
                .where('salesman_id', '==', salesman_id)
                .orderBy('created_at', 'desc')
                .limit(100)
                .get();

            const snap2 = await db.collection('walking_customer')
                .where('salesman_id', '==', salesman_id)
                .orderBy('created_at', 'desc')
                .limit(100)
                .get();

            const responseData = [];
            const processDoc = (doc) => {
                const row = doc.data();
                const createdAt = row.created_at ? row.created_at.toDate() : null;
                let createdFmt = "";
                if (createdAt) {
                    createdFmt = moment(createdAt).tz(TIMEZONE).format('YYYY-MM-DD HH:mm:ss');
                }

                const billedAt = row.billed_at ? row.billed_at.toDate() : null;
                let billedFmt = "";
                if (billedAt) {
                    billedFmt = moment(billedAt).tz(TIMEZONE).format('YYYY-MM-DD HH:mm:ss');
                }

                responseData.push({
                    id: doc.id,
                    salesman_id: row.salesman_id,
                    customer_name: row.customer_name,
                    phone: row.phone || "",
                    product_interest: row.product_interest || "",
                    status: row.status || 'Pending',
                    created_at: createdAt ? createdAt.getTime() : 0,
                    created_date_fmt: createdFmt,
                    bill_photo: row.bill_photo || null,
                    billed_at: billedAt ? billedAt.getTime() : 0,
                    billed_date_fmt: billedFmt,
                    feedback_text: row.feedback_text || null,
                    feedback_by: row.feedback_by || null,
                    feedback_date: row.feedback_date ? row.feedback_date.toDate().toISOString() : null
                });
            };

            snap1.forEach(processDoc);
            snap2.forEach(processDoc);

            responseData.sort((a, b) => b.created_at - a.created_at);

            return res.json({ status: 'success', data: responseData.slice(0, 100) });
        }

        // --- 4. UPLOAD BILL (Directly to Firebase Storage API) ---
        if (action === 'upload_bill') {
            const { getStorage } = require("firebase-admin/storage");
            const bucket = getStorage().bucket();
            const { id, bill_image, image } = data;
            let base64Image = bill_image || image;

            if (!id || !base64Image) return res.json({ status: 'error', message: 'Bill Photo Required' });

            if (base64Image.includes(',')) {
                base64Image = base64Image.split(',')[1];
            }

            const imageBuffer = Buffer.from(base64Image, 'base64');
            let compressedBuffer = imageBuffer;
            try {
                const sharp = require('sharp');
                compressedBuffer = await sharp(imageBuffer).jpeg({ quality: 60 }).toBuffer();
            } catch (e) {
                console.log('Sharp module not found or failed, proceeding without compression');
            }

            const filename = `bills/BILL_${id}_${Date.now()}.jpg`;
            const file = bucket.file(filename);

            await file.save(compressedBuffer, {
                metadata: { contentType: 'image/jpeg' }
            });
            await file.makePublic();

            const publicUrl = file.publicUrl();

            // Find in whichever collection it is and update
            const docRef = await findWalkingDoc(id);
            if (docRef) {
                await docRef.update({
                    bill_photo: publicUrl,
                    status: 'Billed',
                    billed_at: admin.firestore.FieldValue.serverTimestamp()
                });
            }

            return res.json({ status: 'success', message: 'Bill Uploaded Successfully' });
        }

        // --- NEW: UPDATE BILL URL (Image in PHP, Data in Firebase) ---
        if (action === 'update_bill_url') {
            const { id, bill_url } = data;
            if (!id || !bill_url) return res.json({ status: 'error', message: 'Bill URL Required' });

            const docRef = await findWalkingDoc(id);
            if (!docRef) return res.json({ status: 'error', message: 'Customer record not found!' });

            await docRef.update({
                bill_photo: bill_url,
                status: 'Billed',
                billed_at: admin.firestore.FieldValue.serverTimestamp()
            });

            return res.json({ status: 'success', message: 'Bill Data Updated in Firebase' });
        }

        // --- 5. ADD FEEDBACK ---
        if (action === 'add_feedback') {
            const { id, feedback_text, salesman_name } = data;
            if (!id || !feedback_text) return res.json({ status: 'error', message: 'Feedback cannot be empty' });

            const docRef = await findWalkingDoc(id);
            if (!docRef) return res.json({ status: 'error', message: 'Customer record not found!' });

            await docRef.update({
                feedback_text,
                feedback_by: salesman_name || 'Unknown',
                feedback_date: admin.firestore.FieldValue.serverTimestamp()
            });

            return res.json({ status: 'success', message: 'Feedback Added' });
        }

        // --- 6. UPDATE WALKING ---
        if (action === 'update_walking') {
            const { id, customer_name, phone, product_interest } = data;

            const docRef = await findWalkingDoc(id);
            if (!docRef) return res.json({ status: 'error', message: 'Customer record not found!' });

            await docRef.update({
                customer_name,
                phone: phone || "",
                product_interest: product_interest || ""
            });

            return res.json({ status: 'success', message: 'Updated' });
        }

        return res.json({ status: 'error', message: 'Invalid Action' });

    } catch (error) {
        console.error("Walking Customer API Error:", error);
        return res.json({ status: 'error', message: error.message });
    }
});

exports.admin_leave = onRequest({ cors: true }, async (req, res) => {
    const data = req.method === "POST" ? req.body : req.query;
    const action = data.action || "";

    try {
        // --- 1. GET PENDING LEAVE REQUESTS ---
        if (action === 'get_pending_requests') {
            const requests = [];
            const leaveSnap = await db.collection("leave_requests")
                .where("status", "in", ["Pending", "pending"])
                .orderBy("created_at", "desc")
                .get();

            for (const doc of leaveSnap.docs) {
                const row = doc.data();
                row.id = doc.id;

                if (row.salesman_id) {
                    const sSnap = await db.collection("salesmen").doc(row.salesman_id).get();
                    if (sSnap.exists) {
                        row.salesman_name = sSnap.data().name || "";
                        row.showroom_name = sSnap.data().showroom_name || "";
                    }
                }
                requests.push(row);
            }

            return res.json({
                status: "success",
                data: requests,
                debug_total_rows: leaveSnap.size,
                debug_message: `Found ${requests.length} pending requests.`
            });
        }

        // --- 2. GET CANCEL REQUESTS ---
        else if (action === 'get_cancel_requests') {
            const requests = [];
            const cancelSnap = await db.collection("leave_cancel_requests")
                .orderBy("created_at", "desc")
                .get();

            for (const doc of cancelSnap.docs) {
                const row = doc.data();
                row.id = doc.id;

                if (row.salesman_id) {
                    const sSnap = await db.collection("salesmen").doc(row.salesman_id).get();
                    if (sSnap.exists) row.showroom_name = sSnap.data().showroom_name || "";
                }

                if (row.leave_id) {
                    const lSnap = await db.collection("leave_requests").doc(row.leave_id).get();
                    if (lSnap.exists) {
                        row.leave_date = lSnap.data().leave_date;
                        row.leave_type = lSnap.data().leave_type;
                    }
                }
                requests.push(row);
            }
            return res.json({ status: "success", data: requests });
        }

        // --- 2.5 GET ALL REQUESTS (HISTORY) ---
        else if (action === 'get_all_requests') {
            const requests = [];
            const leaveSnap = await db.collection("leave_requests")
                .orderBy("created_at", "desc")
                .get();

            for (const doc of leaveSnap.docs) {
                const row = doc.data();
                row.id = doc.id;

                if (row.salesman_id) {
                    const sSnap = await db.collection("salesmen").doc(row.salesman_id).get();
                    if (sSnap.exists) {
                        row.salesman_name = sSnap.data().name || "";
                        row.showroom_name = sSnap.data().showroom_name || "";
                    }
                }
                requests.push(row);
            }
            return res.json({ status: "success", data: requests });
        }

        // --- 3. UPDATE LEAVE STATUS ---
        else if (action === 'update_status') {
            const leave_id = data.leave_id;
            const new_status = data.status;

            if (!leave_id || !new_status) {
                return res.json({ status: "error", message: "Missing ID or Status" });
            }

            await db.collection("leave_requests").doc(leave_id).update({
                status: new_status,
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            });
            return res.json({ status: "success", message: `Leave ${new_status} Successfully!` });
        }

        // --- 4. PROCESS CANCEL REQUEST ---
        else if (action === 'process_cancel_request') {
            const cancel_id = data.cancel_id;
            const decision = data.decision || 'Approve';

            if (!cancel_id) {
                return res.json({ status: "error", message: "Missing Cancel ID" });
            }

            const cancelRef = db.collection("leave_cancel_requests").doc(cancel_id);
            const cancelSnap = await cancelRef.get();

            if (!cancelSnap.exists) {
                return res.json({ status: "error", message: "Cancel Request Not Found" });
            }

            const leave_id = cancelSnap.data().leave_id;
            const batch = db.batch();

            if (decision === 'Approve') {
                if (leave_id) {
                    const leaveRef = db.collection("leave_requests").doc(leave_id);
                    batch.delete(leaveRef);
                }
                batch.delete(cancelRef);
                await batch.commit();

                return res.json({ status: "success", message: "Leave Request Deleted & Cancelled Successfully" });
            } else {
                batch.delete(cancelRef);
                await batch.commit();

                return res.json({ status: "success", message: "Cancellation Request Rejected" });
            }
        }

        // --- 5. GET NOTIFICATION COUNTS ---
        else if (action === 'get_notification_counts') {
            const pendingLeavesSnap = await db.collection("leave_requests")
                .where("status", "in", ["Pending", "pending"])
                .get();

            const cancelRequestsSnap = await db.collection("leave_cancel_requests").get();

            return res.json({
                status: "success",
                data: {
                    pending_leaves: pendingLeavesSnap.size,
                    cancel_requests: cancelRequestsSnap.size,
                    total: pendingLeavesSnap.size + cancelRequestsSnap.size
                }
            });
        }

        // --- INVALID ACTION ---
        else {
            return res.json({ status: "error", message: "Invalid Action" });
        }

    } catch (error) {
        console.error("Admin Leave Error:", error);
        return res.json({ status: "error", message: error.message });
    }
});

exports.admin_location = onRequest({ cors: true }, async (req, res) => {
    const data = req.method === "POST" ? req.body : req.query;
    const action = data.action || "";

    try {
        // ---------------------------------------------------------
        // 1. GET ALL LOCATIONS
        // ---------------------------------------------------------
        if (action === 'get_all_locations') {
            const showroom = data.showroom ? data.showroom.trim().toLowerCase() : "";

            // Get all active salesmen
            const salesmenSnap = await db.collection("salesmen")
                .where("status", "==", "Active")
                .get();

            const salesmen = [];
            const nowMs = Date.now();

            salesmenSnap.forEach(doc => {
                const row = doc.data();

                // Firestore doesn't support "LIKE" query easily, so filtering in memory
                const rowShowroom = (row.showroom_name || "").trim().toLowerCase();
                if (showroom && rowShowroom !== showroom) {
                    return; // Skip if showroom doesn't match
                }

                // Time calculation for Online/Offline (5 mins = 300000 ms)
                let lastSyncMs = 0;
                if (row.last_sync) {
                    lastSyncMs = row.last_sync.toDate ? row.last_sync.toDate().getTime() : new Date(row.last_sync).getTime();
                }
                const diffMs = nowMs - lastSyncMs;
                const is_online = diffMs < 300000; // less than 5 mins

                // Tracking Active check
                let trackingExpiryMs = 0;
                if (row.tracking_expiry) {
                    trackingExpiryMs = row.tracking_expiry.toDate ? row.tracking_expiry.toDate().getTime() : new Date(row.tracking_expiry).getTime();
                }

                // Checking if tracking is 1 or true and expiry time is greater than now
                const isTrackingFlag = row.is_tracking === 1 || row.is_tracking === "1" || row.is_tracking === true;
                const is_tracking_active = isTrackingFlag && (trackingExpiryMs > nowMs);

                salesmen.push({
                    salesman_id: row.salesman_id || doc.id,
                    name: row.name || "",
                    showroom_name: row.showroom_name || "Main Branch",
                    lat: parseFloat(row.current_lat || row.latitude || 0),
                    lng: parseFloat(row.current_lng || row.longitude || 0),
                    last_update: row.last_location_update || null,
                    is_online: is_online,
                    is_tracking: is_tracking_active,
                    gps_status: row.gps_status || "ON"
                });
            });

            return res.json({ status: "success", data: salesmen });
        }

        // ---------------------------------------------------------
        // 2. TRIGGER TRACKING (Fixes "Click to Track" issue)
        // ---------------------------------------------------------
        else if (action === 'toggle_tracking') {
            const salesman_id = data.salesman_id || "";
            const status = data.status || "0";

            if (!salesman_id) {
                return res.json({ status: "error", message: "Salesman ID required" });
            }

            const sRef = db.collection("salesmen").doc(salesman_id);
            const sSnap = await sRef.get();

            if (!sSnap.exists) {
                return res.json({ status: "error", message: "Salesman not found" });
            }

            if (status === '1') {
                // Enable for 5 Minutes
                const expiryTime = new Date(Date.now() + 5 * 60000); // Current time + 5 minutes
                await sRef.update({
                    is_tracking: 1,
                    tracking_expiry: admin.firestore.Timestamp.fromDate(expiryTime)
                });
            } else {
                // Disable
                await sRef.update({
                    is_tracking: 0
                });
            }

            // INSTANT FIX: Fetch the current location immediately to send back
            const updatedSnap = await sRef.get();
            const locData = updatedSnap.data();

            return res.json({
                status: "success",
                message: "Tracking Updated",
                lat: parseFloat(locData.current_lat || locData.latitude || 0),
                lng: parseFloat(locData.current_lng || locData.longitude || 0),
                gps_status: locData.gps_status || "ON"
            });
        }

        // ---------------------------------------------------------
        // INVALID ACTION
        // ---------------------------------------------------------
        else {
            return res.json({ status: "error", message: "Invalid Action" });
        }

    } catch (error) {
        console.error("Admin Location Error:", error);
        return res.json({ status: "error", message: error.message });
    }
});

exports.approve_attendance = onRequest({ cors: true }, async (req, res) => {
    const data = req.method === "POST" ? req.body : req.query;
    const action = data.action || "";
    const attendance_id = data.attendance_id || "";
    const approver_id = data.approver_id || "";

    if (!attendance_id) {
        return res.json({ status: "error", message: "Attendance ID is required" });
    }
    if (!approver_id) {
        return res.json({ status: "error", message: "Approver ID is required" });
    }
    if (action !== 'approve' && action !== 'reject' && action !== 'undo') {
        return res.json({ status: "error", message: "Invalid Action" });
    }

    try {
        // 🔥 SECURITY CHECK: Only Admin AND Owner can approve/reject
        let userRole = "";
        const staffSnap = await db.collection("billing_staff").where("staff_id", "==", approver_id).get();

        if (!staffSnap.empty) {
            userRole = (staffSnap.docs[0].data().role || "").toLowerCase();
        } else {
            // Fallback: Check doc ID directly
            const staffDoc = await db.collection("billing_staff").doc(approver_id).get();
            if (staffDoc.exists) {
                userRole = (staffDoc.data().role || "").toLowerCase();
            } else {
                return res.json({ status: "error", message: "Approver not found." });
            }
        }

        if (userRole !== 'admin' && userRole !== 'owner') {
            return res.json({ status: "error", message: "Permission Denied: Only Admin or Owner can perform this action." });
        }

        // STEP 1: Fetch Data from Database
        const attRef = db.collection("attendance").doc(attendance_id);
        const attSnap = await attRef.get();

        if (!attSnap.exists) {
            return res.json({ status: "error", message: "Attendance Record Not Found" });
        }

        const row = attSnap.data();
        if (!row.clock_in_time) {
            return res.json({ status: "error", message: "Clock In time not found for this record." });
        }

        // Get Salesman Data
        const salesman_id = row.salesman_id;
        const sSnap = await db.collection("salesmen").doc(salesman_id).get();
        const sRow = sSnap.exists ? sSnap.data() : {};

        const is_out_of_location = row.is_out_of_location === 1 || row.is_out_of_location === "1";
        const gender = (sRow.gender || 'male').toLowerCase();
        const custom_late_cutoff = sRow.custom_late_cutoff || null;

        // Parse Time using Moment.js
        const clockInDate = row.clock_in_time.toDate ? row.clock_in_time.toDate() : new Date(row.clock_in_time);
        const clockInMoment = moment(clockInDate).tz(TIMEZONE);
        const dateStr = clockInMoment.format("YYYY-MM-DD");
        const clockInStr = clockInMoment.format("HH:mm:ss");

        // Define Thresholds
        let late_cutoff_str = "10:00:59";
        if (custom_late_cutoff) {
            const customMoment = moment(`${dateStr} ${custom_late_cutoff}`, "YYYY-MM-DD HH:mm:ss").add(59, 'seconds');
            late_cutoff_str = customMoment.format("HH:mm:ss");
        }
        const leave_cutoff_str = "15:00:59";

        // STEP 2: Determine "Base Status" depending strictly on IN-TIME
        let baseStatus = 'Present';
        if (clockInStr > leave_cutoff_str) {
            baseStatus = 'Leave';
        } else if (clockInStr > late_cutoff_str) {
            baseStatus = 'Half Day';
        } else {
            baseStatus = 'Present';
        }

        // STEP 3: Apply Approve or Reject logic based on Base Status
        let finalStatus = '';
        let adminApprovalText = null;

        if (action === 'approve') {
            finalStatus = baseStatus;
            adminApprovalText = 'Approved';
        }
        else if (action === 'reject') {
            adminApprovalText = 'Rejected';
            if (baseStatus === 'Present') finalStatus = 'Half Day';
            else if (baseStatus === 'Half Day') finalStatus = 'Leave';
            else finalStatus = 'Leave';
        }
        else if (action === 'undo') {
            adminApprovalText = is_out_of_location ? 'Pending' : null;
            finalStatus = baseStatus;

            if (row.clock_out_time) {
                const clockOutDate = row.clock_out_time.toDate ? row.clock_out_time.toDate() : new Date(row.clock_out_time);
                const clockOutStr = moment(clockOutDate).tz(TIMEZONE).format("HH:mm:ss");
                const exit_cutoff = gender === 'female' ? '20:00:00' : '21:00:00';

                if (clockOutStr < '14:30:00') {
                    finalStatus = 'Leave';
                } else if (clockOutStr < exit_cutoff) {
                    finalStatus = (baseStatus === 'Half Day') ? 'Leave' : 'Half Day';
                }
            }
        }

        // STEP 4: Update the Final Status in Database
        await attRef.update({
            status: finalStatus,
            admin_approval: adminApprovalText,
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        });

        // NOTE: Firebase `onAttendanceWrite` Trigger handles the performance summary automatically
        // when the status changes, so no manual HTTP trigger is needed here!

        const msg_text = (action === 'undo')
            ? `Undo successful. Status reverted to ${finalStatus}.`
            : `Attendance ${adminApprovalText} successfully! Status set to ${finalStatus}.`;

        return res.json({
            status: "success",
            message: msg_text,
            new_status: finalStatus
        });

    } catch (error) {
        console.error("Approve Attendance Error:", error);
        return res.json({ status: "error", message: error.message });
    }
});


exports.check_user_status = onRequest({ cors: true }, async (req, res) => {
    const data = req.method === "POST" ? req.body : req.query;
    const staff_id = data.staff_id || "";

    if (!staff_id) {
        return res.json({ status: "error", message: "Staff ID required" });
    }

    try {
        // Check if user exists in billing_staff collection
        const staffSnap = await db.collection("billing_staff").where("staff_id", "==", staff_id).get();

        let isActive = false;

        if (!staffSnap.empty) {
            isActive = true;
        } else {
            // Fallback: Check if the staff_id is used as the document ID itself
            const staffDoc = await db.collection("billing_staff").doc(staff_id).get();
            if (staffDoc.exists) {
                isActive = true;
            }
        }

        if (isActive) {
            return res.json({ status: "active", message: "User is active" });
        } else {
            return res.json({ status: "inactive", message: "User not found" });
        }

    } catch (error) {
        console.error("Check User Status Error:", error);
        return res.json({ status: "error", message: error.message });
    }
});

exports.dashboard_stats = onRequest({ cors: true }, async (req, res) => {
    try {
        // Get today's start and end timestamps in IST timezone
        const startOfDay = admin.firestore.Timestamp.fromDate(moment().tz(TIMEZONE).startOf('day').toDate());
        const endOfDay = admin.firestore.Timestamp.fromDate(moment().tz(TIMEZONE).endOf('day').toDate());

        // 1. Pending Bills Count (Orders ready for billing)
        const pendingSnap = await db.collection("bills").where("status", "==", "Pending").get();
        const pending_bills = pendingSnap.size;

        // 2 & 3. Printed Bills (Today) and Total Sales Value (Today)
        const printedSnap = await db.collection("bills")
            .where("status", "==", "Printed")
            .where("created_at", ">=", startOfDay)
            .where("created_at", "<=", endOfDay)
            .get();

        const printed_today = printedSnap.size;
        let total_sales_today = 0;

        printedSnap.forEach(doc => {
            const data = doc.data();
            total_sales_today += parseFloat(data.final_price || 0);
        });

        // 4. Active Staff Count
        const staffSnap = await db.collection("salesmen").where("status", "==", "Active").get();
        const active_staff = staffSnap.size;

        // --- 🔥 WALKING CUSTOMER STATS ---

        // 5. Total Pending Walking Customers
        const walkPendingSnap = await db.collection("walking_customers").where("status", "==", "Pending").get();
        const walking_pending = walkPendingSnap.size;

        // 6. Walking Customers Billed TODAY
        const walkBilledSnap = await db.collection("walking_customers")
            .where("status", "==", "Billed")
            .where("billed_at", ">=", startOfDay)
            .where("billed_at", "<=", endOfDay)
            .get();
        const walking_billed_today = walkBilledSnap.size;

        // Send Final Response
        return res.json({
            status: "success",
            data: {
                pending_bills,
                printed_today,
                total_sales_today,
                active_staff,
                walking_pending,
                walking_billed_today
            }
        });

    } catch (error) {
        console.error("Dashboard Stats Error:", error);
        return res.json({ status: "error", message: error.message });
    }
});

exports.get_all_salesman_timing_report = onRequest({ cors: true }, async (req, res) => {
    const data = req.method === "POST" ? req.body : req.query;

    // Default dates and showroom matching PHP logic
    const showroom = data.showroom || 'All';
    const start_date = data.start_date || moment().tz(TIMEZONE).startOf('month').format('YYYY-MM-DD');
    const end_date = data.end_date || moment().tz(TIMEZONE).endOf('month').format('YYYY-MM-DD');

    try {
        // ---------------------------------------------------------
        // 1. Fetch Salesmen for this branch
        // ---------------------------------------------------------
        let salesmenQuery = db.collection("salesmen").where("status", "==", "Active");

        if (showroom !== 'All' && showroom !== '') {
            salesmenQuery = salesmenQuery.where("showroom_name", "==", showroom);
        }

        const salesmenSnap = await salesmenQuery.get();

        if (salesmenSnap.empty) {
            return res.json({
                status: "success",
                data: {},
                message: "No salesmen found for this showroom"
            });
        }

        const salesmenList = {};
        const sidArray = [];

        salesmenSnap.forEach(doc => {
            const s = doc.data();
            const sid = s.salesman_id || doc.id;
            let joinDateOnly = '2000-01-01';
            let joinTimeFmt = '--:--';

            if (s.created_at) {
                const createdDate = s.created_at.toDate ? s.created_at.toDate() : new Date(s.created_at);
                const createdMoment = moment(createdDate).tz(TIMEZONE);
                joinDateOnly = createdMoment.format('YYYY-MM-DD');
                joinTimeFmt = createdMoment.format('hh:mm A');
            }

            salesmenList[sid] = {
                name: s.name || "Unknown",
                showroom_name: s.showroom_name || "",
                join_date_only: joinDateOnly,
                join_time_fmt: joinTimeFmt
            };
            sidArray.push(sid);
        });

        // ---------------------------------------------------------
        // 2. Fetch Attendance Timings
        // ---------------------------------------------------------
        const startTs = admin.firestore.Timestamp.fromDate(moment.tz(start_date, "YYYY-MM-DD", TIMEZONE).startOf('day').toDate());
        const endTs = admin.firestore.Timestamp.fromDate(moment.tz(end_date, "YYYY-MM-DD", TIMEZONE).endOf('day').toDate());

        const attSnap = await db.collection("attendance")
            .where("date", ">=", startTs)
            .where("date", "<=", endTs)
            .get();

        const attendance_records = {};
        const today_str = moment().tz(TIMEZONE).format('YYYY-MM-DD');
        const records = [];

        attSnap.forEach(doc => {
            records.push(doc.data());
        });

        // Sort data chronologically and by salesman_id to match SQL 'ORDER BY date ASC, salesman_id ASC'
        records.sort((a, b) => {
            const dateA = a.date && a.date.toDate ? a.date.toDate().getTime() : 0;
            const dateB = b.date && b.date.toDate ? b.date.toDate().getTime() : 0;
            if (dateA !== dateB) return dateA - dateB;

            const sidA = a.salesman_id || "";
            const sidB = b.salesman_id || "";
            return sidA.localeCompare(sidB);
        });

        for (const row of records) {
            const sid = row.salesman_id;

            // Skip if salesman is not in our filtered list
            if (!sidArray.includes(sid)) continue;

            const s_info = salesmenList[sid];
            let rDateObj = row.date && row.date.toDate ? row.date.toDate() : null;
            if (!rDateObj) continue;

            const r_date = moment(rDateObj).tz(TIMEZONE).format('YYYY-MM-DD');
            const status_lower = (row.status || "").toLowerCase().trim();

            const in_t = row.clock_in_time;
            const out_t = row.clock_out_time;

            // Filter: Skip ABSENT before join date
            if (status_lower === 'absent' && r_date < s_info.join_date_only) {
                continue;
            }

            let disp_status = row.status || "";
            if (status_lower === 'present') disp_status = 'P';
            else if (status_lower === 'half day') disp_status = 'H';
            else if (status_lower === 'absent') disp_status = 'A';
            else if (status_lower.includes('leave')) disp_status = 'L';

            let remarks = (row.is_late === 1 || row.is_late === true || row.is_late === "1") ? "Late" : "";

            let inTimeFmt = '--:--';
            let outTimeFmt = '--:--';

            if (in_t) {
                const inDate = in_t.toDate ? in_t.toDate() : new Date(in_t);
                inTimeFmt = moment(inDate).tz(TIMEZONE).format('hh:mm A');
            }
            if (out_t) {
                const outDate = out_t.toDate ? out_t.toDate() : new Date(out_t);
                outTimeFmt = moment(outDate).tz(TIMEZONE).format('hh:mm A');
            }

            // Missing Clock-out Filter (Past Dates)
            if (r_date !== today_str && in_t && !out_t) {
                if (status_lower === 'present' || status_lower === 'half day') {
                    disp_status = '--';
                    remarks = (remarks ? `${remarks} | ` : "") + "No Clock-out";
                }
            }

            const entry = {
                name: s_info.name,
                showroom: s_info.showroom_name,
                status: disp_status,
                in_time: inTimeFmt,
                out_time: outTimeFmt,
                remarks: remarks,
                join_date: s_info.join_date_only,
                join_time: s_info.join_time_fmt
            };

            if (!attendance_records[r_date]) {
                attendance_records[r_date] = [];
            }
            attendance_records[r_date].push(entry);
        }

        // ---------------------------------------------------------
        // 3. Return JSON
        // ---------------------------------------------------------
        return res.json({
            status: "success",
            showroom: showroom,
            period: { start: start_date, end: end_date },
            data: attendance_records
        });

    } catch (error) {
        console.error("Salesman Timing Report Error:", error);
        return res.json({ status: "error", message: error.message });
    }
});


exports.get_attendance_excel = onRequest({ cors: true }, async (req, res) => {
    // 1. Set headers for Excel download
    res.setHeader("Content-Type", "application/vnd.ms-excel; charset=utf-8");
    res.setHeader("Content-Disposition", "attachment; filename=attendance_report.xls");
    res.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    res.setHeader("Pragma", "no-cache");
    res.setHeader("Expires", "0");

    const data = req.method === "POST" ? req.body : req.query;

    const start_date = data.start_date || moment().tz(TIMEZONE).startOf('month').format('YYYY-MM-DD');
    const end_date = data.end_date || moment().tz(TIMEZONE).endOf('month').format('YYYY-MM-DD');
    const showroom = data.showroom || 'All';
    const current_date = moment().tz(TIMEZONE).format('YYYY-MM-DD');

    // Date Format Validation
    const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
    if (!dateRegex.test(start_date) || !dateRegex.test(end_date)) {
        return res.send('\uFEFFSl.No,Error\n1,Invalid Date Format (Use YYYY-MM-DD)');
    }

    try {
        // 2. Generate Date Array
        const dates = [];
        let currDate = moment.tz(start_date, TIMEZONE);
        const lastDate = moment.tz(end_date, TIMEZONE);

        while (currDate.isSameOrBefore(lastDate)) {
            const dStr = currDate.format('YYYY-MM-DD');
            if (dStr <= current_date) {
                dates.push(dStr);
            }
            currDate.add(1, 'day');
        }

        // 3. Fetch Holidays
        const holidays = [];
        const holSnap = await db.collection("holidays")
            .where("holiday_date", ">=", start_date)
            .where("holiday_date", "<=", end_date)
            .get();
        holSnap.forEach(doc => {
            holidays.push(doc.data().holiday_date);
        });

        // 4. Fetch Active Salesmen
        let salesmenQuery = db.collection("salesmen").where("status", "==", "Active");
        if (showroom !== 'All' && showroom !== '') {
            salesmenQuery = salesmenQuery.where("showroom_name", "==", showroom);
        }
        const salesmenSnap = await salesmenQuery.get();
        const salesmenList = [];
        salesmenSnap.forEach(doc => {
            salesmenList.push({ id: doc.id, ...doc.data() });
        });

        // Sort salesmen alphabetically
        salesmenList.sort((a, b) => (a.name || "").localeCompare(b.name || ""));

        // 5. Fetch ALL Attendance records in the date range once (Optimization over looping queries)
        const startTs = admin.firestore.Timestamp.fromDate(moment.tz(start_date, "YYYY-MM-DD", TIMEZONE).startOf('day').toDate());
        const endTs = admin.firestore.Timestamp.fromDate(moment.tz(end_date, "YYYY-MM-DD", TIMEZONE).endOf('day').toDate());

        const attSnap = await db.collection("attendance")
            .where("date", ">=", startTs)
            .where("date", "<=", endTs)
            .get();

        const attendanceLookup = {};
        attSnap.forEach(doc => {
            const row = doc.data();
            const sid = row.salesman_id;
            if (!row.date || !row.date.toDate) return;
            const rDate = moment(row.date.toDate()).tz(TIMEZONE).format('YYYY-MM-DD');

            if (!attendanceLookup[sid]) attendanceLookup[sid] = {};
            attendanceLookup[sid][rDate] = row;
        });

        // 6. Output HTML Table for Excel
        let htmlOut = '\uFEFF'; // UTF-8 BOM for Excel
        htmlOut += "<table border='1'>";

        // Headers
        let headers = ['Sl.No', 'Salesman Name', 'Role', 'Showroom'];
        dates.forEach(d => {
            headers.push(moment(d).format('DD'));
        });
        headers = headers.concat(['Total Present', 'Total Leave/Absent', 'Total Half Day', 'Total Days Worked', 'Total Working Days']);

        htmlOut += "<tr style='background-color: #f2f2f2; font-weight: bold;'>";
        headers.forEach(header => {
            htmlOut += `<th>${header}</th>`;
        });
        htmlOut += "</tr>";

        if (salesmenList.length > 0) {
            let sl_no = 1;
            for (const salesman of salesmenList) {
                const sid = salesman.salesman_id || salesman.id;
                const name = salesman.name || "Unknown";
                const role_val = salesman.role || 'Salesman';
                const showroom_name = salesman.showroom_name || 'Main Branch';

                let join_date_only = '2000-01-01';
                if (salesman.created_at) {
                    const createdDate = salesman.created_at.toDate ? salesman.created_at.toDate() : new Date(salesman.created_at);
                    join_date_only = moment(createdDate).tz(TIMEZONE).format('YYYY-MM-DD');
                }

                let row_data = [sl_no++, name, role_val, showroom_name];

                let present_count = 0;
                let half_day_count = 0;
                let absent_leave_count = 0;
                let total_working_days = 0;

                dates.forEach(date => {
                    let cell_val = '-';

                    if (date < join_date_only) {
                        row_data.push('N/A');
                        return;
                    }

                    if (!holidays.includes(date)) {
                        total_working_days++;
                    }

                    if (attendanceLookup[sid] && attendanceLookup[sid][date]) {
                        const att = attendanceLookup[sid][date];
                        const status_lower = (att.status || "").toLowerCase().trim();
                        const r_in = att.clock_in_time;
                        const r_out = att.clock_out_time;

                        if (date !== current_date && r_in && !r_out) {
                            if (status_lower === 'present' || status_lower === 'half day') {
                                row_data.push('M/O'); // Missing Out
                                return;
                            }
                        }

                        if (holidays.includes(date)) {
                            row_data.push('Holiday');
                            return;
                        }

                        if (status_lower === 'present') {
                            cell_val = 'P';
                            present_count++;
                        } else if (status_lower === 'half day') {
                            cell_val = 'H';
                            half_day_count++;
                        } else if (status_lower.includes('leave')) {
                            cell_val = 'L';
                            absent_leave_count++;
                        } else {
                            cell_val = 'A';
                            absent_leave_count++;
                        }
                    } else {
                        if (holidays.includes(date)) {
                            cell_val = 'Holiday';
                        } else {
                            cell_val = 'A';
                            absent_leave_count++;
                        }
                    }
                    row_data.push(cell_val);
                });

                const adjusted_present = present_count + (half_day_count * 0.5);
                const adjusted_leave_absent = absent_leave_count + (half_day_count * 0.5);

                row_data.push(adjusted_present);
                row_data.push(adjusted_leave_absent);
                row_data.push(half_day_count);
                row_data.push(adjusted_present); // Total Days Worked
                row_data.push(total_working_days); // Total Working Days

                htmlOut += "<tr>";
                row_data.forEach(cell => {
                    if (cell === 'N/A') {
                        htmlOut += `<td style='background-color: #ffcccc; color: #cc0000; font-weight: bold; text-align: center;'>${cell}</td>`;
                    } else if (cell === 'M/O') {
                        htmlOut += `<td style='background-color: #ffe5b4; color: #ff8c00; font-weight: bold; text-align: center;'>${cell}</td>`;
                    } else if (cell === 'A') {
                        htmlOut += `<td style='color: red; font-weight: bold; text-align: center;'>${cell}</td>`;
                    } else if (cell === 'P' || cell === 'H' || cell === 'L' || cell === 'Holiday') {
                        htmlOut += `<td style='text-align: center;'>${cell}</td>`;
                    } else {
                        htmlOut += `<td>${cell}</td>`;
                    }
                });
                htmlOut += "</tr>";
            }
        } else {
            htmlOut += `<tr><td colspan='${headers.length}'>No matching records found</td></tr>`;
        }

        htmlOut += "</table>";

        // 7. Send Response
        res.status(200).send(htmlOut);

    } catch (error) {
        console.error("Export Excel Error:", error);
        res.send('\uFEFFSl.No,Error\n1,Server Error: ' + error.message);
    }
});


exports.get_attendance_report = onRequest({ cors: true }, async (req, res) => {
    const data = req.method === "POST" ? req.body : req.query;

    const start_date = data.start_date || moment().tz(TIMEZONE).startOf('month').format('YYYY-MM-DD');
    const end_date = data.end_date || moment().tz(TIMEZONE).endOf('month').format('YYYY-MM-DD');
    const current_date = moment().tz(TIMEZONE).format('YYYY-MM-DD');

    try {
        // 1. Fetch Active Salesmen
        const salesmenSnap = await db.collection("salesmen")
            .where("status", "==", "Active")
            .get();

        const salesmenList = [];
        salesmenSnap.forEach(doc => {
            salesmenList.push({ id: doc.id, ...doc.data() });
        });
        salesmenList.sort((a, b) => (a.name || "").localeCompare(b.name || ""));

        // 2. Fetch Holidays for the range
        const holidays = [];
        const hSnap = await db.collection("holidays")
            .where("holiday_date", ">=", start_date)
            .where("holiday_date", "<=", end_date)
            .get();
        hSnap.forEach(doc => {
            holidays.push(doc.data().holiday_date);
        });

        // 3. Fetch Attendance Data
        const startTs = admin.firestore.Timestamp.fromDate(moment.tz(start_date, "YYYY-MM-DD", TIMEZONE).startOf('day').toDate());
        const endTs = admin.firestore.Timestamp.fromDate(moment.tz(end_date, "YYYY-MM-DD", TIMEZONE).endOf('day').toDate());

        const attSnap = await db.collection("attendance")
            .where("date", ">=", startTs)
            .where("date", "<=", endTs)
            .get();

        const attendanceLookup = {};
        attSnap.forEach(doc => {
            const row = doc.data();
            const sid = row.salesman_id;
            if (!attendanceLookup[sid]) attendanceLookup[sid] = [];
            attendanceLookup[sid].push(row);
        });

        // 4. Fetch Approved Leaves
        const leaveSnap = await db.collection("leave_requests")
            .where("status", "==", "Approved")
            .get(); // Filtering dates in memory to avoid index issues

        const leaveLookup = {};
        leaveSnap.forEach(doc => {
            const row = doc.data();
            if (!row.leave_date || !row.leave_date.toDate) return;
            const lDate = moment(row.leave_date.toDate()).tz(TIMEZONE).format('YYYY-MM-DD');
            if (lDate >= start_date && lDate <= end_date) {
                const sid = row.salesman_id;
                if (!leaveLookup[sid]) leaveLookup[sid] = 0;
                leaveLookup[sid]++;
            }
        });

        const report_data = [];

        // 5. Build Report
        for (const salesman of salesmenList) {
            const sid = salesman.salesman_id || salesman.id;
            let join_date_only = '2000-01-01';
            if (salesman.created_at) {
                const createdDate = salesman.created_at.toDate ? salesman.created_at.toDate() : new Date(salesman.created_at);
                join_date_only = moment(createdDate).tz(TIMEZONE).format('YYYY-MM-DD');
            }

            let present_count = 0;
            let half_day_count = 0;
            let absent_count = 0;
            let leave_att_count = 0;
            let late_count = 0;

            const myAttendance = attendanceLookup[sid] || [];

            for (const row of myAttendance) {
                if (!row.date || !row.date.toDate) continue;
                const r_date = moment(row.date.toDate()).tz(TIMEZONE).format('YYYY-MM-DD');
                const status_lower = (row.status || "").toLowerCase().trim();
                const r_in = row.clock_in_time;
                const r_out = row.clock_out_time;
                const r_late = row.is_late === 1 || row.is_late === true || row.is_late === "1";

                // EXCLUSION: Skip Absent before join
                if (status_lower === 'absent' && r_date < join_date_only) continue;

                // EXCLUSION: Incomplete Days
                if (r_date !== current_date && r_in && !r_out) {
                    if (status_lower === 'present' || status_lower === 'half day') continue;
                }

                // EXCLUSION: Holidays
                if (holidays.includes(r_date)) {
                    if (status_lower === 'absent' || status_lower.includes('leave')) continue;
                }

                // Tallies
                if (status_lower === 'present') {
                    present_count++;
                    if (r_late) late_count++;
                } else if (status_lower === 'half day') {
                    half_day_count++;
                    if (r_late) late_count++;
                } else if (status_lower === 'absent') {
                    absent_count++;
                } else if (status_lower.includes('leave')) {
                    leave_att_count++;
                }
            }

            const leave_req_count = leaveLookup[sid] || 0;
            const final_leave_count = Math.max(leave_att_count, leave_req_count);
            const total_worked = present_count + (half_day_count * 0.5);

            report_data.push({
                id: sid,
                name: salesman.name || "Unknown",
                showroom_name: salesman.showroom_name || 'Unknown',
                present: present_count,
                half_day: half_day_count,
                absent: absent_count,
                leave: final_leave_count,
                late: late_count,
                total_working_days: total_worked,
                join_date: salesman.created_at
            });
        }

        return res.json({
            status: "success",
            data: report_data,
            period: { start: start_date, end: end_date }
        });

    } catch (error) {
        console.error("Attendance Report Error:", error);
        return res.json({ status: "error", message: error.message });
    }
});


exports.get_early_arrivals_excel = onRequest({ cors: true }, async (req, res) => {
    // Set CSV Headers
    res.setHeader("Content-Type", "text/csv; charset=utf-8");
    res.setHeader("Content-Disposition", "attachment; filename=early_arrivals_report.csv");
    res.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    res.setHeader("Pragma", "no-cache");
    res.setHeader("Expires", "0");

    const data = req.method === "POST" ? req.body : req.query;
    const start_date = data.start_date || moment().tz(TIMEZONE).format('YYYY-MM-DD');
    const end_date = data.end_date || moment().tz(TIMEZONE).format('YYYY-MM-DD');
    const showroom = data.showroom || 'All';

    // Date Format Validation
    const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
    if (!dateRegex.test(start_date) || !dateRegex.test(end_date)) {
        return res.send(`\uFEFFDate,Error\n${moment().tz(TIMEZONE).format('YYYY-MM-DD')},Invalid Date Format`);
    }

    try {
        let csvContent = '\uFEFFDate,Salesman ID,Name,Showroom,Clock-In Time,Clock-Out Time\n';

        const startTs = admin.firestore.Timestamp.fromDate(moment.tz(start_date, "YYYY-MM-DD", TIMEZONE).startOf('day').toDate());
        const endTs = admin.firestore.Timestamp.fromDate(moment.tz(end_date, "YYYY-MM-DD", TIMEZONE).endOf('day').toDate());

        // Fetch attendance
        const attSnap = await db.collection("attendance")
            .where("date", ">=", startTs)
            .where("date", "<=", endTs)
            .get();

        // Fetch active salesmen
        const salesmenSnap = await db.collection("salesmen").where("status", "==", "Active").get();
        const salesmenLookup = {};
        salesmenSnap.forEach(doc => {
            salesmenLookup[doc.id] = doc.data();
        });

        const records = [];

        attSnap.forEach(doc => {
            const row = doc.data();
            const sid = row.salesman_id;
            const salesman = salesmenLookup[sid];
            if (!salesman) return; // Skip if salesman not active/found

            if (showroom !== 'All' && showroom !== '' && salesman.showroom_name !== showroom) {
                return;
            }

            if (!row.clock_in_time) return;

            const inTimeMoment = moment(row.clock_in_time.toDate()).tz(TIMEZONE);
            const inTimeStr = inTimeMoment.format('HH:mm:ss');

            // LOGIC: Arrived before or at 09:30:59
            if (inTimeStr <= '09:30:59') {
                let outTimeFmt = "Still Present";
                let isValidEarly = true;

                if (row.clock_out_time) {
                    const outTimeMoment = moment(row.clock_out_time.toDate()).tz(TIMEZONE);
                    const outTimeStr = outTimeMoment.format('HH:mm:ss');

                    // AND clocked out after 18:00:00 (as per PHP logic)
                    if (outTimeStr < '18:00:00') {
                        isValidEarly = false;
                    } else {
                        outTimeFmt = outTimeMoment.format('hh:i A'); // 12-hour format
                    }
                }

                if (isValidEarly) {
                    records.push({
                        date: row.date ? moment(row.date.toDate()).tz(TIMEZONE).format('YYYY-MM-DD') : start_date,
                        sid: sid,
                        name: salesman.name,
                        showroom: salesman.showroom_name || "Main Branch",
                        inTimeFmt: inTimeMoment.format('hh:i A'),
                        outTimeFmt: outTimeFmt,
                        rawInTime: inTimeMoment.valueOf() // for sorting
                    });
                }
            }
        });

        // Sort by date DESC, then inTime ASC
        records.sort((a, b) => {
            if (a.date !== b.date) return b.date.localeCompare(a.date);
            return a.rawInTime - b.rawInTime;
        });

        if (records.length > 0) {
            for (const r of records) {
                // Escape commas by quoting strings if necessary
                const name = `"${(r.name || "").replace(/"/g, '""')}"`;
                const sroom = `"${(r.showroom || "").replace(/"/g, '""')}"`;
                csvContent += `${r.date},${r.sid},${name},${sroom},${r.inTimeFmt},${r.outTimeFmt}\n`;
            }
        } else {
            csvContent += `${moment().tz(TIMEZONE).format('YYYY-MM-DD')},-,No early arrivals found,-,-,-\n`;
        }

        return res.status(200).send(csvContent);

    } catch (error) {
        console.error("Early Arrivals CSV Error:", error);
        return res.send(`\uFEFFDate,Error\n${moment().tz(TIMEZONE).format('YYYY-MM-DD')},Server Error: ${error.message}`);
    }
});


exports.get_late_arrivals_excel = onRequest({ cors: true }, async (req, res) => {
    // Set CSV Headers
    res.setHeader("Content-Type", "text/csv; charset=utf-8");
    res.setHeader("Content-Disposition", "attachment; filename=late_arrivals_report.csv");
    res.setHeader("Access-Control-Allow-Origin", "*");

    const data = req.method === "POST" ? req.body : req.query;
    const start_date = data.start_date || moment().tz(TIMEZONE).format('YYYY-MM-DD');
    const end_date = data.end_date || moment().tz(TIMEZONE).format('YYYY-MM-DD');
    const showroom = data.showroom || 'All';

    try {
        let csvContent = '\uFEFFDate,Salesman ID,Name,Showroom,Clock-In Time\n';

        const startTs = admin.firestore.Timestamp.fromDate(moment.tz(start_date, "YYYY-MM-DD", TIMEZONE).startOf('day').toDate());
        const endTs = admin.firestore.Timestamp.fromDate(moment.tz(end_date, "YYYY-MM-DD", TIMEZONE).endOf('day').toDate());

        // Fetch attendance
        const attSnap = await db.collection("attendance")
            .where("date", ">=", startTs)
            .where("date", "<=", endTs)
            .get();

        // Fetch active salesmen
        const salesmenSnap = await db.collection("salesmen").where("status", "==", "Active").get();
        const salesmenLookup = {};
        salesmenSnap.forEach(doc => {
            salesmenLookup[doc.id] = doc.data();
        });

        const records = [];

        attSnap.forEach(doc => {
            const row = doc.data();
            const sid = row.salesman_id;
            const salesman = salesmenLookup[sid];
            if (!salesman) return; // Skip if salesman not active/found

            if (showroom !== 'All' && showroom !== '' && salesman.showroom_name !== showroom) {
                return;
            }

            if (!row.clock_in_time) return;

            const inTimeMoment = moment(row.clock_in_time.toDate()).tz(TIMEZONE);
            const inTimeStr = inTimeMoment.format('HH:mm:ss');

            // LOGIC: Arrived between 09:31:00 and 10:00:59
            if (inTimeStr >= '09:31:00' && inTimeStr <= '10:00:59') {
                records.push({
                    date: row.date ? moment(row.date.toDate()).tz(TIMEZONE).format('YYYY-MM-DD') : start_date,
                    sid: sid,
                    name: salesman.name,
                    showroom: salesman.showroom_name || "Main Branch",
                    inTimeFmt: inTimeMoment.format('hh:i A'),
                    rawInTime: inTimeMoment.valueOf() // for sorting
                });
            }
        });

        // Sort by date DESC, then inTime ASC
        records.sort((a, b) => {
            if (a.date !== b.date) return b.date.localeCompare(a.date);
            return a.rawInTime - b.rawInTime;
        });

        if (records.length > 0) {
            for (const r of records) {
                const name = `"${(r.name || "").replace(/"/g, '""')}"`;
                const sroom = `"${(r.showroom || "").replace(/"/g, '""')}"`;
                csvContent += `${r.date},${r.sid},${name},${sroom},${r.inTimeFmt}\n`;
            }
        } else {
            csvContent += `No late arrivals found for the given criteria (09:30 AM - 10:00 AM).\n`;
        }

        return res.status(200).send(csvContent);

    } catch (error) {
        console.error("Late Arrivals CSV Error:", error);
        return res.send(`\uFEFFDate,Error\nServer Error: ${error.message}`);
    }
});


exports.get_pending_attendance = onRequest({ cors: true }, async (req, res) => {
    const data = req.method === "POST" ? req.body : req.query;
    const showroom = data.showroom ? data.showroom.trim() : "";
    const staff_id = data.staff_id ? data.staff_id.trim() : "";

    try {
        let can_approve = false;

        // Check if Admin or Owner
        if (staff_id) {
            const roleSnap = await db.collection("billing_staff").where("staff_id", "==", staff_id).get();
            if (!roleSnap.empty) {
                const user_role = (roleSnap.docs[0].data().role || "").toLowerCase().trim();
                if (user_role === 'admin' || user_role === 'owner') {
                    can_approve = true;
                }
            } else {
                const docSnap = await db.collection("billing_staff").doc(staff_id).get();
                if (docSnap.exists) {
                    const user_role = (docSnap.data().role || "").toLowerCase().trim();
                    if (user_role === 'admin' || user_role === 'owner') can_approve = true;
                }
            }
        } else if (showroom === '') {
            can_approve = true; // Fallback for Admin login without showroom
        }

        const today = moment().tz(TIMEZONE);
        const sevenDaysAgo = moment().tz(TIMEZONE).subtract(7, 'days');

        const startTs = admin.firestore.Timestamp.fromDate(sevenDaysAgo.startOf('day').toDate());
        const endTs = admin.firestore.Timestamp.fromDate(today.endOf('day').toDate());

        // Fetch attendance with clock_out_time NOT NULL
        let attQuery = db.collection("attendance")
            .where("date", ">=", startTs)
            .where("date", "<=", endTs);

        // Note: Firestore doesn't allow "!= null" directly easily alongside range queries, 
        // we'll filter clock_out_time in memory.
        const attSnap = await attQuery.get();

        // Fetch salesmen
        const salesmenSnap = await db.collection("salesmen").get();
        const salesmenLookup = {};
        salesmenSnap.forEach(doc => { salesmenLookup[doc.id] = doc.data(); });

        // Fetch leave requests for last 7 days
        const leaveSnap = await db.collection("leave_requests")
            .where("leave_date", ">=", startTs)
            .where("leave_date", "<=", endTs)
            .get();
        const leaveLookup = {};
        leaveSnap.forEach(doc => {
            const row = doc.data();
            const sid = row.salesman_id;
            const lDate = moment(row.leave_date.toDate()).tz(TIMEZONE).format('YYYY-MM-DD');
            leaveLookup[`${sid}_${lDate}`] = row.leave_type;
        });

        const pending_approvals = [];
        let true_pending_count = 0;

        attSnap.forEach(doc => {
            const aData = doc.data();
            const sid = aData.salesman_id;
            const sData = salesmenLookup[sid];

            if (!sData || !aData.clock_out_time) return;
            if (showroom !== '' && sData.showroom_name !== showroom) return;

            const clockOutMoment = moment(aData.clock_out_time.toDate()).tz(TIMEZONE);
            const hour = clockOutMoment.hour();
            const gender = (sData.gender || 'male').toLowerCase();
            const maxHour = (gender === 'female') ? 20 : 21;

            const is_early_out = (hour >= 18 && hour < maxHour);
            const is_out_of_location_pending = (aData.is_out_of_location === "1" || aData.is_out_of_location === 1) && aData.admin_approval === 'Pending';
            const is_already_actioned = (aData.admin_approval && aData.admin_approval !== 'Pending');

            if (is_early_out || is_out_of_location_pending || is_already_actioned) {
                const status = (aData.status || "").toLowerCase().trim();
                const valid_statuses = ['present', 'late', 'half day', 'leave'];

                if (valid_statuses.includes(status) || (is_already_actioned && status === 'leave') || is_out_of_location_pending) {

                    const attDateStr = aData.date ? moment(aData.date.toDate()).tz(TIMEZONE).format('YYYY-MM-DD') : "";
                    const leaveType = leaveLookup[`${sid}_${attDateStr}`] || null;

                    let displayStatus = aData.status || "Not In";

                    let isLate = 0;
                    let lateMinutes = 0;
                    let clockInStr = "--:--";
                    if (aData.clock_in_time) {
                        const inMoment = moment(aData.clock_in_time.toDate()).tz(TIMEZONE);
                        clockInStr = inMoment.format('hh:mm A');

                        const time930 = moment(attDateStr + " 09:30:00", "YYYY-MM-DD HH:mm:ss").tz(TIMEZONE);
                        if (inMoment.isAfter(time930)) {
                            isLate = 1;
                            lateMinutes = Math.round(moment.duration(inMoment.diff(time930)).asMinutes());
                        }
                    }

                    let outOfLocAlert = "";
                    if (aData.is_out_of_location === "1" || aData.is_out_of_location === 1) {
                        outOfLocAlert = `Out of Showroom (${aData.location_distance || 0}m Away)`;
                    }

                    let adminAppr = aData.admin_approval === 'Pending' ? null : aData.admin_approval;
                    const isSeen = aData.is_seen_by_admin === 1 || aData.is_seen_by_admin === "1";

                    pending_approvals.push({
                        id: sid,
                        employeeId: sid,
                        name: sData.name || "Unknown",
                        phone: sData.phone || null,
                        role: sData.role || "Salesman",
                        gender: sData.gender || "Male",
                        showroom_name: sData.showroom_name || "Main Branch",
                        promoters: sData.promoters || null,
                        profilePhoto: null,
                        status: status,
                        displayStatus: displayStatus,
                        inTime: clockInStr,
                        outTime: clockOutMoment.format('hh:mm A'),
                        timestamp: clockOutMoment.valueOf(),
                        isLate: isLate === 1,
                        lateMinutes: lateMinutes,
                        leaveStatus: leaveType,
                        adminApproval: adminAppr,
                        attendanceId: doc.id,
                        showApprovalButtons: (!adminAppr && can_approve),
                        outOfLocationAlert: outOfLocAlert,
                        isSeen: isSeen,
                        latitude: aData.latitude || null,
                        longitude: aData.longitude || null,
                        outLatitude: aData.out_latitude || null,
                        outLongitude: aData.out_longitude || null,
                        selfieUrl: aData.selfie_url || null,
                        outSelfieUrl: aData.clock_out_selfie_url || null,
                        reentrySelfieUrl: aData.reentry_selfie_url || null,
                        out_selfie_url: aData.clock_out_selfie_url || null,
                        reentry_selfie_url: aData.reentry_selfie_url || null,
                        date: clockOutMoment.format('DD MMM YYYY')
                    });
                }
            }
        });

        // Sort: Pending first, then by timestamp DESC
        pending_approvals.sort((a, b) => {
            const aPending = !a.adminApproval ? 0 : 1;
            const bPending = !b.adminApproval ? 0 : 1;
            if (aPending !== bPending) return aPending - bPending;
            return b.timestamp - a.timestamp;
        });

        pending_approvals.forEach(item => {
            if (!item.adminApproval && !item.isSeen) true_pending_count++;
        });

        return res.json({
            status: "success",
            data: pending_approvals,
            count: true_pending_count
        });

    } catch (error) {
        console.error("Pending Attendance Error:", error);
        return res.json({ status: "error", message: error.message });
    }
});


exports.get_salesman_monthly_report = onRequest({ cors: true }, async (req, res) => {
    const data = req.method === "POST" ? req.body : req.query;

    const salesman_id = data.salesman_id || "";
    const start_date = data.start_date || moment().tz(TIMEZONE).startOf('month').format('YYYY-MM-DD');
    const end_date = data.end_date || moment().tz(TIMEZONE).endOf('month').format('YYYY-MM-DD');

    if (!salesman_id) {
        return res.json({ status: "error", message: "Salesman ID is required" });
    }

    try {
        // 1. Fetch Salesman Details
        const sSnap = await db.collection("salesmen").doc(salesman_id).get();
        if (!sSnap.exists) {
            // Check fallback (query by salesman_id field)
            const querySnap = await db.collection("salesmen").where("salesman_id", "==", salesman_id).get();
            if (querySnap.empty) {
                return res.json({ status: "error", message: "Salesman not found" });
            }
        }
        const sData = sSnap.exists ? sSnap.data() : (await db.collection("salesmen").where("salesman_id", "==", salesman_id).get()).docs[0].data();

        // 2. Fetch Holidays
        const holidays = {};
        const hSnap = await db.collection("holidays")
            .where("holiday_date", ">=", start_date)
            .where("holiday_date", "<=", end_date)
            .get();
        hSnap.forEach(doc => {
            const h = doc.data();
            holidays[h.holiday_date] = h.name || "Holiday";
        });

        // 3. Fetch Attendance
        const startTs = admin.firestore.Timestamp.fromDate(moment.tz(start_date, "YYYY-MM-DD", TIMEZONE).startOf('day').toDate());
        const endTs = admin.firestore.Timestamp.fromDate(moment.tz(end_date, "YYYY-MM-DD", TIMEZONE).endOf('day').toDate());

        const attSnap = await db.collection("attendance")
            .where("salesman_id", "==", salesman_id)
            .where("date", ">=", startTs)
            .where("date", "<=", endTs)
            .get();

        const attendance_data = {};
        attSnap.forEach(doc => {
            const row = doc.data();
            if (row.date && row.date.toDate) {
                const dateStr = moment(row.date.toDate()).tz(TIMEZONE).format('YYYY-MM-DD');
                attendance_data[dateStr] = row;
            }
        });

        // 4. Build Daily Report
        const report_rows = [];
        let currMoment = moment.tz(start_date, TIMEZONE);
        const endMoment = moment.tz(end_date, TIMEZONE);
        const todayStr = moment().tz(TIMEZONE).format('YYYY-MM-DD');

        while (currMoment.isSameOrBefore(endMoment)) {
            const date_str = currMoment.format('YYYY-MM-DD');
            const day_name = currMoment.format('ddd'); // Mon, Tue...

            let row_data = {
                date: date_str,
                day: day_name,
                status: 'Absent',
                in_time: '--:--',
                out_time: '--:--',
                remarks: ''
            };

            // Check Holiday
            if (holidays[date_str]) {
                row_data.status = 'Holiday';
                row_data.remarks = holidays[date_str];
            }

            // Check Attendance
            if (attendance_data[date_str]) {
                const att = attendance_data[date_str];
                row_data.status = att.status || "Absent";

                if (att.clock_in_time) {
                    row_data.in_time = moment(att.clock_in_time.toDate()).tz(TIMEZONE).format('hh:mm A');
                }

                if (att.clock_out_time) {
                    row_data.out_time = moment(att.clock_out_time.toDate()).tz(TIMEZONE).format('hh:mm A');
                } else if (att.clock_in_time) {
                    if (date_str !== todayStr) {
                        row_data.remarks = "No Clock-out";
                    } else {
                        row_data.remarks = "Ongoing";
                    }
                }

                if (att.is_late === 1 || att.is_late === "1" || att.is_late === true) {
                    row_data.remarks += (row_data.remarks ? " | " : "") + "Late Entry";
                    if (att.late_entry_approved === 1 || att.late_entry_approved === true) {
                        row_data.remarks += " (Approved)";
                    }
                }
            }

            report_rows.push(row_data);
            currMoment.add(1, 'day');
        }

        return res.json({
            status: "success",
            salesman: {
                id: salesman_id,
                name: sData.name || "Unknown",
                showroom: sData.showroom_name || "Main Branch"
            },
            data: report_rows
        });

    } catch (error) {
        console.error("Salesman Monthly Report Error:", error);
        return res.json({ status: "error", message: error.message });
    }
});


exports.leave_actions = onRequest({ cors: true }, async (req, res) => {
    const data = req.method === "POST" ? req.body : req.query;
    const action = data.action || "";

    try {
        // ----------------------------------------------------------------------
        // ACTION: APPLY LEAVE
        // ----------------------------------------------------------------------
        if (action === 'apply_leave') {
            const salesman_id = data.salesman_id || "";
            const leave_date = data.leave_date || "";
            const leave_type = data.leave_type || "Full Day";
            const reason = data.reason || "";

            if (!salesman_id || !leave_date || !reason) {
                return res.json({ status: "error", message: "Missing required fields" });
            }

            const lDateTs = admin.firestore.Timestamp.fromDate(moment.tz(leave_date, "YYYY-MM-DD", TIMEZONE).startOf('day').toDate());

            // Check if already exists for this date
            const checkSnap = await db.collection("leave_requests")
                .where("salesman_id", "==", salesman_id)
                .where("leave_date", "==", lDateTs)
                .get();

            let exists = false;
            checkSnap.forEach(doc => {
                if (doc.data().status !== 'Rejected' && doc.data().status !== 'Cancelled') {
                    exists = true;
                }
            });

            if (exists) {
                return res.json({ status: "error", message: "Leave request already exists for this date" });
            }

            await db.collection("leave_requests").add({
                salesman_id: salesman_id,
                leave_date: lDateTs,
                leave_type: leave_type,
                reason: reason,
                status: 'Pending',
                created_at: admin.firestore.FieldValue.serverTimestamp(),
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            });

            return res.json({ status: "success", message: "Leave applied successfully" });
        }

        // ----------------------------------------------------------------------
        // ACTION: CANCEL LEAVE REQUEST
        // ----------------------------------------------------------------------
        else if (action === 'cancel_leave') {
            const salesman_id = data.salesman_id || "";
            const leave_id = data.leave_id || "";
            const cancel_reason = data.reason || "By User";

            if (!salesman_id || !leave_id) {
                return res.json({ status: "error", message: "Missing ID or Leave ID" });
            }

            // Fetch Salesman Name
            let salesman_name = "Unknown";
            const sSnap = await db.collection("salesmen").doc(salesman_id).get();
            if (sSnap.exists) {
                salesman_name = sSnap.data().name || "Unknown";
            } else {
                const sQuery = await db.collection("salesmen").where("salesman_id", "==", salesman_id).get();
                if (!sQuery.empty) salesman_name = sQuery.docs[0].data().name || "Unknown";
            }

            await db.collection("leave_cancel_requests").add({
                salesman_id: salesman_id,
                salesman_name: salesman_name,
                leave_id: leave_id,
                cancel_reason: cancel_reason,
                created_at: admin.firestore.FieldValue.serverTimestamp()
            });

            return res.json({ status: "success", message: "Cancel request submitted" });
        }

        // ----------------------------------------------------------------------
        // ACTION: GET LEAVE HISTORY (For App List)
        // ----------------------------------------------------------------------
        else if (action === 'get_leave_history') {
            const salesman_id = data.salesman_id || "";

            if (!salesman_id) {
                return res.json({ status: "error", message: "Missing Salesman ID" });
            }

            const historySnap = await db.collection("leave_requests")
                .where("salesman_id", "==", salesman_id)
                .orderBy("created_at", "desc")
                .get();

            const records = [];
            historySnap.forEach(doc => {
                const row = doc.data();
                row.id = doc.id;
                if (row.leave_date && row.leave_date.toDate) {
                    row.leave_date_fmt = moment(row.leave_date.toDate()).tz(TIMEZONE).format('YYYY-MM-DD');
                }
                records.push(row);
            });

            return res.json({ status: "success", data: records });
        }

        // --- INVALID ACTION ---
        else {
            return res.json({ status: "error", message: "Invalid Action" });
        }

    } catch (error) {
        console.error("Leave Action Error:", error);
        return res.json({ status: "error", message: error.message });
    }
});


exports.manage_employees = onRequest({ cors: true }, async (req, res) => {
    const data = req.method === "POST" ? req.body : req.query;
    const action = data.action || "";

    try {
        // --- CREATE TABLE (Fallback/Mock for NoSQL) ---
        if (action === 'create_table') {
            return res.json({ status: "success", message: "Collection 'salesmen' is ready (NoSQL doesn't need table creation)" });
        }

        // --- ADD EMPLOYEE ---
        if (action === 'add') {
            const salesman_id = data.salesman_id ? data.salesman_id.trim() : "";
            const name = data.name ? data.name.trim() : "";
            const password = data.password || ""; // In production, hash this

            if (!salesman_id || !name) {
                return res.json({ status: "error", message: "ID and Name are required" });
            }

            // Check if ID exists
            const checkSnap = await db.collection("salesmen").where("salesman_id", "==", salesman_id).get();
            if (!checkSnap.empty) {
                return res.json({ status: "error", message: "Salesman ID already exists" });
            }

            await db.collection("salesmen").doc(salesman_id).set({
                salesman_id: salesman_id,
                name: name,
                password_hash: password,
                status: 'Active',
                created_at: admin.firestore.FieldValue.serverTimestamp()
            });

            return res.json({ status: "success", message: "Employee added successfully" });
        }

        // --- UPDATE EMPLOYEE STATUS ---
        else if (action === 'update') {
            const salesman_id = data.salesman_id ? data.salesman_id.trim() : "";
            const status = data.status ? data.status.trim() : ""; // 'Active' or 'Suspended'

            if (!salesman_id) {
                return res.json({ status: "error", message: "Salesman ID is required" });
            }

            const sRef = db.collection("salesmen").doc(salesman_id);
            const sSnap = await sRef.get();

            if (sSnap.exists) {
                await sRef.update({ status: status });
            } else {
                // Try querying by field if doc ID doesn't match
                const qSnap = await db.collection("salesmen").where("salesman_id", "==", salesman_id).get();
                if (!qSnap.empty) {
                    await qSnap.docs[0].ref.update({ status: status });
                } else {
                    return res.json({ status: "error", message: "Employee not found" });
                }
            }

            return res.json({ status: "success", message: "Employee status updated" });
        }

        // --- LIST EMPLOYEES ---
        else if (action === 'list') {
            const salesmenSnap = await db.collection("salesmen").orderBy("name", "asc").get();
            const employees = [];

            salesmenSnap.forEach(doc => {
                const row = doc.data();
                employees.push({
                    id: doc.id,
                    salesman_id: row.salesman_id || doc.id,
                    name: row.name || "",
                    status: row.status || "Active",
                    created_at: row.created_at ? row.created_at.toDate().toISOString() : null
                });
            });

            return res.json({ status: "success", data: employees });
        }

        // --- INVALID ACTION ---
        else {
            return res.json({ status: "error", message: "Invalid action" });
        }

    } catch (error) {
        console.error("Manage Employees Error:", error);
        return res.json({ status: "error", message: error.message });
    }
});


exports.mark_absent_sync = onRequest({ cors: true }, async (req, res) => {
    const data = req.method === "POST" ? req.body : req.query;
    const specific_salesman_id = data.salesman_id || null;

    try {
        const now = moment().tz(TIMEZONE);
        const current_time = now.format('HH:mm');
        const cutoff_time = '10:00';
        const today = now.format('YYYY-MM-DD');

        // 1. Determine End Date
        let end_date_str = today;
        if (current_time < cutoff_time) {
            end_date_str = now.clone().subtract(1, 'days').format('YYYY-MM-DD');
        }

        // 2. Determine Start Date (7 days back)
        const start_date_str = moment(end_date_str).subtract(6, 'days').format('YYYY-MM-DD');

        // 3. Generate Date List
        const dates_to_check = [];
        let currDate = moment(start_date_str);
        const endDate = moment(end_date_str);
        while (currDate.isSameOrBefore(endDate)) {
            dates_to_check.push(currDate.format('YYYY-MM-DD'));
            currDate.add(1, 'days');
        }

        let absent_count = 0;
        let cleaned_count = 0;
        let skipped_new_joinee_count = 0;
        let leave_synced = 0;
        const marked_ids = [];

        // Get Salesmen
        let salesmenQuery = db.collection("salesmen").where("status", "==", "Active");
        if (specific_salesman_id) {
            salesmenQuery = salesmenQuery.where("salesman_id", "==", specific_salesman_id);
        }
        const salesmenSnap = await salesmenQuery.get();
        const salesmenList = [];
        salesmenSnap.forEach(doc => salesmenList.push({ id: doc.id, ...doc.data() }));

        // Loop through Dates
        for (const process_date of dates_to_check) {
            const processTs = admin.firestore.Timestamp.fromDate(moment.tz(process_date, "YYYY-MM-DD", TIMEZONE).startOf('day').toDate());

            for (const salesman of salesmenList) {
                const sid = salesman.salesman_id || salesman.id;
                const sname = salesman.name || "";
                const showroom = salesman.showroom_name || 'Main Branch';

                // JOINING DATE CHECK
                let join_date = '2000-01-01';
                if (salesman.created_at) {
                    const cDate = salesman.created_at.toDate ? salesman.created_at.toDate() : new Date(salesman.created_at);
                    join_date = moment(cDate).tz(TIMEZONE).format('YYYY-MM-DD');
                }
                if (process_date < join_date) {
                    skipped_new_joinee_count++;
                    continue;
                }

                const attDocId = `${process_date.replace(/-/g, '_')}_${sid}`; // Standardizing ID format
                const attRef = db.collection("attendance").doc(attDocId);
                const attSnap = await attRef.get();

                const has_entry = attSnap.exists;
                const current_status = has_entry ? attSnap.data().status : '';

                // Check Approved Leave
                const leaveSnap = await db.collection("leave_requests")
                    .where("salesman_id", "==", sid)
                    .where("leave_date", "==", processTs)
                    .where("status", "==", "Approved")
                    .get();

                const has_approved_leave = !leaveSnap.empty;

                // LOGIC 1: LEAVE SYNC
                if (has_approved_leave) {
                    if (!has_entry) {
                        await attRef.set({
                            salesman_id: sid,
                            salesman_name: sname,
                            showroom_name: showroom,
                            date: processTs,
                            status: 'On Leave',
                            is_late: 0,
                            clock_in_time: null,
                            created_at: admin.firestore.FieldValue.serverTimestamp()
                        });
                        leave_synced++;
                    } else if (current_status === 'Absent') {
                        await attRef.update({ status: 'On Leave' });
                        leave_synced++;
                    }
                }
                // LOGIC 2: CONFLICT FIX
                else if (current_status === 'Absent' && has_approved_leave) {
                    await attRef.delete();
                    cleaned_count++;
                }
                // LOGIC 3: MARK ABSENT
                else if (!has_entry && !has_approved_leave) {
                    await attRef.set({
                        salesman_id: sid,
                        salesman_name: sname,
                        showroom_name: showroom,
                        date: processTs,
                        status: 'Absent',
                        is_late: 0,
                        clock_in_time: null,
                        created_at: admin.firestore.FieldValue.serverTimestamp()
                    });
                    absent_count++;
                    marked_ids.push({ id: sid, name: sname, date: process_date });
                }
            }
        }

        return res.json({
            status: "success",
            message: "Sync Completed.",
            marked_absent: absent_count,
            has_leave_synced: leave_synced,
            cleaned_conflicts: cleaned_count,
            skipped_new_joinees: skipped_new_joinee_count
        });

    } catch (error) {
        console.error("Mark Absent Sync Error:", error);
        return res.json({ status: "error", message: error.message });
    }
});


exports.mark_attendance = onRequest({ cors: true }, async (req, res) => {
    const data = req.method === "POST" ? req.body : req.query;
    const salesman_id = data.salesman_id || "";
    const action = data.action || ""; // 'clock_in', 'clock_out'
    const selfie_url = data.selfie_url || "";

    if (!salesman_id || !action) {
        return res.json({ status: "error", message: "Missing parameters" });
    }

    try {
        const now = moment().tz(TIMEZONE);
        const dateStr = now.format('YYYY-MM-DD');
        const timeStr = now.format('HH:mm:ss');
        const dateTs = admin.firestore.Timestamp.fromDate(now.startOf('day').toDate());

        // Fetch Salesman
        const sQuery = await db.collection("salesmen").where("salesman_id", "==", salesman_id).get();
        if (sQuery.empty) {
            return res.json({ status: "error", message: "Salesman not found or inactive" });
        }
        const sRow = sQuery.docs[0].data();
        const s_name = sRow.name || "";
        const s_showroom = sRow.showroom_name || "Main Branch";
        const gender = sRow.gender || "Male";

        // Fetch Today's Attendance
        let attDocRef = null;
        let attData = null;
        const attSnap = await db.collection("attendance")
            .where("salesman_id", "==", salesman_id)
            .where("date", "==", dateTs)
            .get();

        if (!attSnap.empty) {
            attDocRef = attSnap.docs[0].ref;
            attData = attSnap.docs[0].data();
        }

        if (action === 'clock_in') {
            const is_auto_absent = attData && attData.status === 'Absent' && !attData.clock_in_time;

            if (!attData || is_auto_absent) {
                // --- NEW ENTRY (Or Override Absent) ---
                let is_late = 0;
                let initial_status = 'Present';

                if (timeStr > "09:30:00" && timeStr <= "10:00:00") {
                    is_late = 1;
                } else if (timeStr > "10:00:00" && timeStr <= "15:00:00") {
                    initial_status = 'Half Day';
                } else if (timeStr > "15:00:00") {
                    initial_status = 'Absent'; // Leave
                }

                if (is_auto_absent) {
                    await attDocRef.update({
                        clock_in_time: admin.firestore.FieldValue.serverTimestamp(),
                        selfie_url: selfie_url,
                        is_late: is_late,
                        status: initial_status
                    });
                    return res.json({ status: "success", message: "Clocked In (Absent Overridden)" });
                } else {
                    await db.collection("attendance").add({
                        salesman_id: salesman_id,
                        salesman_name: s_name,
                        showroom_name: s_showroom,
                        date: dateTs,
                        clock_in_time: admin.firestore.FieldValue.serverTimestamp(),
                        selfie_url: selfie_url,
                        is_late: is_late,
                        status: initial_status
                    });
                    return res.json({ status: "success", message: "Clocked In" });
                }
            } else {
                // --- RE-ENTRY CHECK ---
                if (attData.clock_out_time) {
                    const lastOutDate = attData.clock_out_time.toDate ? attData.clock_out_time.toDate() : new Date(attData.clock_out_time);
                    const diffMinutes = moment().tz(TIMEZONE).diff(moment(lastOutDate).tz(TIMEZONE), 'minutes');

                    if (diffMinutes <= 60) {
                        await attDocRef.update({
                            clock_out_time: null,
                            status: 'Present'
                        });
                        return res.json({ status: "success", message: "Resumed Duty (Re-entry within 1 hr)" });
                    } else {
                        await attDocRef.update({ status: 'Absent' });
                        return res.json({ status: "error", message: "Re-entry timeout! Marked as Leave." });
                    }
                } else {
                    return res.json({ status: "error", message: "Already clocked in." });
                }
            }

        } else if (action === 'clock_out') {
            if (attData && !attData.clock_out_time) {
                // --- CLOCK OUT VALIDATION ---
                let final_status = 'Present';

                if (timeStr < "14:30:00") {
                    final_status = 'Absent'; // Leave
                } else if (timeStr >= "14:30:00" && timeStr <= "15:00:00") {
                    final_status = 'Half Day';
                }

                // Preserve 'Absent'/'Leave'
                if (attData.status === 'Absent' || attData.status === 'Leave') {
                    final_status = 'Absent';
                }

                await attDocRef.update({
                    clock_out_time: admin.firestore.FieldValue.serverTimestamp(),
                    status: final_status
                });

                return res.json({ status: "success", message: `Clocked Out (${final_status})` });

            } else {
                return res.json({ status: "error", message: "Not clocked in or already out." });
            }
        }

    } catch (error) {
        console.error("Mark Attendance Error:", error);
        return res.json({ status: "error", message: error.message });
    }
});


exports.mark_notifications_seen = onRequest({ cors: true }, async (req, res) => {
    const data = req.method === "POST" ? req.body : req.query;
    const ids_input = data.ids || "";

    if (!ids_input) {
        return res.json({ status: "error", message: "No IDs provided" });
    }

    try {
        let ids_array = [];
        if (typeof ids_input === 'string') {
            ids_array = JSON.parse(ids_input);
        } else if (Array.isArray(ids_input)) {
            ids_array = ids_input;
        }

        if (Array.isArray(ids_array) && ids_array.length > 0) {
            // Firebase Batch Update
            const batch = db.batch();

            for (const id of ids_array) {
                const docRef = db.collection("attendance").doc(id.toString());
                batch.update(docRef, { is_seen_by_admin: 1 });
            }

            await batch.commit();

            return res.json({ status: "success", message: "Marked as seen on server" });
        } else {
            return res.json({ status: "error", message: "Invalid IDs format" });
        }

    } catch (error) {
        console.error("Mark Notifications Seen Error:", error);
        return res.json({ status: "error", message: error.message });
    }
});


exports.staff_login = onRequest({ cors: true }, async (req, res) => {
    const data = req.method === "POST" ? req.body : req.query;
    const staff_id = data.staff_id || "";
    const password = data.password || "";

    if (!staff_id || !password) {
        return res.json({ status: "error", message: "Staff ID and Password required" });
    }

    try {
        const staffSnap = await db.collection("billing_staff").where("staff_id", "==", staff_id).get();

        if (!staffSnap.empty) {
            const row = staffSnap.docs[0].data();

            // Check password
            if (password === row.password_hash) {
                return res.json({
                    status: "success",
                    message: "Login Successful",
                    data: {
                        staff_id: row.staff_id,
                        name: row.name || "",
                        role: row.role || "",
                        showroom: row.showroom || ""
                    }
                });
            } else {
                return res.json({ status: "error", message: "Invalid Password" });
            }
        } else {
            // Fallback: check doc ID directly
            const docSnap = await db.collection("billing_staff").doc(staff_id).get();
            if (docSnap.exists) {
                const row = docSnap.data();
                if (password === row.password_hash) {
                    return res.json({
                        status: "success",
                        message: "Login Successful",
                        data: {
                            staff_id: row.staff_id || docSnap.id,
                            name: row.name || "",
                            role: row.role || "",
                            showroom: row.showroom || ""
                        }
                    });
                } else {
                    return res.json({ status: "error", message: "Invalid Password" });
                }
            }

            return res.json({ status: "error", message: "Staff ID not found" });
        }

    } catch (error) {
        console.error("Staff Login Error:", error);
        return res.json({ status: "error", message: error.message });
    }
});


exports.toggle_feature = onRequest({ cors: true }, async (req, res) => {
    const data = req.method === "POST" ? req.body : req.query;
    const feature_name = data.feature_name ? data.feature_name.trim() : null;
    let status = data.status !== undefined ? parseInt(data.status) : null;

    if (!feature_name || status === null || isNaN(status)) {
        return res.json({ status: "error", message: "Missing feature_name or status parameter" });
    }

    try {
        // Firestore 'feature_control' collection-la update/insert panrom
        // Document ID aaga feature_name-a use panrom
        await db.collection("feature_control").doc(feature_name).set({
            feature_name: feature_name,
            is_active: status,
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true }); // merge: true irunthal ON DUPLICATE KEY UPDATE maathiri work aagum

        return res.json({
            status: "success",
            message: `Feature '${feature_name}' updated successfully.`
        });

    } catch (error) {
        console.error("Toggle Feature Error:", error);
        return res.json({ status: "error", message: "Failed to update feature: " + error.message });
    }
});


exports.update_bill_status = onRequest({ cors: true }, async (req, res) => {
    const data = req.method === "POST" ? req.body : req.query;
    const order_id = data.order_id ? data.order_id.trim() : "";
    const new_status = data.status ? data.status.trim() : ""; // 'Printed', 'Cancelled'

    if (!order_id || !new_status) {
        return res.json({ status: "error", message: "Order ID and Status are required" });
    }

    try {
        // order_id vachi bills collection-la thedurom
        const billQuery = await db.collection("bills").where("order_id", "==", order_id).get();

        if (!billQuery.empty) {
            // First matching document-a update panrom
            await billQuery.docs[0].ref.update({
                status: new_status,
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            });
            return res.json({ status: "success", message: "Bill updated successfully" });
        } else {
            // Fallback: order_id thaan document id-ah irunthaal
            const docRef = db.collection("bills").doc(order_id);
            const docSnap = await docRef.get();
            if (docSnap.exists) {
                await docRef.update({
                    status: new_status,
                    updated_at: admin.firestore.FieldValue.serverTimestamp()
                });
                return res.json({ status: "success", message: "Bill updated successfully" });
            } else {
                return res.json({ status: "error", message: "Order ID not found" });
            }
        }

    } catch (error) {
        console.error("Update Bill Status Error:", error);
        return res.json({ status: "error", message: "Database error: " + error.message });
    }
});


exports.view_all_bills = onRequest({ cors: true }, async (req, res) => {
    const data = req.method === "POST" ? req.body : req.query;
    const status_filter = data.status ? data.status.trim() : "";
    const date_filter = data.date ? data.date.trim() : "";

    try {
        let billsQuery = db.collection("bills");

        if (status_filter && status_filter !== 'All') {
            billsQuery = billsQuery.where("status", "==", status_filter);
        }

        if (date_filter) {
            // Convert date string to Firestore Timestamps for the start and end of that day
            const startOfDay = admin.firestore.Timestamp.fromDate(moment.tz(date_filter, "YYYY-MM-DD", TIMEZONE).startOf('day').toDate());
            const endOfDay = admin.firestore.Timestamp.fromDate(moment.tz(date_filter, "YYYY-MM-DD", TIMEZONE).endOf('day').toDate());
            billsQuery = billsQuery.where("created_at", ">=", startOfDay).where("created_at", "<=", endOfDay);
        }

        // Fetch bills
        const billsSnap = await billsQuery.get();
        const billsList = [];

        // Optimize fetching salesmen names by fetching all active ones once
        const salesmenSnap = await db.collection("salesmen").get();
        const salesmenLookup = {};
        salesmenSnap.forEach(doc => {
            salesmenLookup[doc.id] = doc.data().name || "Unknown";
            if (doc.data().salesman_id) {
                salesmenLookup[doc.data().salesman_id] = doc.data().name || "Unknown";
            }
        });

        billsSnap.forEach(doc => {
            const row = doc.data();
            row.id = doc.id;

            // Map salesman_name
            if (row.salesman_id) {
                row.salesman_name = salesmenLookup[row.salesman_id] || "Unknown";
            }

            // Convert timestamp to readable date string for frontend sorting/display
            if (row.created_at && row.created_at.toDate) {
                row.created_date_fmt = moment(row.created_at.toDate()).tz(TIMEZONE).format('YYYY-MM-DD HH:mm:ss');
                row.raw_created_at = row.created_at.toDate().getTime();
            } else {
                row.raw_created_at = 0;
            }

            billsList.push(row);
        });

        // ORDER BY b.created_at DESC in memory (Since we might have range queries on other fields)
        billsList.sort((a, b) => b.raw_created_at - a.raw_created_at);

        return res.json({ status: "success", data: billsList });

    } catch (error) {
        console.error("View All Bills Error:", error);
        return res.json({ status: "error", message: error.message });
    }
});


exports.view_attendance = onRequest({ cors: true }, async (req, res) => {
    const data = req.method === "POST" ? req.body : req.query;
    const date = data.date || moment().tz(TIMEZONE).format('YYYY-MM-DD');
    const showroom = data.showroom ? data.showroom.trim() : "";

    try {
        const dateTs = admin.firestore.Timestamp.fromDate(moment.tz(date, "YYYY-MM-DD", TIMEZONE).startOf('day').toDate());

        // 1. Check Holiday
        let is_holiday = false;
        let holiday_reason = '';
        const hSnap = await db.collection("holidays").where("holiday_date", "==", date).get();
        if (!hSnap.empty) {
            is_holiday = true;
            holiday_reason = hSnap.docs[0].data().reason || 'Holiday';
        }

        // 2. Get Salesmen
        let salesmenQuery = db.collection("salesmen").where("status", "==", "Active");
        if (showroom) {
            salesmenQuery = salesmenQuery.where("showroom_name", "==", showroom);
        }
        const sSnap = await salesmenQuery.get();
        const salesmen = [];
        sSnap.forEach(doc => salesmen.push({ id: doc.id, ...doc.data() }));

        // Filter created_at <= date
        const filteredSalesmen = salesmen.filter(s => {
            if (!s.created_at) return true;
            const cDate = s.created_at.toDate ? moment(s.created_at.toDate()).tz(TIMEZONE).format('YYYY-MM-DD') : s.created_at;
            return cDate <= date;
        });

        // 3. Get Attendance for the date
        const attSnap = await db.collection("attendance").where("date", "==", dateTs).get();
        const attLookup = {};
        attSnap.forEach(doc => {
            attLookup[doc.data().salesman_id] = { id: doc.id, ...doc.data() };
        });

        // 4. Get Approved Leaves for the date
        const leaveSnap = await db.collection("leave_requests")
            .where("leave_date", "==", dateTs)
            .where("status", "==", "Approved")
            .get();
        const leaveLookup = {};
        leaveSnap.forEach(doc => {
            leaveLookup[doc.data().salesman_id] = doc.data();
        });

        const employees = [];

        for (const s of filteredSalesmen) {
            const sid = s.salesman_id || s.id;
            const att = attLookup[sid] || {};
            const leave = leaveLookup[sid] || {};

            let status = 'not_logged_in';
            let displayStatus = 'Not In';
            let isLate = 0;
            let lateMinutes = 0;

            const shiftStartStr = s.shift_start_time || '09:30:00';
            const lateCutoffStr = s.custom_late_cutoff || '10:01:00';

            // Priority 1: Calculate from clock_in_time
            if (att.clock_in_time) {
                const inMoment = moment(att.clock_in_time.toDate ? att.clock_in_time.toDate() : att.clock_in_time).tz(TIMEZONE);
                const shiftStartMoment = moment.tz(`${date} ${shiftStartStr}`, "YYYY-MM-DD HH:mm:ss", TIMEZONE);
                const shiftStartWithGrace = shiftStartMoment.clone().add(59, 'seconds');
                const lateCutoffMoment = moment.tz(`${date} ${lateCutoffStr}`, "YYYY-MM-DD HH:mm:ss", TIMEZONE);
                const time0300pm = moment.tz(`${date} 15:01:00`, "YYYY-MM-DD HH:mm:ss", TIMEZONE);

                if (inMoment.isAfter(shiftStartWithGrace)) {
                    isLate = 1;
                    lateMinutes = Math.round(moment.duration(inMoment.diff(shiftStartMoment)).asMinutes());
                }

                if ((att.late_entry_approved === 1 || att.late_entry_approved === true || att.admin_approval === 'Approved' || att.clock_out_time) && att.status) {
                    status = (att.status || "").toLowerCase();
                    if (isLate && status === 'present') status = 'late';
                    displayStatus = status.charAt(0).toUpperCase() + status.slice(1);
                } else if (inMoment.isBefore(lateCutoffMoment)) {
                    if (isLate) {
                        status = 'late'; displayStatus = 'Late';
                    } else {
                        status = 'present'; displayStatus = 'Present';
                    }
                } else if (inMoment.isBefore(time0300pm)) {
                    status = 'half day'; displayStatus = 'Half Day';
                } else {
                    status = 'half day'; displayStatus = 'Half Day (Excused)';
                }
            }
            // Priority 2: Use DB status
            else if (att.status) {
                status = att.status.toLowerCase();
                displayStatus = att.status;
            }

            // Priority Highest: Holiday & Leave Override
            if (is_holiday) {
                status = 'holiday'; displayStatus = 'Holiday';
            } else if (leave.leave_type && !att.clock_in_time) {
                status = 'on_leave'; displayStatus = 'On Leave';
            }

            // Approval Buttons Logic
            let showApprovalButtons = false;
            if (att.clock_out_time && (!att.admin_approval || att.admin_approval === 'Pending')) {
                const outMoment = moment(att.clock_out_time.toDate ? att.clock_out_time.toDate() : att.clock_out_time).tz(TIMEZONE);
                const currentMoment = moment().tz(TIMEZONE).startOf('day');
                const recordDateMoment = outMoment.clone().startOf('day');
                const daysDiff = currentMoment.diff(recordDateMoment, 'days');

                if (daysDiff >= 0 && daysDiff <= 7) {
                    const hour = outMoment.hour();
                    const gender = (s.gender || "male").toLowerCase();
                    const maxHour = gender === 'female' ? 20 : 21;

                    if (hour >= 16 && hour < maxHour) {
                        if (['present', 'late', 'half day'].includes(status)) {
                            showApprovalButtons = true;
                        }
                    }
                }
            }

            let inTimeFmt = "--:--";
            if (att.clock_in_time) inTimeFmt = moment(att.clock_in_time.toDate ? att.clock_in_time.toDate() : att.clock_in_time).tz(TIMEZONE).format('hh:mm A');

            let outTimeFmt = "--:--";
            if (att.clock_out_time) outTimeFmt = moment(att.clock_out_time.toDate ? att.clock_out_time.toDate() : att.clock_out_time).tz(TIMEZONE).format('hh:mm A');

            employees.push({
                id: sid,
                employeeId: sid,
                name: s.name,
                phone: s.phone || null,
                role: s.role || 'Salesman',
                role_color: getRoleColor(s.role),
                gender: s.gender || 'Male',
                showroom_name: s.showroom_name || 'Main Branch',
                promoters: s.promoters || null,
                profilePhoto: null,
                status: status,
                displayStatus: displayStatus,
                inTime: inTimeFmt,
                outTime: outTimeFmt,
                isLate: isLate === 1,
                lateMinutes: lateMinutes,
                leaveStatus: leave.leave_type || null,
                adminApproval: att.admin_approval || null,
                attendanceId: att.id || null,
                showApprovalButtons: showApprovalButtons,
                selfieUrl: att.selfie_url || null,
                outSelfieUrl: att.clock_out_selfie_url || null,
                reentrySelfieUrl: att.reentry_selfie_url || null,
                finalOutSelfieUrl: att.final_out_selfie_url || null,
                out_selfie_url: att.clock_out_selfie_url || null,
                reentry_selfie_url: att.reentry_selfie_url || null,
                selfieTimestamp: att.clock_in_time || null,
                pettaCount: 0,
                latitude: att.latitude || null,
                longitude: att.longitude || null,
                outLatitude: att.out_latitude || null,
                outLongitude: att.out_longitude || null,
                holiday_reason: is_holiday ? holiday_reason : ""
            });
        }

        // Sort alphabetically
        employees.sort((a, b) => (a.name || "").localeCompare(b.name || ""));

        return res.json({ status: "success", data: employees });

    } catch (error) {
        console.error("View Attendance Error:", error);
        return res.json({ status: "error", message: error.message });
    }
});


exports.walking_stats = onRequest({ cors: true }, async (req, res) => {
    const data = req.method === "POST" ? req.body : req.query;
    const action = data.action || "";

    try {
        // --- 1. GET SUMMARY ---
        if (action === 'get_summary') {
            const showroom = data.showroom ? data.showroom.trim() : "";
            const location = data.location ? data.location.trim() : "";

            let salesmenQuery = db.collection("salesmen").where("status", "==", "Active");
            if (showroom) salesmenQuery = salesmenQuery.where("showroom_name", "==", showroom);

            const salesmenSnap = await salesmenQuery.get();
            const salesmenData = {};
            salesmenSnap.forEach(doc => {
                const s = doc.data();
                salesmenData[s.salesman_id || doc.id] = {
                    salesman_id: s.salesman_id || doc.id,
                    name: s.name,
                    showroom_name: s.showroom_name,
                    last_sync: s.last_sync ? s.last_sync.toDate().toISOString() : null,
                    pending_count: 0,
                    billed_count: 0
                };
            });

            // Fetch walking customers (Filtered in memory since we need GROUP BY logic)
            const walkingSnap = await db.collection("walking_customers").get();
            walkingSnap.forEach(doc => {
                const w = doc.data();
                if (location && location !== 'All' && w.location !== location) return;

                const sData = salesmenData[w.salesman_id];
                if (sData) {
                    if (w.status === 'Pending') sData.pending_count++;
                    else if (w.status === 'Billed') sData.billed_count++;
                }
            });

            const resultData = Object.values(salesmenData).sort((a, b) => b.pending_count - a.pending_count);
            return res.json({ status: "success", data: resultData });
        }

        // --- 2. GET CUSTOMER LIST ---
        else if (action === 'get_customers') {
            const salesman_id = data.salesman_id || "";
            const location = data.location || "";

            if (!salesman_id) {
                return res.json({ status: "error", message: "ID Required" });
            }

            let query = db.collection("walking_customers").where("salesman_id", "==", salesman_id);
            if (location && location !== 'All') {
                query = query.where("location", "==", location);
            }

            const snap = await query.get();
            const customers = [];

            snap.forEach(doc => {
                const row = doc.data();
                row.id = doc.id;

                // In Firebase, we assume bill_photo is already a fully qualified Hostinger/Storage URL
                if (row.bill_photo) {
                    row.bill_photo_url = row.bill_photo;
                }

                if (row.created_at && row.created_at.toDate) {
                    row.raw_created = row.created_at.toDate().getTime();
                } else {
                    row.raw_created = 0;
                }
                customers.push(row);
            });

            customers.sort((a, b) => b.raw_created - a.raw_created);

            return res.json({ status: "success", data: customers.slice(0, 50) }); // LIMIT 50
        }

        // --- 3. GET SALESMAN LOCATIONS ---
        else if (action === 'get_salesman_locations') {
            const salesman_id = data.salesman_id || "";
            if (!salesman_id) return res.json({ status: "error", message: "ID Required" });

            const snap = await db.collection("walking_customers").where("salesman_id", "==", salesman_id).get();
            const locationsSet = new Set();

            snap.forEach(doc => {
                const loc = doc.data().location;
                if (loc) locationsSet.add(loc);
            });

            const locations = Array.from(locationsSet).sort();
            return res.json({ status: "success", data: locations });
        }

        // --- 4. GET ALL UNIQUE LOCATIONS FOR A SHOWROOM ---
        else if (action === 'get_all_locations') {
            const showroom = data.showroom ? data.showroom.trim() : "";

            // First get salesmen matching showroom
            let salesmenQuery = db.collection("salesmen");
            if (showroom) salesmenQuery = salesmenQuery.where("showroom_name", "==", showroom);

            const sSnap = await salesmenQuery.get();
            const validSalesmanIds = new Set();
            sSnap.forEach(doc => validSalesmanIds.add(doc.data().salesman_id || doc.id));

            // Then fetch locations
            const wSnap = await db.collection("walking_customers").get();
            const locationsSet = new Set();

            wSnap.forEach(doc => {
                const w = doc.data();
                if (w.location && validSalesmanIds.has(w.salesman_id)) {
                    locationsSet.add(w.location);
                }
            });

            const locations = Array.from(locationsSet).sort();
            return res.json({ status: "success", data: locations });
        }

        else {
            return res.json({ status: "error", message: "Invalid action" });
        }

    } catch (error) {
        console.error("Walking Stats Error:", error);
        return res.json({ status: "error", message: error.message });
    }
});

// ============================================================================
// ADMIN: UPDATE SALESMAN STATUS WEBHOOK
// ============================================================================
exports.update_salesman_status = onRequest({ cors: true, enforceAppCheck: false }, async (req, res) => {
    const data = req.method === "POST" ? req.body : req.query;

    // Simple verification with the shared secret key
    const { salesman_id, status, secret_key } = data;

    if (secret_key !== UPLOAD_SECRET_KEY) {
        return res.json({ status: "error", message: "Unauthorized Request" });
    }

    if (!salesman_id || !status) {
        return res.json({ status: "error", message: "salesman_id and status are required" });
    }

    try {
        const sid = salesman_id.trim();
        const docRef = db.collection("salesmen").doc(sid);

        // Ensure doc exists
        const docSnap = await docRef.get();
        if (!docSnap.exists) {
            return res.json({ status: "error", message: "Salesman not found in Firebase" });
        }

        // Update the status (e.g. 'Active', 'Suspended') and set is_active boolean
        const isActive = status.toLowerCase() === 'active';
        await docRef.update({
            status: status,
            is_active: isActive,
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        });

        return res.json({
            status: "success",
            message: `Salesman ${sid} status updated to ${status} in Firebase.`
        });
    } catch (err) {
        console.error("update_salesman_status error:", err);
        return res.json({ status: "error", message: err.toString() });
    }
});

// ============================================================================
// 18. LUNCH WINDOW SCHEDULER (Runs every minute to enforce custom schedule) 🍽️
// ============================================================================
exports.lunchWindowAutoScheduler = onSchedule({
    schedule: "* * * * *",
    timeZone: "Asia/Kolkata",
}, async (event) => {
    try {
        const dbRef = admin.database().ref("settings/lunch_window");
        const snapshot = await dbRef.once("value");
        if (snapshot.exists()) {
            const data = snapshot.val();
            if (data.mode === "auto") {
                const now = moment().tz("Asia/Kolkata");
                const currentTime = now.format("HH:mm");

                const startTime = data.start_time || "13:00";
                const endTime = data.end_time || "16:00";

                // Determine if we should be open or closed
                let shouldBeOpen = false;
                if (startTime < endTime) {
                    shouldBeOpen = currentTime >= startTime && currentTime < endTime;
                } else {
                    // handles overnight shift
                    shouldBeOpen = currentTime >= startTime || currentTime < endTime;
                }

                if (data.is_open !== shouldBeOpen) {
                    await dbRef.update({
                        is_open: shouldBeOpen,
                        last_updated: now.format("YYYY-MM-DD HH:mm:ss"),
                        updated_by: "system_scheduler_auto"
                    });
                    console.log(`Lunch window automatically ${shouldBeOpen ? 'OPENED' : 'CLOSED'} based on schedule ${startTime}-${endTime}`);
                }
            }
        }
    } catch (err) {
        console.error("Error in lunchWindowAutoScheduler:", err);
    }
});

// ============================================================================
// 🔥 FCM AUTO-WAKE: WhatsApp-Style Background Location Wake-Up
// Runs every 3 minutes during working hours to check for stale salesman locations.
// If a salesman has active tracking but hasn't sent location in 3+ minutes,
// it means the OS killed the app — we send a High Priority silent push to wake it up.
// ============================================================================
exports.fcmAutoWake = onSchedule({
    schedule: "*/3 * * * *",  // Every 3 minutes
    timeZone: "Asia/Kolkata",
    retryCount: 0,            // Don't retry — next cycle will handle it
    memory: "256MiB",
}, async (event) => {
    const now = moment().tz(TIMEZONE);
    const currentHour = now.hour();

    // 🔥 Only run during working hours (8 AM to 10 PM IST) to save resources
    if (currentHour < 8 || currentHour >= 22) {
        console.log("[fcmAutoWake] Outside working hours. Skipping.");
        return;
    }

    try {
        const rtdb = admin.database();

        // 1. Get all tracking_requests to find active salesmen
        const trackingSnapshot = await rtdb.ref("tracking_requests").once("value");
        const trackingData = trackingSnapshot.val();

        if (!trackingData) {
            console.log("[fcmAutoWake] No tracking_requests found. Skipping.");
            return;
        }

        const nowMs = Date.now();
        const STALE_THRESHOLD_MS = 3 * 60 * 1000; // 3 minutes
        let wakeUpCount = 0;
        let gpsOffCount = 0;

        for (const salesmanId of Object.keys(trackingData)) {
            const request = trackingData[salesmanId];

            // Only process salesmen with active live tracking
            if (!request || request.is_live !== true) continue;

            // 2. Check the last location update time
            const locationSnapshot = await rtdb.ref(`locations/${salesmanId}`).once("value");
            const locationData = locationSnapshot.val();

            let isStale = true;
            if (locationData && locationData.updated_at) {
                const lastUpdate = locationData.updated_at;
                const timeSinceUpdate = nowMs - lastUpdate;
                isStale = timeSinceUpdate > STALE_THRESHOLD_MS;

                // 🚨 Check if GPS is OFF
                if (locationData.gps_status === "OFF") {
                    gpsOffCount++;
                    console.log(`[fcmAutoWake] ⚠️ GPS OFF for salesman: ${salesmanId}`);
                    // Don't send FCM push if GPS is off — the phone can't get location anyway
                    continue;
                }
            }

            if (!isStale) continue; // Location is fresh — no need to wake up

            // 3. Get FCM token for this salesman
            const tokenSnapshot = await rtdb.ref(`salesmen/${salesmanId}/fcmToken`).once("value");
            const fcmToken = tokenSnapshot.val();

            if (!fcmToken) {
                console.log(`[fcmAutoWake] No FCM token for salesman: ${salesmanId}`);
                continue;
            }

            // 4. Send High-Priority SILENT Data Message (no notification shown to user)
            try {
                await admin.messaging().send({
                    token: fcmToken,
                    data: {
                        type: "location_wake",
                        salesman_id: salesmanId,
                        timestamp: nowMs.toString(),
                    },
                    android: {
                        priority: "high",        // 🔥 CRITICAL: Bypasses Doze mode
                        ttl: 60 * 1000,           // Message expires in 60 seconds
                    },
                    // NO 'notification' field — this is a DATA-ONLY message (silent)
                });

                wakeUpCount++;
                console.log(`[fcmAutoWake] ✅ Wake-up sent to: ${salesmanId}`);
            } catch (sendErr) {
                // Handle invalid/expired tokens
                if (sendErr.code === "messaging/registration-token-not-registered" ||
                    sendErr.code === "messaging/invalid-registration-token") {
                    console.log(`[fcmAutoWake] 🗑️ Invalid token for ${salesmanId}, cleaning up...`);
                    await rtdb.ref(`salesmen/${salesmanId}/fcmToken`).remove();
                } else {
                    console.error(`[fcmAutoWake] ❌ Send error for ${salesmanId}:`, sendErr.message);
                }
            }
        }

        console.log(`[fcmAutoWake] Done. Woke up: ${wakeUpCount}, GPS OFF: ${gpsOffCount}`);
    } catch (err) {
        console.error("[fcmAutoWake] Error:", err);
    }
});

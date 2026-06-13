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

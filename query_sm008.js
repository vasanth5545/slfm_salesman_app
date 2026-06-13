const admin = require('./functions/node_modules/firebase-admin');

admin.initializeApp({
  projectId: 'slfm-5a9e3' // Assuming default from your functions
});

const db = admin.firestore();

async function run() {
  try {
    const doc = await db.collection("salesman_monthly_performance").doc("2026-03_SM008").get();
    if (doc.exists) {
      console.log("=== MONTHLY PERFORMANCE ===");
      console.log(JSON.stringify(doc.data(), null, 2));
    } else {
      console.log("Monthly Performance DOC NOT FOUND");
    }

    const attSnap = await db.collection("attendance")
        .where("salesman_id", "==", "SM008")
        .where("date", ">=", new Date("2026-03-01T00:00:00.000Z"))
        .get();
        
    console.log("\n=== ATTENDANCE RECORDS ===");
    const absents = [];
    const excluded = [];
    attSnap.forEach(d => {
        let v = d.data();
        let status = v.status ? v.status.toLowerCase() : '';
        if (status === 'absent') absents.push(v.date);
        
        // Excluded check
        let isOutMissing = !v.clock_out_time || v.clock_out_time === '--:--';
        if (isOutMissing && (v.status === 'Present' || v.status === 'Half Day')) {
            excluded.push(v.date);
        }
    });
    console.log("Absents Found:", absents.length);
    console.log("Absents Dates:", absents.map(v => v.toDate().toISOString()));
    console.log("Excluded Found:", excluded.length);
    console.log("Excluded Dates:", excluded.map(v => v.toDate().toISOString()));
  } catch (err) {
    console.log("Error:", err);
  }
}

run();

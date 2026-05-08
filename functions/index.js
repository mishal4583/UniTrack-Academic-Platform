const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const crypto = require("crypto");
const { ethers } = require("ethers");

admin.initializeApp();

const ABI = [
  {
    "inputs": [
      {"internalType": "address", "name": "student", "type": "address"},
      {"internalType": "string", "name": "hash", "type": "string"}
    ],
    "name": "issueCertificate",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "string", "name": "hash", "type": "string"}],
    "name": "verifyCertificate",
    "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "string", "name": "", "type": "string"}],
    "name": "certificateOwner",
    "outputs": [{"internalType": "address", "name": "", "type": "address"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "anonymous": false,
    "inputs": [
      {"indexed": true, "internalType": "address", "name": "student", "type": "address"},
      {"indexed": false, "internalType": "string", "name": "certificateHash", "type": "string"},
      {"indexed": false, "internalType": "uint256", "name": "timestamp", "type": "uint256"}
    ],
    "name": "CertificateIssued",
    "type": "event"
  }
];

exports.issueCertificate = onCall(
  { secrets: ["RPC_URL", "PRIVATE_KEY", "CONTRACT_ADDRESS"] },
  async (request) => {

    console.log("🔥 FUNCTION TRIGGERED");
    console.log("Incoming Data:", request.data);

    try {
      // ✅ Check secrets loaded
      console.log("RPC_URL:", process.env.RPC_URL ? "Loaded" : "Missing");
      console.log("PRIVATE_KEY:", process.env.PRIVATE_KEY ? "Loaded" : "Missing");
      console.log("CONTRACT_ADDRESS:", process.env.CONTRACT_ADDRESS ? "Loaded" : "Missing");

      const provider = new ethers.JsonRpcProvider(process.env.RPC_URL);
      const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

      console.log("Wallet Address:", wallet.address);

      const contract = new ethers.Contract(
        process.env.CONTRACT_ADDRESS,
        ABI,
        wallet
      );

      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Login required");
      }

      const { certificateId, activityName } = request.data;

      if (!certificateId) {
        throw new HttpsError("invalid-argument", "Missing certificateId");
      }

      // 🔍 Fetch certificate
      const certDoc = await admin
        .firestore()
        .collection("certificates")
        .doc(certificateId)
        .get();

      console.log("Certificate exists:", certDoc.exists);

      if (!certDoc.exists) {
        throw new HttpsError("not-found", "Certificate not found");
      }

      const certData = certDoc.data();
      console.log("Certificate Data:", certData);

      if (certData.blockchainHash) {
        throw new HttpsError("already-exists", "Already on blockchain");
      }

      const studentAddress =
        certData.walletAddress ||
        "0x0000000000000000000000000000000000000000";

      console.log("Student Address:", studentAddress);

      // 🔐 Generate hash
      const hash = crypto
        .createHash("sha256")
        .update(certificateId + (activityName || ""))
        .digest("hex");

      console.log("Generated Hash:", hash);

      // 🚀 Call blockchain
      console.log("Calling smart contract...");
      const tx = await contract.issueCertificate(studentAddress, hash);

      console.log("TX SENT:", tx.hash);

      await tx.wait();

      console.log("TX CONFIRMED");

      // 🔄 Update Firestore
      await admin.firestore().collection("certificates").doc(certificateId).update({
        blockchainHash: hash,
        transactionHash: tx.hash,
        status: "verified",
      });

      console.log("Firestore updated");

      return {
        success: true,
        hash,
        txHash: tx.hash,
      };

    } catch (error) {
      console.error("❌ ERROR:", error);
      throw new HttpsError("internal", error.message);
    }
  }
);
// ─────────────────────────────────────────────────────────────────────────────
// enrollActivity — called by student when tapping "Enroll Now"
// Runs as admin SDK → bypasses Firestore client rules entirely
// ─────────────────────────────────────────────────────────────────────────────
exports.enrollActivity = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Login required");
  }

  const uid = request.auth.uid;
  const { activityId } = request.data;

  if (!activityId) {
    throw new HttpsError("invalid-argument", "Missing activityId");
  }

  const db = admin.firestore();
  const actRef = db.collection("activities").doc(activityId);

  try {
    let enrollmentId = null;

    await db.runTransaction(async (txn) => {
      const actSnap = await txn.get(actRef);

      if (!actSnap.exists) {
        throw new HttpsError("not-found", "Activity not found");
      }

      const data = actSnap.data();
      const enrolled = data.enrolled ?? 0;
      const capacity = data.capacity ?? 0;
      const status   = data.status   ?? "open";

      if (capacity <= 0) {
        throw new HttpsError("failed-precondition", "Invalid capacity");
      }

      // Duplicate check — must be outside transaction (Firestore rule)
      const existing = await db
        .collection("enrollments")
        .where("userId",     "==", uid)
        .where("activityId", "==", activityId)
        .limit(1)
        .get();

      if (!existing.empty) {
        throw new HttpsError("already-exists", "Already enrolled");
      }

      if (status === "full" || enrolled >= capacity) {
        throw new HttpsError("failed-precondition", "Activity is fully booked");
      }

      // Create enrollment doc
      const enrRef = db.collection("enrollments").doc();
      enrollmentId  = enrRef.id;

      txn.set(enrRef, {
        userId:     uid,
        activityId: activityId,
        status:     "Enrolled",
        enrolledAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Increment enrolled count + mark full if last spot
      const actUpdate = { enrolled: admin.firestore.FieldValue.increment(1) };
      if (enrolled + 1 >= capacity) {
        actUpdate.status = "full";
      }
      txn.update(actRef, actUpdate);
    });

    return { success: true, enrollmentId };

  } catch (error) {
    console.error("❌ enrollActivity error:", error);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", error.message);
  }
});

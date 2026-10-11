/**
 * MP3 Player — server-side App Store purchase verification.
 *
 * Sets `users/{uid}.isPremium` from a TRUSTED source: transactions verified
 * against Apple's signatures. This is the only place `isPremium` is written for
 * real purchases (the client is blocked from writing it by Firestore rules).
 *
 * Two entry points:
 *   1. appStoreNotificationsV2  (HTTPS webhook)
 *        Apple → your server on every lifecycle event: purchase, renewal,
 *        expiry, refund, revoke. Keeps isPremium correct even when the app
 *        isn't running (e.g. a subscription lapses → ads come back).
 *        Linked to a user via the transaction's `appAccountToken`.
 *
 *   2. syncAppStoreEntitlement  (callable)
 *        The app calls this right after a purchase/restore with the signed
 *        transaction (StoreKit 2 JWS) for an immediate, verified update.
 *        Linked to the user via the authenticated call (context.auth.uid).
 *
 * Requires the Blaze plan (Cloud Functions need billing). Deploy with:
 *   firebase deploy --only functions,firestore:rules
 *
 * See SERVER_VERIFICATION_SETUP.md for the full setup.
 */

const fs = require("fs");
const path = require("path");
const { onRequest, onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineString } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const {
  SignedDataVerifier,
  Environment,
} = require("@apple/app-store-server-library");

admin.initializeApp();
const db = admin.firestore();

// ---- Config (set via `firebase functions:config` params or .env) -----------

// Your app's bundle ID.
const BUNDLE_ID = defineString("APPLE_BUNDLE_ID", { default: "com.dhruva.mp3player" });
// Your app's numeric App Store ID (App Store Connect → App Information →
// "Apple ID"). Needed to verify PRODUCTION notifications. Fill it in once the
// app exists in App Store Connect.
const APP_APPLE_ID = defineString("APPLE_APP_APPLE_ID", { default: "" });

// Your in-app purchase product IDs (must match StoreKit / App Store Connect).
const OUR_PRODUCTS = new Set([
  "com.dhruva.mp3player.premium.monthly",
  "com.dhruva.mp3player.premium.lifetime",
]);

// Notification types that always mean "no longer entitled".
const NEGATIVE_NOTIFICATIONS = new Set([
  "EXPIRED",
  "GRACE_PERIOD_EXPIRED",
  "REVOKE",
  "REFUND",
]);

// ---- Apple signature verification ------------------------------------------

// Apple root CA certificates (DER/.cer) live in functions/certs/.
// Download them once — see functions/certs/README.md.
let cachedRootCerts = null;
function appleRootCertificates() {
  if (cachedRootCerts) return cachedRootCerts;
  const dir = path.join(__dirname, "certs");
  const files = fs
    .readdirSync(dir)
    .filter((f) => f.endsWith(".cer") || f.endsWith(".der") || f.endsWith(".pem"));
  if (files.length === 0) {
    throw new Error("No Apple root certificates found in functions/certs/. See certs/README.md.");
  }
  cachedRootCerts = files.map((f) => fs.readFileSync(path.join(dir, f)));
  return cachedRootCerts;
}

function makeVerifier(environment) {
  const appAppleId = APP_APPLE_ID.value()
    ? Number(APP_APPLE_ID.value())
    : undefined;
  return new SignedDataVerifier(
    appleRootCertificates(),
    /* enableOnlineChecks */ true,
    environment,
    BUNDLE_ID.value(),
    appAppleId
  );
}

// Verify against Production first, then Sandbox (so the same deployment handles
// both TestFlight/sandbox testing and live purchases).
async function verifyNotification(signedPayload) {
  let lastError;
  for (const env of [Environment.PRODUCTION, Environment.SANDBOX]) {
    try {
      const verifier = makeVerifier(env);
      const notification = await verifier.verifyAndDecodeNotification(signedPayload);
      const signedTx = notification.data && notification.data.signedTransactionInfo;
      const transaction = signedTx
        ? await verifier.verifyAndDecodeTransaction(signedTx)
        : null;
      return { notification, transaction };
    } catch (e) {
      lastError = e;
    }
  }
  throw lastError || new Error("Notification verification failed");
}

async function verifyTransaction(jws) {
  let lastError;
  for (const env of [Environment.PRODUCTION, Environment.SANDBOX]) {
    try {
      return await makeVerifier(env).verifyAndDecodeTransaction(jws);
    } catch (e) {
      lastError = e;
    }
  }
  throw lastError || new Error("Transaction verification failed");
}

// ---- Entitlement logic ------------------------------------------------------

function isTransactionActive(tx, negativeEvent) {
  if (negativeEvent) return false;
  if (tx.revocationDate) return false; // refunded / revoked
  if (tx.expiresDate) return tx.expiresDate > Date.now(); // subscription window
  return true; // non-consumable (lifetime) — active unless revoked
}

async function uidForAppAccountToken(token) {
  if (!token) return null;
  // Preferred: reverse-map doc written by the client (create-only, un-hijackable).
  const mapped = await db.collection("purchaseTokens").doc(token).get();
  if (mapped.exists && mapped.data().uid) return mapped.data().uid;
  // Fallback: single-field query on the user profile.
  const q = await db
    .collection("users")
    .where("appAccountToken", "==", token)
    .limit(1)
    .get();
  return q.empty ? null : q.docs[0].id;
}

async function setPremium(uid, active, tx) {
  await db.collection("users").doc(uid).set(
    {
      isPremium: active,
      premium: {
        active,
        productId: tx.productId,
        originalTransactionId: tx.originalTransactionId || null,
        expiresDate: tx.expiresDate ? new Date(tx.expiresDate) : null,
        source: "app_store_server",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    },
    { merge: true }
  );
  logger.info(`Set isPremium=${active} for ${uid} (${tx.productId})`);
}

// ---- 1) App Store Server Notifications V2 webhook --------------------------

exports.appStoreNotificationsV2 = onRequest(
  { cors: false, region: "us-central1" },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }
    const signedPayload = req.body && req.body.signedPayload;
    if (!signedPayload) {
      res.status(400).send("Missing signedPayload");
      return;
    }

    let notification;
    let transaction;
    try {
      ({ notification, transaction } = await verifyNotification(signedPayload));
    } catch (e) {
      logger.error("Signature verification failed", e);
      res.status(401).send("Invalid signature"); // don't retry a bad signature
      return;
    }

    try {
      const type = notification.notificationType;
      logger.info(`ASSN v2: ${type} / ${notification.subtype || "-"}`);

      if (!transaction) {
        res.status(200).send("OK (no transaction)");
        return;
      }
      if (!OUR_PRODUCTS.has(transaction.productId)) {
        res.status(200).send("OK (other product)");
        return;
      }

      const uid = await uidForAppAccountToken(transaction.appAccountToken);
      if (!uid) {
        logger.warn(`No user for appAccountToken ${transaction.appAccountToken}`);
        res.status(200).send("OK (unmapped)");
        return;
      }

      const active = isTransactionActive(transaction, NEGATIVE_NOTIFICATIONS.has(type));
      await setPremium(uid, active, transaction);
      res.status(200).send("OK");
    } catch (e) {
      logger.error("Processing error", e);
      res.status(500).send("Processing error"); // transient → Apple retries
    }
  }
);

// ---- 2) Callable: immediate post-purchase sync -----------------------------

exports.syncAppStoreEntitlement = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const jws = request.data && request.data.transactionJWS;
    if (!jws) {
      throw new HttpsError("invalid-argument", "Missing transactionJWS.");
    }

    let tx;
    try {
      tx = await verifyTransaction(jws);
    } catch (e) {
      logger.error("Callable verification failed", e);
      throw new HttpsError("invalid-argument", "Could not verify transaction.");
    }

    if (!OUR_PRODUCTS.has(tx.productId)) {
      throw new HttpsError("failed-precondition", "Unknown product.");
    }

    const active = isTransactionActive(tx, false);
    await setPremium(request.auth.uid, active, tx);
    return { isPremium: active };
  }
);

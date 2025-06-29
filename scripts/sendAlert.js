// scripts/sendAlert.js
import { initializeApp, cert, getApp } from 'firebase-admin/app';
import { getDatabase }                 from 'firebase-admin/database';
import { getMessaging }                from 'firebase-admin/messaging';

/* ------------------------------------------------------------------ */
/* 1️⃣  Load service-account creds                                    */
/*      Works with *either* raw JSON *or* base-64, no change needed.  */
const keyEnv = process.env.FIREBASE_SERVICE_ACCOUNT?.trim() || '';
if (!keyEnv) throw new Error('FIREBASE_SERVICE_ACCOUNT env-var is empty');

const serviceAccount = keyEnv.startsWith('{')           // raw JSON?
  ? JSON.parse(keyEnv)
  : JSON.parse(Buffer.from(keyEnv, 'base64'));

/* ------------------------------------------------------------------ */
/* 2️⃣  Initialise Firebase Admin                                     */
initializeApp({
  credential: cert(serviceAccount),
  databaseURL:
    process.env.DATABASE_URL ||               // preferred
    `https://${process.env.GOOGLE_CLOUD_PROJECT}.firebaseio.com`
});

/* ------------------------------------------------------------------ */
/* 3️⃣  Main logic                                                    */
const db  = getDatabase();
const fcm = getMessaging();

const ref = db.ref('sensors/latest');

try {
  const snap = await ref.get();
  if (!snap.exists()) {
    console.log('No /sensors/latest node found — nothing to do');
    await getApp().delete();
    process.exit(0);
  }

  const { temp, hum, updatedAt, lastNotifiedAt = 0 } = snap.val();

  if (updatedAt <= lastNotifiedAt) {
    console.log('Already notified for this reading');
    await getApp().delete();
    process.exit(0);
  }

  const message = {
    topic: 'all_android',
    notification: {
      title: 'Weather update',
      body: `Temp ${temp} °C, Hum ${hum}%`
    },
    data: { temp: String(temp), hum: String(hum) },
    android: { priority: 'high' }
  };

  await fcm.send(message);
  console.log('Push sent');

  await ref.child('lastNotifiedAt').set(Date.now());
} catch (err) {
  console.error('❌  sendAlert failed:', err);
  process.exitCode = 1;           // let GitHub Actions mark the job failed
} finally {
  /* ---------------------------------------------------------------- */
  /* 4️⃣  Clean shutdown                                              */
  await getApp().delete();        // closes all gRPC handles
  console.log('Job finished — exiting');
}

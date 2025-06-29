// scripts/sendAlert.js
import { initializeApp, cert } from 'firebase-admin/app';
import { getDatabase } from 'firebase-admin/database';
import { getMessaging } from 'firebase-admin/messaging';

const keyEnv = process.env.FIREBASE_SERVICE_ACCOUNT.trim();
const sa = keyEnv.startsWith('{')           // ← sniff: looks like raw JSON?
  ? JSON.parse(keyEnv)                      // yes → parse directly
  : JSON.parse(Buffer.from(keyEnv, 'base64').toString('utf8')); // else assume b64

initializeApp({
  credential: cert(sa),
  databaseURL: process.env.DATABASE_URL,
});

const db  = getDatabase();
const fcm = getMessaging();

// path that holds the object you pasted in the prompt
const ref = db.ref('sensors/latest');

(async () => {
  const snap = await ref.get();                       // single read :contentReference[oaicite:2]{index=2}
  if (!snap.exists()) return console.log('No data');

  const { temp, hum, updatedAt, lastNotifiedAt = 0 } = snap.val();

  // only notify when there's a *new* update
  if (updatedAt <= lastNotifiedAt) {
    return console.log('Already notified for this reading');
  }

  // compose push payload
  const message = {
    topic: 'all_android',
    notification: {
      title: 'Weather update',
      body: `Temp ${temp} °C, Hum ${hum}%`,
    },
    data: { temp: String(temp), hum: String(hum) },
    android: { priority: 'high' },
  };

  // send & log
  await fcm.send(message);                            // :contentReference[oaicite:3]{index=3}
  console.log('Push sent');

  // update marker so we don’t spam
  await ref.child('lastNotifiedAt').set(Date.now());
})();

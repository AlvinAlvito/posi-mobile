import dotenv from 'dotenv'
import fs from 'fs/promises'

dotenv.config()

let messaging = null

async function initFirebase() {
  if (!process.env.FIREBASE_SERVICE_ACCOUNT) return
  try {
    const admin = await import('firebase-admin')
    let credJson
    // allow inline JSON or file path
    const sa = process.env.FIREBASE_SERVICE_ACCOUNT
    if (sa.trim().startsWith('{')) {
      credJson = JSON.parse(sa)
    } else {
      const raw = await fs.readFile(sa, 'utf8')
      credJson = JSON.parse(raw)
    }
    if (!admin.apps.length) {
      admin.initializeApp({
        credential: admin.credential.cert(credJson),
      })
    }
    messaging = admin.messaging()
  } catch (err) {
    console.warn('FCM init failed, continuing without push:', err.message)
  }
}

await initFirebase()

export async function sendPush(tokens, payload) {
  if (!messaging || !tokens || tokens.length === 0) return { skipped: true }
  const msg = {
    tokens,
    notification: {
      title: payload.title || 'POSI',
      body: payload.body || '',
    },
    data: payload.data || {},
  }
  return messaging.sendEachForMulticast(msg)
}

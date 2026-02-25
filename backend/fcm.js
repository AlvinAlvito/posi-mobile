import dotenv from 'dotenv'
import fs from 'fs/promises'

dotenv.config()

let messaging = null

async function initFirebase() {
  const saRaw = process.env.FIREBASE_SERVICE_ACCOUNT
  if (!saRaw || !saRaw.trim()) {
    console.warn('FCM init skipped: FIREBASE_SERVICE_ACCOUNT not set')
    return
  }
  try {
    const adminModule = await import('firebase-admin')
    const admin = adminModule.default || adminModule
    let credJson
    // allow inline JSON or file path
    if (saRaw.trim().startsWith('{')) {
      credJson = JSON.parse(saRaw)
    } else {
      const raw = await fs.readFile(saRaw, 'utf8')
      credJson = JSON.parse(raw)
    }
    if (!admin.apps || !admin.apps.length) {
      admin.initializeApp({
        credential: admin.credential.cert(credJson),
      })
    }
    messaging = admin.messaging()
  } catch (err) {
    console.warn('FCM init failed, continuing without push:', err)
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
  try {
    const res = await messaging.sendEachForMulticast(msg)
    return res
  } catch (err) {
    console.error('[push] send error', err)
    return { error: err }
  }
}

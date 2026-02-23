import { Router } from 'express'
import { authRequired } from '../auth.js'
import { query } from '../db.js'

const router = Router()

router.post('/devices', authRequired(), async (req, res) => {
  const { token, platform, app } = req.body || {}
  if (!token || !platform) return res.status(400).json({ message: 'token & platform wajib' })
  await query(
    `INSERT INTO chat_device_tokens (user_id, token, platform, app, last_seen_at)
     VALUES (?, ?, ?, ?, NOW())
     ON DUPLICATE KEY UPDATE user_id = VALUES(user_id), platform = VALUES(platform), app = VALUES(app), last_seen_at = NOW(), revoked_at = NULL`,
    [req.user.id, token, platform, app || null]
  )
  res.json({ ok: true })
})

router.delete('/devices', authRequired(), async (req, res) => {
  const { token } = req.body || {}
  if (!token) return res.status(400).json({ message: 'token wajib' })
  await query('UPDATE chat_device_tokens SET revoked_at = NOW() WHERE token = ? AND user_id = ?', [token, req.user.id])
  res.json({ ok: true })
})

export default router

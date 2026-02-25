import { Router } from 'express'
import bcrypt from 'bcryptjs'
import { query } from '../db.js'
import { signToken, setAuthCookie } from '../auth.js'
import { OAuth2Client } from 'google-auth-library'

const router = Router()
const googleClient = process.env.GOOGLE_CLIENT_ID ? new OAuth2Client(process.env.GOOGLE_CLIENT_ID) : null

async function findUserByEmail(table, email) {
  const rows = await query(`SELECT id, name, email, password FROM ${table} WHERE email = ? LIMIT 1`, [email])
  return rows[0]
}

// User login
router.post('/login', async (req, res) => {
  const { email, password } = req.body || {}
  if (!email || !password) return res.status(400).json({ message: 'Email dan password wajib' })
  const user = await findUserByEmail('users', email)
  if (!user || !(await bcrypt.compare(password, user.password || ''))) {
    return res.status(401).json({ message: 'Email atau password salah' })
  }
  const token = signToken({ id: user.id, role: 'user', email: user.email })
  setAuthCookie(res, token)
  res.json({ token, user: { id: user.id, name: user.name, email: user.email } })
})

// Admin login
router.post('/admin/login', async (req, res) => {
  const { email, password } = req.body || {}
  if (!email || !password) return res.status(400).json({ message: 'Email dan password wajib' })
  const admin = await findUserByEmail('admins', email)
  if (!admin || !(await bcrypt.compare(password, admin.password || ''))) {
    return res.status(401).json({ message: 'Email atau password salah' })
  }
  const token = signToken({ id: admin.id, role: 'admin', email: admin.email })
  setAuthCookie(res, token)
  res.json({ token, admin: { id: admin.id, name: admin.name, email: admin.email } })
})

export default router

// logout: clear cookie
router.post('/logout', (req, res) => {
  res.cookie('token', '', { httpOnly: true, sameSite: 'lax', secure: false, maxAge: 0, path: '/' })
  res.json({ ok: true })
})

// Google login: require existing user by email, verify idToken
router.post('/google', async (req, res) => {
  try {
    const { idToken, accessToken } = req.body || {}
    if (!idToken && !accessToken) return res.status(400).json({ message: 'idToken atau accessToken wajib' })
    if (!googleClient) return res.status(500).json({ message: 'GOOGLE_CLIENT_ID belum diset' })

    let email, name
    if (idToken) {
      const ticket = await googleClient.verifyIdToken({
        idToken,
        audience: process.env.GOOGLE_CLIENT_ID,
      })
      const payload = ticket.getPayload()
      email = payload?.email
      name = payload?.name || email?.split('@')[0] || 'Pengguna'
    } else if (accessToken) {
      // fallback: gunakan accessToken untuk mengambil userinfo
      const resp = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
        headers: { Authorization: `Bearer ${accessToken}` },
      })
      if (!resp.ok) throw new Error('Google access token invalid')
      const data = await resp.json()
      email = data?.email
      name = data?.name || data?.given_name || email?.split('@')[0] || 'Pengguna'
    }
    if (!email) return res.status(400).json({ message: 'Email tidak ditemukan di token' })

    const user = await findUserByEmail('users', email)
    if (!user) return res.status(401).json({ message: 'Akun belum terdaftar, hubungi admin.' })

    const token = signToken({ id: user.id, role: 'user', email: user.email })
    setAuthCookie(res, token)
    res.json({ token, user: { id: user.id, name: user.name || name, email: user.email } })
  } catch (err) {
    console.error('Google login error', err)
    res.status(401).json({ message: 'Token Google tidak valid' })
  }
})

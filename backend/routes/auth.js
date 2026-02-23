import { Router } from 'express'
import bcrypt from 'bcryptjs'
import { query } from '../db.js'
import { signToken, setAuthCookie } from '../auth.js'

const router = Router()

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

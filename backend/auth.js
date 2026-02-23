import jwt from 'jsonwebtoken'
import dotenv from 'dotenv'

dotenv.config()

const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret'
const COOKIE_NAME = 'token'

export function signToken(payload, opts = {}) {
  return jwt.sign(payload, JWT_SECRET, { expiresIn: process.env.JWT_EXPIRES || '30d', ...opts })
}

export function setAuthCookie(res, token) {
  res.cookie(COOKIE_NAME, token, {
    httpOnly: true,
    sameSite: 'lax',
    secure: false, // set true if behind https
    maxAge: 30 * 24 * 60 * 60 * 1000,
    path: '/',
  })
}

export function authRequired(role = 'user') {
  return (req, res, next) => {
    const hdr = req.headers.authorization || ''
    const token =
      (hdr.startsWith('Bearer ') ? hdr.slice(7) : null) ||
      req.cookies?.token ||
      req.signedCookies?.token
    if (!token) return res.status(401).json({ message: 'Unauthorized' })
    try {
      const decoded = jwt.verify(token, JWT_SECRET)
      if (role === 'admin' && decoded.role !== 'admin') {
        return res.status(403).json({ message: 'Forbidden' })
      }
      req.user = decoded
      next()
    } catch (err) {
      return res.status(401).json({ message: 'Invalid token' })
    }
  }
}

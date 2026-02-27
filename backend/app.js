import http from 'http'
import express from 'express'
import cors from 'cors'
import helmet from 'helmet'
import morgan from 'morgan'
import dotenv from 'dotenv'
import cookieParser from 'cookie-parser'
import rateLimit from 'express-rate-limit'

import authRoutes from './routes/auth.js'
import ticketRoutes from './routes/tickets.js'
import deviceRoutes from './routes/devices.js'
import profileRoutes from './routes/profile.js'
import competitionRoutes from './routes/competitions.js'
import newsRoutes from './routes/news.js'
import resultsRoutes from './routes/results.js'
import { createSocket } from './socket.js'

dotenv.config()

// Allow all origins in dev if CORS_ORIGIN not set. Use comma-separated list; '*' means allow any.
const corsOrigins = (process.env.CORS_ORIGIN || '*')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean)
const cookieSecure = process.env.COOKIE_SECURE === 'true'

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 50,
  standardHeaders: true,
  legacyHeaders: false,
})

const app = express()
// disable etag and prevent caching so responses aren't 304'ed with empty bodies
app.set('etag', false)
app.use((req, res, next) => {
  res.set('Cache-Control', 'no-store, no-cache, must-revalidate')
  res.set('Pragma', 'no-cache')
  res.set('Expires', '0')
  next()
})
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Credentials', 'true')
  next()
})
app.use(helmet())
app.use(
  cors({
    origin: (origin, cb) => {
      if (!origin) return cb(null, true) // mobile / curl / same-origin
      if (corsOrigins.includes('*')) return cb(null, true)
      const allowed = corsOrigins.some((o) => {
        if (o === origin) return true
        if (o.endsWith('*')) return origin.startsWith(o.slice(0, -1))
        return false
      })
      cb(allowed ? null : new Error('Not allowed by CORS'), allowed)
    },
    credentials: true,
  })
)
app.use(express.json({ limit: '1mb' }))
app.use(express.urlencoded({ extended: true }))
app.use(cookieParser())
app.use(morgan('dev'))

app.get('/health', (req, res) => res.json({ ok: true }))
// Auth available at /login and /auth/login
app.use('/', authLimiter, authRoutes)
app.use('/auth', authLimiter, authRoutes)
// API routes with /api prefix (matching mobile app)
app.use('/api', ticketRoutes)
app.use('/api', deviceRoutes)
app.use('/api', profileRoutes)
app.use('/api', competitionRoutes)
app.use('/api', newsRoutes)
app.use('/api', resultsRoutes)

app.use((err, req, res, next) => {
  console.error(err)
  res.status(500).json({ message: 'Server error' })
})

const server = http.createServer(app)
createSocket(server)

const port = process.env.PORT || 4000
server.listen(port, () => {
  console.log(`POSI backend listening on ${port}`)
})

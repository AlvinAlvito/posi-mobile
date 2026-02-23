import http from 'http'
import express from 'express'
import cors from 'cors'
import helmet from 'helmet'
import morgan from 'morgan'
import dotenv from 'dotenv'
import cookieParser from 'cookie-parser'

import authRoutes from './routes/auth.js'
import ticketRoutes from './routes/tickets.js'
import deviceRoutes from './routes/devices.js'
import profileRoutes from './routes/profile.js'
import competitionRoutes from './routes/competitions.js'
import { createSocket } from './socket.js'

dotenv.config()

const app = express()
app.use(helmet())
app.use(
  cors({
    origin: (origin, cb) => cb(null, origin || 'http://localhost:4000'), // reflect origin for credentialed requests
    credentials: true,
  })
)
app.use(express.json({ limit: '1mb' }))
app.use(express.urlencoded({ extended: true }))
app.use(cookieParser())
app.use(morgan('dev'))

app.get('/health', (req, res) => res.json({ ok: true }))
// Auth available at /login and /auth/login
app.use('/', authRoutes)
app.use('/auth', authRoutes)
// API routes with /api prefix (matching mobile app)
app.use('/api', ticketRoutes)
app.use('/api', deviceRoutes)
app.use('/api', profileRoutes)
app.use('/api', competitionRoutes)

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

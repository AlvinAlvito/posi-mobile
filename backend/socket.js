import { Server } from 'socket.io'
import jwt from 'jsonwebtoken'
import { query } from './db.js'
import { sendPush } from './fcm.js'
import { pool } from './db.js'

const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret'
let ioInstance = null

export function createSocket(httpServer) {
  const io = new Server(httpServer, {
    cors: { origin: process.env.CORS_ORIGIN || '*', credentials: true },
  })
  ioInstance = io

  io.use((socket, next) => {
    try {
      let token =
        socket.handshake.auth?.token ||
        socket.handshake.headers.authorization?.replace('Bearer ', '')

      // fallback: read token from cookie (browser)
      if (!token && socket.handshake.headers.cookie) {
        const m = socket.handshake.headers.cookie.match(/(?:^|;\\s*)token=([^;]+)/)
        if (m) token = decodeURIComponent(m[1])
      }
      // fallback: query param token
      if (!token && socket.handshake.query && socket.handshake.query.token) {
        const q = socket.handshake.query.token
        token = Array.isArray(q) ? q[0] : q
      }

      if (!token) return next(new Error('No token'))
      const user = jwt.verify(token, JWT_SECRET)
      socket.user = user
      console.log('[socket] auth ok user', user.id, 'role', user.role)
      next()
    } catch (err) {
      console.log('[socket] auth error', err.message)
      next(err)
    }
  })

  io.on('connection', (socket) => {
    console.log('[socket] connected', socket.id, 'user', socket.user?.id, 'role', socket.user?.role)
    socket.on('join-ticket', (ticketId) => {
      console.log('[socket] join-ticket', ticketId, 'user', socket.user?.id)
      socket.join(`ticket:${ticketId}`)
    })

    socket.on('message:send', async ({ ticketId, text }) => {
      if (!ticketId || !text) return
      if (!socket.user) return // must be authenticated to send
      const senderType = socket.user.role === 'admin' ? 'admin' : 'user'
      const senderUserId = senderType === 'user' ? socket.user.id : null
      const senderAdminId = senderType === 'admin' ? socket.user.id : null
      const [insertRes] = await pool.execute(
        'INSERT INTO chat_messages (ticket_id, chat_sender_type, sender_user_id, sender_admin_id, text) VALUES (?, ?, ?, ?, ?)',
        [ticketId, senderType, senderUserId, senderAdminId, text]
      )
      const messageId = insertRes.insertId
      await pool.execute(
        'UPDATE chat_tickets SET last_message_at = NOW(), last_message_id = ? WHERE id = ?',
        [messageId, ticketId]
      )
      const [message] = await query(
        'SELECT id, ticket_id AS ticketId, chat_sender_type AS senderType, text, created_at AS createdAt FROM chat_messages WHERE id = ?',
        [messageId]
      )
      io.to(`ticket:${ticketId}`).emit('message:new', { ...message, ticket_id: ticketId })
      // push notif to ticket owner if sender is admin
      if (senderType === 'admin') {
        const rows = await query('SELECT user_id FROM chat_tickets WHERE id = ? LIMIT 1', [ticketId])
        const userId = rows[0]?.user_id
        if (userId) {
          const tokens = await query('SELECT token FROM chat_device_tokens WHERE user_id = ? AND revoked_at IS NULL', [userId])
          await sendPush(tokens.map((t) => t.token), {
            title: 'Pesan baru dari admin',
            body: text.slice(0, 80),
            data: { ticketId: String(ticketId) },
          })
        }
      }
    })
  })

  return io
}

export function getIo() {
  return ioInstance
}

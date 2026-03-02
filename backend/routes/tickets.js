import { Router } from 'express'
import { authRequired } from '../auth.js'
import { getIo } from '../socket.js'
import { query, pool } from '../db.js'
import { sendPush } from '../fcm.js'

const router = Router()

function buildAdminTicketFilters(queryObj, { includeStatus = true } = {}) {
  const { status, competition_id, topic, competition_type, q } = queryObj || {}
  const clauses = []
  const params = []

  if (includeStatus && status) {
    clauses.push('t.chat_status = ?')
    params.push(status)
  }
  if (competition_id) {
    clauses.push('t.competition_id = ?')
    params.push(competition_id)
  }
  if (topic) {
    clauses.push('t.chat_topic = ?')
    params.push(topic)
  }
  if (competition_type) {
    clauses.push('c.location_type = ?')
    params.push(competition_type)
  }
  if (q) {
    clauses.push('(u.email LIKE ? OR u.name LIKE ? OR u.whatsapp LIKE ? OR t.summary LIKE ?)')
    const like = `%${q}%`
    params.push(like, like, like, like)
  }
  return { clauses, params }
}

// GET /chat/tickets (user) or /admin/chat/tickets (admin)
 router.get('/chat/tickets', authRequired(), async (req, res) => {
  const userId = req.user.id
  const rows = await query(
    `SELECT t.id,
            t.chat_topic   AS topic,
            t.summary,
            t.chat_status  AS status,
            t.competition_id,
            t.last_message_at AS lastMessageAt,
            c.title AS competitionTitle,
            c.location_type AS competitionLocationType,
            lm.text AS lastMessage
     FROM chat_tickets t
     LEFT JOIN competitions c ON c.id = t.competition_id
     LEFT JOIN chat_messages lm ON lm.id = t.last_message_id
     WHERE t.user_id = ?
     ORDER BY t.last_message_at DESC
     LIMIT 200`,
    [userId]
  )
  res.json({ tickets: rows })
})

router.get('/admin/chat/tickets/summary', authRequired('admin'), async (req, res) => {
  const { clauses, params } = buildAdminTicketFilters(req.query, { includeStatus: false })
  let whereSql = ''
  if (clauses.length) whereSql = `WHERE ${clauses.join(' AND ')}`
  const rows = await query(
    `SELECT COUNT(*) AS total,
            SUM(CASE WHEN t.chat_status = 'Baru' THEN 1 ELSE 0 END) AS baru,
            SUM(CASE WHEN t.chat_status = 'Proses' THEN 1 ELSE 0 END) AS proses,
            SUM(CASE WHEN t.chat_status = 'Selesai' THEN 1 ELSE 0 END) AS selesai
       FROM chat_tickets t
  LEFT JOIN competitions c ON c.id = t.competition_id
  LEFT JOIN users u ON u.id = t.user_id
      ${whereSql}`,
    params
  )
  const summary = rows[0] || {}
  res.json({
    summary: {
      total: Number(summary.total || 0),
      baru: Number(summary.baru || 0),
      proses: Number(summary.proses || 0),
      selesai: Number(summary.selesai || 0),
    },
  })
})

router.get('/admin/chat/tickets', authRequired('admin'), async (req, res) => {
  const rawPage = Array.isArray(req.query.page) ? req.query.page[0] : req.query.page
  const rawPageSize = Array.isArray(req.query.pageSize) ? req.query.pageSize[0] : req.query.pageSize
  const pageNum = Number(rawPage)
  const pageSizeNum = Number(rawPageSize)
  const page = Number.isFinite(pageNum) && pageNum > 0 ? Math.floor(pageNum) : 1
  const pageSize = Number.isFinite(pageSizeNum)
    ? Math.min(100, Math.max(10, Math.floor(pageSizeNum)))
    : 50
  const offset = (page - 1) * pageSize
  const { clauses, params } = buildAdminTicketFilters(req.query, { includeStatus: true })

  let sql = `SELECT t.id,
                    t.chat_topic   AS topic,
                    t.summary,
                    t.chat_status  AS status,
                    t.competition_id,
                    t.last_message_at AS lastMessageAt,
                    c.title AS competitionTitle,
                    c.location_type AS competitionLocationType,
                    t.user_id,
                    u.name AS user_name,
                    u.email AS user_email,
                    u.whatsapp,
                    lm.text AS lastMessage
             FROM chat_tickets t
             LEFT JOIN competitions c ON c.id = t.competition_id
             LEFT JOIN users u ON u.id = t.user_id
             LEFT JOIN chat_messages lm ON lm.id = t.last_message_id`
  if (clauses.length) sql += ' WHERE ' + clauses.join(' AND ')
  // Use validated numeric literals for LIMIT/OFFSET to avoid driver/server binding issues.
  sql += ` ORDER BY t.last_message_at DESC LIMIT ${pageSize} OFFSET ${offset}`
  const rows = await query(sql, params)

  let countSql = `SELECT COUNT(*) AS total
                    FROM chat_tickets t
               LEFT JOIN competitions c ON c.id = t.competition_id
               LEFT JOIN users u ON u.id = t.user_id`
  if (clauses.length) countSql += ' WHERE ' + clauses.join(' AND ')
  const countRows = await query(countSql, params)
  const total = Number(countRows[0]?.total || 0)
  const totalPages = Math.max(1, Math.ceil(total / pageSize))
  const hasMore = page < totalPages

  res.json({
    tickets: rows,
    pagination: {
      page,
      pageSize,
      total,
      totalPages,
      hasMore,
    },
  })
})

router.post('/chat/tickets', authRequired(), async (req, res) => {
  const { competition_id, topic, summary } = req.body || {}
  if (!topic || !summary) return res.status(400).json({ message: 'Topic dan summary wajib' })
  const conn = await pool.getConnection()
  try {
    await conn.beginTransaction()
    const [insertTicket] = await conn.execute(
      'INSERT INTO chat_tickets (user_id, competition_id, chat_topic, summary, chat_status, last_message_at) VALUES (?, ?, ?, ?, ?, NOW())',
      [req.user.id, competition_id || null, topic, summary, 'Baru']
    )
    const ticketId = insertTicket.insertId
    // first message equals summary
    const [insertMsg] = await conn.execute(
      'INSERT INTO chat_messages (ticket_id, chat_sender_type, sender_user_id, text) VALUES (?, ?, ?, ?)',
      [ticketId, 'user', req.user.id, summary]
    )
    const firstMessageId = insertMsg.insertId
    await conn.execute(
      'UPDATE chat_tickets SET last_message_id = ?, last_message_at = NOW() WHERE id = ?',
      [firstMessageId, ticketId]
    )
    await conn.commit()
    const [ticket] = await query(
      `SELECT t.id,
              t.chat_topic AS topic,
              t.summary,
              t.chat_status AS status,
              t.competition_id,
              t.last_message_at AS lastMessageAt,
              COALESCE(c.title, 'Tanpa Kompetisi') AS competitionTitle,
              t.last_message_id AS lastMessageId
       FROM chat_tickets t
       LEFT JOIN competitions c ON c.id = t.competition_id
       WHERE t.id = ?`,
      [ticketId]
    )
    res.status(201).json({ ticket })
  } catch (err) {
    await conn.rollback()
    throw err
  } finally {
    conn.release()
  }
})

router.get('/chat/tickets/:id/messages', authRequired(), async (req, res) => {
  const ticketId = req.params.id
  const rows = await query(
    `SELECT id,
            ticket_id AS ticketId,
            chat_sender_type AS senderType,
            text,
            created_at AS createdAt
     FROM chat_messages
     WHERE ticket_id = ?
     ORDER BY created_at ASC
     LIMIT 1000`,
    [ticketId]
  )
  res.json({ messages: rows })
})

router.post('/chat/tickets/:id/messages', authRequired(), async (req, res) => {
  const ticketId = req.params.id
  const { text } = req.body || {}
  if (!text) return res.status(400).json({ message: 'Text wajib' })
  const [insertRes] = await pool.execute(
    'INSERT INTO chat_messages (ticket_id, chat_sender_type, sender_user_id, text) VALUES (?, ?, ?, ?)',
    [ticketId, 'user', req.user.id, text]
  )
  const messageId = insertRes.insertId
  await pool.execute('UPDATE chat_tickets SET last_message_at = NOW(), last_message_id = ? WHERE id = ?', [
    messageId,
    ticketId,
  ])
  const [message] = await query(
    'SELECT id, ticket_id AS ticketId, chat_sender_type AS senderType, text, created_at AS createdAt FROM chat_messages WHERE id = ?',
    [messageId]
  )
  const io = getIo()
  if (io) io.to(`ticket:${ticketId}`).emit('message:new', { ...message, ticket_id: Number(ticketId) })
  res.status(201).json({ ok: true, message })
})

// Admin send message
router.post('/admin/chat/tickets/:id/messages', authRequired('admin'), async (req, res) => {
  const ticketId = req.params.id
  const { text } = req.body || {}
  if (!text) return res.status(400).json({ message: 'Text wajib' })
  const [insertRes] = await pool.execute(
    'INSERT INTO chat_messages (ticket_id, chat_sender_type, sender_admin_id, text) VALUES (?, ?, ?, ?)',
    [ticketId, 'admin', req.user.id, text]
  )
  const messageId = insertRes.insertId
  await pool.execute('UPDATE chat_tickets SET last_message_at = NOW(), last_message_id = ? WHERE id = ?', [
    messageId,
    ticketId,
  ])
  const [message] = await query(
    'SELECT id, ticket_id AS ticketId, chat_sender_type AS senderType, text, created_at AS createdAt FROM chat_messages WHERE id = ?',
    [messageId]
  )
  const io = getIo()
  if (io) io.to(`ticket:${ticketId}`).emit('message:new', { ...message, ticket_id: Number(ticketId) })

  // Push notif ke pemilik tiket
  try {
    const rows = await query('SELECT user_id FROM chat_tickets WHERE id = ? LIMIT 1', [ticketId])
    const userId = rows[0]?.user_id
    if (userId) {
      if (io) io.to(`user:${userId}`).emit('message:new', { ...message, ticket_id: Number(ticketId) })
      const tokens = await query(
        'SELECT token FROM chat_device_tokens WHERE user_id = ? AND (revoked_at IS NULL OR revoked_at > NOW())',
        [userId]
      )
      const tokenList = tokens.map((t) => t.token)
      if (tokenList.length) {
        console.log('[push] admin->user REST', { ticketId, userId, tokens: tokenList.length })
        await sendPush(tokenList, {
          title: 'Pesan baru dari admin',
          body: text.slice(0, 80),
          data: { ticketId: String(ticketId) },
        })
      } else {
        console.log('[push] admin->user REST no tokens', { ticketId, userId })
      }
    }
  } catch (err) {
    console.error('[push] admin->user REST error', err)
  }

  res.status(201).json({ ok: true, message })
})

// Admin update status tiket
router.patch('/admin/chat/tickets/:id/status', authRequired('admin'), async (req, res) => {
  const ticketId = req.params.id
  const status = req.body?.status
  if (!['Baru', 'Proses', 'Selesai'].includes(status)) return res.status(400).json({ message: 'Status tidak valid' })
  await pool.execute('UPDATE chat_tickets SET chat_status = ? WHERE id = ?', [status, ticketId])
  res.json({ ok: true, status })
})

// Tandai tiket telah dibaca (ubah status ke Proses)
router.patch('/chat/tickets/:id/read', authRequired(), async (req, res) => {
  const ticketId = req.params.id
  const status = req.body?.status || 'Proses'
  const role = req.user.role || 'user'
  const fieldClause = role === 'admin' ? '' : 'AND user_id = ?'
  const params = role === 'admin' ? [status, ticketId] : [status, ticketId, req.user.id]
  await pool.execute(
    `UPDATE chat_tickets SET chat_status = ? WHERE id = ? ${fieldClause}`,
    params
  )
  res.json({ ok: true })
})

// User can escalate status manually
router.patch('/chat/tickets/:id/status', authRequired(), async (req, res) => {
  const ticketId = req.params.id
  const status = req.body?.status
  if (!['Baru', 'Proses', 'Selesai'].includes(status)) return res.status(400).json({ message: 'Status tidak valid' })
  await pool.execute('UPDATE chat_tickets SET chat_status = ? WHERE id = ? AND user_id = ?', [status, ticketId, req.user.id])
  res.json({ ok: true })
})

export default router

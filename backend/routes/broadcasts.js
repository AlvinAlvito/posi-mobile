import { Router } from 'express'
import { authRequired } from '../auth.js'
import { pool, query } from '../db.js'
import { sendPush } from '../fcm.js'
import { getIo } from '../socket.js'

const router = Router()

const BROADCAST_BATCH_SIZE = Math.max(1, Number(process.env.BROADCAST_BATCH_SIZE || 100))
const TARGET_INSERT_CHUNK = 1000
let workerRunning = false
let queueSchemaSupported = null

async function hasColumn(tableName, columnName) {
  const rows = await query(
    `SELECT 1
       FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = ?
        AND COLUMN_NAME = ?
      LIMIT 1`,
    [tableName, columnName]
  )
  return rows.length > 0
}

async function supportsQueueSchema() {
  if (queueSchemaSupported !== null) return queueSchemaSupported
  try {
    const hasBroadcastStatus = await hasColumn('chat_broadcasts', 'status')
    const hasTargetStatus = await hasColumn('chat_broadcast_targets', 'status')
    queueSchemaSupported = hasBroadcastStatus && hasTargetStatus
    if (!queueSchemaSupported) {
      console.warn('[broadcast-worker] queue schema tidak lengkap, fallback ke mode legacy')
    }
  } catch (err) {
    queueSchemaSupported = false
    console.warn('[broadcast-worker] gagal cek schema, fallback ke mode legacy', err?.message || err)
  }
  return queueSchemaSupported
}

function pickTopic({ topic, title, dataJson }) {
  if (['Pendaftaran', 'Pemesanan', 'Lainnya'].includes(topic)) return topic
  if (['Pendaftaran', 'Pemesanan', 'Lainnya'].includes(title)) return title
  if (dataJson) {
    try {
      const parsed = JSON.parse(dataJson)
      if (['Pendaftaran', 'Pemesanan', 'Lainnya'].includes(parsed?.topic)) return parsed.topic
    } catch (_) {}
  }
  return 'Lainnya'
}

function toNumber(value) {
  const n = Number(value)
  return Number.isFinite(n) ? n : 0
}

async function fetchBroadcastProgressRows(limit = 100) {
  return query(
    `SELECT b.id,
            b.title,
            b.body,
            b.competition_id AS competitionId,
            b.status,
            b.sent_at AS sentAt,
            b.created_at AS createdAt,
            c.title AS competitionTitle,
            COUNT(t.id) AS totalTargets,
            SUM(CASE WHEN t.status = 'sent' THEN 1 ELSE 0 END) AS sentTargets,
            SUM(CASE WHEN t.status = 'failed' THEN 1 ELSE 0 END) AS failedTargets,
            SUM(CASE WHEN t.status = 'pending' THEN 1 ELSE 0 END) AS pendingTargets
       FROM chat_broadcasts b
  LEFT JOIN competitions c ON c.id = b.competition_id
  LEFT JOIN chat_broadcast_targets t ON t.broadcast_id = b.id
   GROUP BY b.id, b.title, b.body, b.competition_id, b.status, b.sent_at, b.created_at, c.title
   ORDER BY b.created_at DESC
      LIMIT ?`,
    [limit]
  )
}

async function fetchBroadcastProgressById(id) {
  const rows = await query(
    `SELECT b.id,
            b.title,
            b.body,
            b.competition_id AS competitionId,
            b.status,
            b.sent_at AS sentAt,
            b.created_at AS createdAt,
            c.title AS competitionTitle,
            COUNT(t.id) AS totalTargets,
            SUM(CASE WHEN t.status = 'sent' THEN 1 ELSE 0 END) AS sentTargets,
            SUM(CASE WHEN t.status = 'failed' THEN 1 ELSE 0 END) AS failedTargets,
            SUM(CASE WHEN t.status = 'pending' THEN 1 ELSE 0 END) AS pendingTargets
       FROM chat_broadcasts b
  LEFT JOIN competitions c ON c.id = b.competition_id
  LEFT JOIN chat_broadcast_targets t ON t.broadcast_id = b.id
      WHERE b.id = ?
   GROUP BY b.id, b.title, b.body, b.competition_id, b.status, b.sent_at, b.created_at, c.title
      LIMIT 1`,
    [id]
  )
  return rows[0] || null
}

function mapProgressRow(r) {
  const totalTargets = toNumber(r.totalTargets)
  const sentTargets = toNumber(r.sentTargets)
  const failedTargets = toNumber(r.failedTargets)
  const pendingTargets = toNumber(r.pendingTargets)
  const processedTargets = sentTargets + failedTargets
  const progressPct = totalTargets > 0 ? Math.round((processedTargets / totalTargets) * 100) : 0
  return {
    ...r,
    totalTargets,
    sentTargets,
    failedTargets,
    pendingTargets,
    processedTargets,
    progressPct,
  }
}

async function sendLegacyBroadcast({ adminId, competitionId, subject, message, topicVal }) {
  const targets = await query(
    'SELECT DISTINCT COALESCE(userid, buyer) AS user_id FROM transactions WHERE competition_id = ?',
    [competitionId]
  )
  const userIds = targets.map((t) => Number(t.user_id)).filter(Boolean)
  if (!userIds.length) return { ok: false, message: 'Tidak ada peserta untuk kompetisi ini' }

  let broadcastId = null
  const realtimeEvents = []
  const conn = await pool.getConnection()
  try {
    await conn.beginTransaction()
    const [bRes] = await conn.execute(
      'INSERT INTO chat_broadcasts (admin_id, title, body, competition_id, created_at) VALUES (?, ?, ?, ?, NOW())',
      [adminId, subject, message, competitionId]
    )
    broadcastId = bRes.insertId

    for (const uid of userIds) {
      const [ticketRes] = await conn.execute(
        'INSERT INTO chat_tickets (user_id, competition_id, chat_topic, summary, chat_status, last_message_at) VALUES (?, ?, ?, ?, ?, NOW())',
        [uid, competitionId, topicVal, subject, 'Baru']
      )
      const ticketId = ticketRes.insertId
      const [msgRes] = await conn.execute(
        'INSERT INTO chat_messages (ticket_id, chat_sender_type, sender_admin_id, text, created_at) VALUES (?, ?, ?, ?, NOW())',
        [ticketId, 'admin', adminId, message]
      )
      const msgId = msgRes.insertId
      await conn.execute('UPDATE chat_tickets SET last_message_id = ?, last_message_at = NOW() WHERE id = ?', [
        msgId,
        ticketId,
      ])
      await conn.execute(
        'INSERT INTO chat_broadcast_targets (broadcast_id, user_id, ticket_id, created_at) VALUES (?, ?, ?, NOW())',
        [broadcastId, uid, ticketId]
      )
      realtimeEvents.push({
        userId: uid,
        ticketId,
        message: {
          id: msgId,
          ticketId,
          senderType: 'admin',
          text: message,
          createdAt: new Date().toISOString(),
        },
      })
    }
    await conn.commit()
  } catch (err) {
    await conn.rollback()
    throw err
  } finally {
    conn.release()
  }

  try {
    const io = getIo()
    if (io) {
      for (const evt of realtimeEvents) {
        io.to(`ticket:${evt.ticketId}`).emit('message:new', { ...evt.message, ticket_id: evt.ticketId })
        io.to(`user:${evt.userId}`).emit('message:new', { ...evt.message, ticket_id: evt.ticketId })
      }
    }
    for (const uid of userIds) {
      const tokens = await query(
        'SELECT token FROM chat_device_tokens WHERE user_id = ? AND (revoked_at IS NULL OR revoked_at > NOW())',
        [uid]
      )
      const tokenList = tokens.map((t) => t.token)
      if (tokenList.length) {
        await sendPush(tokenList, {
          title: subject,
          body: String(message || '').slice(0, 120),
          data: { type: 'broadcast', competitionId: String(competitionId) },
        })
      }
    }
  } catch (err) {
    console.warn('Broadcast push error (legacy mode diabaikan)', err)
  }

  return { ok: true, broadcastId, totalTargets: userIds.length }
}

function startWorker() {
  if (workerRunning) return
  setImmediate(async () => {
    if (workerRunning) return
    workerRunning = true
    try {
      const enabled = await supportsQueueSchema()
      if (!enabled) return
      while (true) {
        const rows = await query(
          `SELECT id,
                  admin_id AS adminId,
                  title,
                  body,
                  competition_id AS competitionId,
                  data_json AS dataJson
             FROM chat_broadcasts
            WHERE status = 'sending'
         ORDER BY created_at ASC
            LIMIT 1`
        )
        const job = rows[0]
        if (!job) break
        await processBroadcastBatch(job)
      }
    } catch (err) {
      if (err?.code === 'ER_BAD_FIELD_ERROR') {
        queueSchemaSupported = false
        console.warn('[broadcast-worker] schema tidak mendukung queue, worker dimatikan')
      } else {
        console.error('[broadcast-worker] fatal', err)
      }
    } finally {
      workerRunning = false
    }
  })
}

async function processBroadcastBatch(job) {
  const targets = await query(
    `SELECT id, user_id AS userId
       FROM chat_broadcast_targets
      WHERE broadcast_id = ?
        AND status = 'pending'
   ORDER BY id ASC
      LIMIT ?`,
    [job.id, BROADCAST_BATCH_SIZE]
  )

  if (!targets.length) {
    await finalizeBroadcast(job.id)
    return
  }

  const userIds = [...new Set(targets.map((t) => Number(t.userId)).filter(Boolean))]
  const tokenMap = new Map()
  if (userIds.length) {
    const placeholders = userIds.map(() => '?').join(', ')
    const tokenRows = await query(
      `SELECT user_id AS userId, token
         FROM chat_device_tokens
        WHERE user_id IN (${placeholders})
          AND (revoked_at IS NULL OR revoked_at > NOW())`,
      userIds
    )
    for (const row of tokenRows) {
      const uid = Number(row.userId)
      if (!tokenMap.has(uid)) tokenMap.set(uid, [])
      tokenMap.get(uid).push(row.token)
    }
  }

  const io = getIo()
  const topic = pickTopic({ title: job.title, dataJson: job.dataJson })
  const conn = await pool.getConnection()
  try {
    for (const target of targets) {
      const userId = Number(target.userId)
      try {
        await conn.beginTransaction()
        const [ticketRes] = await conn.execute(
          'INSERT INTO chat_tickets (user_id, competition_id, chat_topic, summary, chat_status, last_message_at) VALUES (?, ?, ?, ?, ?, NOW())',
          [userId, job.competitionId || null, topic, job.title, 'Baru']
        )
        const ticketId = ticketRes.insertId
        const [msgRes] = await conn.execute(
          'INSERT INTO chat_messages (ticket_id, chat_sender_type, sender_admin_id, text, created_at) VALUES (?, ?, ?, ?, NOW())',
          [ticketId, 'admin', job.adminId, job.body]
        )
        const messageId = msgRes.insertId
        await conn.execute(
          'UPDATE chat_tickets SET last_message_id = ?, last_message_at = NOW() WHERE id = ?',
          [messageId, ticketId]
        )
        await conn.execute(
          "UPDATE chat_broadcast_targets SET ticket_id = ?, status = 'sent', error = NULL, sent_at = NOW() WHERE id = ?",
          [ticketId, target.id]
        )
        await conn.commit()

        const messagePayload = {
          id: messageId,
          ticketId,
          senderType: 'admin',
          text: job.body,
          createdAt: new Date().toISOString(),
        }
        if (io) {
          io.to(`ticket:${ticketId}`).emit('message:new', { ...messagePayload, ticket_id: ticketId })
          io.to(`user:${userId}`).emit('message:new', { ...messagePayload, ticket_id: ticketId })
        }

        const tokens = tokenMap.get(userId) || []
        if (tokens.length) {
          await sendPush(tokens, {
            title: job.title,
            body: String(job.body || '').slice(0, 120),
            data: {
              type: 'broadcast',
              competitionId: String(job.competitionId || ''),
              ticketId: String(ticketId),
            },
          })
        }
      } catch (err) {
        try {
          await conn.rollback()
        } catch (_) {}
        const errMsg = String(err?.message || err).slice(0, 1000)
        await conn.execute(
          "UPDATE chat_broadcast_targets SET status = 'failed', error = ? WHERE id = ?",
          [errMsg, target.id]
        )
      }
    }
  } finally {
    conn.release()
  }

  await finalizeBroadcast(job.id)
}

async function finalizeBroadcast(broadcastId) {
  const rows = await query(
    `SELECT COUNT(*) AS totalTargets,
            SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) AS pendingTargets,
            SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failedTargets
       FROM chat_broadcast_targets
      WHERE broadcast_id = ?`,
    [broadcastId]
  )
  const stats = rows[0] || {}
  const pending = toNumber(stats.pendingTargets)
  const failed = toNumber(stats.failedTargets)

  if (pending > 0) {
    await query("UPDATE chat_broadcasts SET status = 'sending' WHERE id = ?", [broadcastId])
    return
  }

  if (failed > 0) {
    await query("UPDATE chat_broadcasts SET status = 'failed' WHERE id = ?", [broadcastId])
    return
  }

  await query("UPDATE chat_broadcasts SET status = 'sent', sent_at = NOW() WHERE id = ?", [broadcastId])
}

// List latest broadcasts with target progress.
router.get('/admin/broadcasts', authRequired('admin'), async (_req, res) => {
  try {
    const rows = await fetchBroadcastProgressRows(100)
    res.json({ broadcasts: rows.map(mapProgressRow) })
  } catch (err) {
    if (err?.code !== 'ER_BAD_FIELD_ERROR') throw err
    // Fallback untuk schema lama yang belum punya kolom status/error di targets.
    const rows = await query(
      `SELECT b.id,
              b.title,
              b.body,
              b.competition_id AS competitionId,
              b.created_at AS createdAt,
              c.title AS competitionTitle,
              (SELECT COUNT(*) FROM chat_broadcast_targets t WHERE t.broadcast_id = b.id) AS totalTargets
         FROM chat_broadcasts b
    LEFT JOIN competitions c ON c.id = b.competition_id
     ORDER BY b.created_at DESC
        LIMIT 100`
    )
    const mapped = rows.map((r) => ({
      ...r,
      status: 'sent',
      sentAt: r.createdAt,
      totalTargets: toNumber(r.totalTargets),
      sentTargets: toNumber(r.totalTargets),
      failedTargets: 0,
      pendingTargets: 0,
      processedTargets: toNumber(r.totalTargets),
      progressPct: 100,
    }))
    res.json({ broadcasts: mapped })
  }
})

// Create broadcast as queued job and process in background.
router.post('/admin/broadcasts', authRequired('admin'), async (req, res) => {
  const adminId = req.user.id
  const { competition_id, subject, message, topic } = req.body || {}
  if (!competition_id) return res.status(400).json({ message: 'competition_id wajib' })
  if (!subject) return res.status(400).json({ message: 'Perihal wajib' })
  if (!message) return res.status(400).json({ message: 'Pesan wajib' })

  const topicVal = pickTopic({ topic, title: subject, dataJson: null })
  const queueEnabled = await supportsQueueSchema()
  if (!queueEnabled) {
    try {
      const legacy = await sendLegacyBroadcast({
        adminId,
        competitionId: competition_id,
        subject,
        message,
        topicVal,
      })
      if (!legacy.ok) return res.status(400).json({ message: legacy.message || 'Broadcast gagal dikirim' })
      return res.status(201).json({ ok: true, broadcastId: legacy.broadcastId, totalTargets: legacy.totalTargets, status: 'sent' })
    } catch (err) {
      console.error('Broadcast legacy gagal', err)
      return res.status(500).json({ message: 'Broadcast gagal dikirim' })
    }
  }

  const targets = await query(
    'SELECT DISTINCT COALESCE(userid, buyer) AS user_id FROM transactions WHERE competition_id = ?',
    [competition_id]
  )
  const userIds = targets.map((t) => Number(t.user_id)).filter(Boolean)
  if (!userIds.length) return res.status(400).json({ message: 'Tidak ada peserta untuk kompetisi ini' })

  let broadcastId = null
  const conn = await pool.getConnection()
  try {
    await conn.beginTransaction()
    const [bRes] = await conn.execute(
      'INSERT INTO chat_broadcasts (admin_id, title, body, target_scope, competition_id, status, data_json) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [adminId, subject, message, 'competition', competition_id, 'sending', JSON.stringify({ topic: topicVal })]
    )
    broadcastId = bRes.insertId

    for (let i = 0; i < userIds.length; i += TARGET_INSERT_CHUNK) {
      const chunk = userIds.slice(i, i + TARGET_INSERT_CHUNK)
      const placeholders = chunk.map(() => '(?, ?, ?, NOW())').join(', ')
      const params = []
      for (const userId of chunk) {
        params.push(broadcastId, userId, 'pending')
      }
      await conn.execute(
        `INSERT INTO chat_broadcast_targets (broadcast_id, user_id, status, created_at) VALUES ${placeholders}`,
        params
      )
    }

    await conn.commit()
  } catch (err) {
    await conn.rollback()
    console.error('Broadcast enqueue gagal', err)
    return res.status(500).json({ message: 'Broadcast gagal diantrikan' })
  } finally {
    conn.release()
  }

  startWorker()
  res.status(202).json({ ok: true, broadcastId, totalTargets: userIds.length, status: 'sending' })
})

// Resume failed broadcast targets.
router.post('/admin/broadcasts/:id/resume', authRequired('admin'), async (req, res) => {
  if (!(await supportsQueueSchema())) {
    return res.status(400).json({ message: 'Resume hanya tersedia jika schema queue aktif' })
  }
  const broadcastId = Number(req.params.id)
  if (!broadcastId) return res.status(400).json({ message: 'broadcast id tidak valid' })

  const [existing] = await query('SELECT id FROM chat_broadcasts WHERE id = ? LIMIT 1', [broadcastId])
  if (!existing) return res.status(404).json({ message: 'Broadcast tidak ditemukan' })

  await query("UPDATE chat_broadcast_targets SET status = 'pending', error = NULL WHERE broadcast_id = ? AND status = 'failed'", [
    broadcastId,
  ])
  await query("UPDATE chat_broadcasts SET status = 'sending' WHERE id = ?", [broadcastId])

  startWorker()
  const progress = await fetchBroadcastProgressById(broadcastId)
  res.json({ ok: true, broadcast: progress ? mapProgressRow(progress) : null })
})

// List broadcast targets (default failed targets) with simple pagination/filter.
router.get('/admin/broadcasts/:id/targets', authRequired('admin'), async (req, res) => {
  if (!(await supportsQueueSchema())) {
    return res.status(400).json({ message: 'Detail target hanya tersedia jika schema queue aktif' })
  }
  const broadcastId = Number(req.params.id)
  if (!broadcastId) return res.status(400).json({ message: 'broadcast id tidak valid' })

  const status = String(req.query.status || 'failed')
  const page = Math.max(1, Number(req.query.page || 1))
  const pageSize = Math.min(200, Math.max(1, Number(req.query.pageSize || 50)))
  const q = String(req.query.q || '').trim()
  const offset = (page - 1) * pageSize
  const allowedStatuses = new Set(['pending', 'sent', 'failed'])
  const safeStatus = allowedStatuses.has(status) ? status : 'failed'

  const clauses = ['t.broadcast_id = ?', 't.status = ?']
  const params = [broadcastId, safeStatus]
  if (q) {
    clauses.push('(u.name LIKE ? OR u.email LIKE ? OR t.error LIKE ?)')
    const like = `%${q}%`
    params.push(like, like, like)
  }
  const whereSql = clauses.join(' AND ')

  const countRows = await query(
    `SELECT COUNT(*) AS total
       FROM chat_broadcast_targets t
  LEFT JOIN users u ON u.id = t.user_id
      WHERE ${whereSql}`,
    params
  )
  const total = toNumber(countRows[0]?.total)

  const rows = await query(
    `SELECT t.id,
            t.broadcast_id AS broadcastId,
            t.user_id AS userId,
            t.ticket_id AS ticketId,
            t.status,
            t.error,
            t.sent_at AS sentAt,
            t.updated_at AS updatedAt,
            u.name AS userName,
            u.email AS userEmail
       FROM chat_broadcast_targets t
  LEFT JOIN users u ON u.id = t.user_id
      WHERE ${whereSql}
   ORDER BY t.id ASC
      LIMIT ? OFFSET ?`,
    [...params, pageSize, offset]
  )

  res.json({
    targets: rows,
    pagination: {
      page,
      pageSize,
      total,
      totalPages: Math.max(1, Math.ceil(total / pageSize)),
    },
  })
})

// Retry only selected failed target ids for a broadcast.
router.post('/admin/broadcasts/:id/retry-targets', authRequired('admin'), async (req, res) => {
  if (!(await supportsQueueSchema())) {
    return res.status(400).json({ message: 'Retry target hanya tersedia jika schema queue aktif' })
  }
  const broadcastId = Number(req.params.id)
  if (!broadcastId) return res.status(400).json({ message: 'broadcast id tidak valid' })

  const targetIds = Array.isArray(req.body?.target_ids)
    ? req.body.target_ids.map((v) => Number(v)).filter((v) => Number.isFinite(v) && v > 0)
    : []
  if (!targetIds.length) return res.status(400).json({ message: 'target_ids wajib diisi' })

  const placeholders = targetIds.map(() => '?').join(', ')
  const updateRes = await query(
    `UPDATE chat_broadcast_targets
        SET status = 'pending', error = NULL
      WHERE broadcast_id = ?
        AND status = 'failed'
        AND id IN (${placeholders})`,
    [broadcastId, ...targetIds]
  )

  if (!toNumber(updateRes.affectedRows)) {
    return res.status(400).json({ message: 'Tidak ada target gagal yang dapat di-retry' })
  }

  await query("UPDATE chat_broadcasts SET status = 'sending' WHERE id = ?", [broadcastId])
  startWorker()

  const progress = await fetchBroadcastProgressById(broadcastId)
  res.json({
    ok: true,
    retried: toNumber(updateRes.affectedRows),
    broadcast: progress ? mapProgressRow(progress) : null,
  })
})

// Resume unfinished queued jobs after backend restart.
startWorker()

export default router

import { Router } from 'express'
import { authRequired } from '../auth.js'
import { query } from '../db.js'

const router = Router()

// GET /api/results/offline - hasil kompetisi milik user (exam sessions only)
router.get('/results/offline', authRequired(), async (req, res) => {
  res.set('Cache-Control', 'no-store')
  const userId = req.user.id
  const page = Math.max(1, Number.parseInt(`${req.query.page || '1'}`, 10) || 1)
  const pageSize = Math.min(
    50,
    Math.max(1, Number.parseInt(`${req.query.pageSize || '5'}`, 10) || 5)
  )
  const offset = (page - 1) * pageSize

  const whereClause = `e.userid = ?
     AND (
       e.is_finish = 1
       OR e.ranking IS NOT NULL
       OR e.nilai IS NOT NULL
       OR COALESCE(e.total_score, 0) > 0
     )`

  const [{ total }] = await query(
    `SELECT COUNT(*) AS total
       FROM exam_sessions e
      WHERE ${whereClause}`,
    [userId]
  )

  const rows = await query(
    `SELECT DISTINCT e.id,
            e.competition_id,
            e.study_id,
            e.nilai,
            e.ranking      AS ranking,
            1              AS finalized,
            e.updated_at   AS finalized_at,
            e.updated_at   AS updated_at,
            e.created_at   AS scoreCreatedAt,
            c.title        AS competitionTitle,
            c.date         AS competitionDate,
            c.location_type AS competitionLocationType,
            p.name         AS subjectName,
            l.level_name   AS levelName,
            l.jenjang      AS levelJenjang,
            COALESCE(e.medali, '') AS medali,
            COALESCE(e.updated_at, e.created_at) AS sortKey
       FROM exam_sessions e
     LEFT JOIN competitions c ON c.id = e.competition_id
     LEFT JOIN studies st ON st.id = e.study_id
     LEFT JOIN pelajarans p ON p.id = st.pelajaran_id
     LEFT JOIN levels l ON l.id = st.level_id
      WHERE ${whereClause}
     ORDER BY (ranking IS NOT NULL) DESC, sortKey DESC
     LIMIT ${pageSize} OFFSET ${offset}`,
    [userId]
  )
  const totalRows = Number(total || 0)
  const totalPages = Math.max(1, Math.ceil(totalRows / pageSize))
  console.log('[results] user', userId, 'rows', rows.length, 'page', page, 'size', pageSize)
  res.json({
    results: rows,
    pagination: {
      page,
      pageSize,
      total: totalRows,
      totalPages,
      hasNextPage: page < totalPages,
      hasPrevPage: page > 1,
    },
  })
})

export default router

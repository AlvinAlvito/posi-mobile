import { Router } from 'express'
import { authRequired } from '../auth.js'
import { query } from '../db.js'

const router = Router()

// GET /api/results/offline - hasil kompetisi offline milik user
router.get('/results/offline', authRequired(), async (req, res) => {
  res.set('Cache-Control', 'no-store')
  const userId = req.user.id
  const rows = await query(
    `(
        SELECT DISTINCT s.id,
               s.competition_id,
               s.study_id,
               s.nilai,
               s.ranking,
               s.finalized,
               s.finalized_at,
               s.updated_at,
               s.created_at      AS scoreCreatedAt,
               c.title           AS competitionTitle,
               c.date            AS competitionDate,
               c.location_type   AS competitionLocationType,
               p.name            AS subjectName,
               l.level_name      AS levelName,
               l.jenjang         AS levelJenjang,
               ''                AS medali,
               COALESCE(s.finalized_at, s.updated_at, s.created_at, m.created_at) AS sortKey
          FROM offline_result_scores s
     LEFT JOIN competitions c ON c.id = s.competition_id
     LEFT JOIN studies st ON st.id = s.study_id
     LEFT JOIN pelajarans p ON p.id = st.pelajaran_id
     LEFT JOIN levels l ON l.id = st.level_id
     LEFT JOIN offline_result_matches m
            ON m.competition_id = s.competition_id
           AND m.study_id = s.study_id
           AND m.user_id = ?
     LEFT JOIN transactions t
            ON t.id = s.transaction_id
           OR (t.competition_id = s.competition_id AND t.study_id = s.study_id)
         WHERE (s.user_id = ?
                OR m.user_id = ?
                OR t.userid = ?
                OR t.buyer = ?)
     )
     UNION ALL
     (
        SELECT DISTINCT m.id,
               m.competition_id,
               m.study_id,
               r.nilai,
               NULL           AS ranking,
               1              AS finalized,
               r.created_at   AS finalized_at,
               r.created_at   AS updated_at,
               r.created_at   AS scoreCreatedAt,
               c.title        AS competitionTitle,
               c.date         AS competitionDate,
               c.location_type AS competitionLocationType,
               p.name         AS subjectName,
               l.level_name   AS levelName,
               l.jenjang      AS levelJenjang,
               ''             AS medali,
               COALESCE(r.created_at, m.created_at) AS sortKey
          FROM offline_result_matches m
     INNER JOIN offline_result_rows_raw r ON r.id = m.raw_row_id
     LEFT JOIN competitions c ON c.id = m.competition_id
     LEFT JOIN studies st ON st.id = m.study_id
     LEFT JOIN pelajarans p ON p.id = st.pelajaran_id
     LEFT JOIN levels l ON l.id = st.level_id
         WHERE m.user_id = ?
     )
     ORDER BY sortKey DESC
     LIMIT 50`,
    [userId, userId, userId, userId, userId, userId]
  )
  console.log('[results] user', userId, 'rows', rows.length)
  res.json({ results: rows })
})

export default router

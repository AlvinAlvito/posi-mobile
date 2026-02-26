import { Router } from 'express'
import { authRequired } from '../auth.js'
import { query } from '../db.js'

const router = Router()

// List competitions (active)
router.get('/competitions', authRequired(), async (req, res) => {
  const rows = await query(
    `SELECT id, title
     FROM competitions
     WHERE is_active = 1
     ORDER BY title ASC
     LIMIT 500`
  )
  res.json({ competitions: rows })
})

// List competitions aktif & masih dalam masa pendaftaran
router.get('/competitions/active', authRequired(), async (req, res) => {
  const { location_type } = req.query
  const params = []
  let sql = `SELECT id,
                    title,
                    date,
                    start_registration_date,
                    finish_registration_date,
                    price,
                    image,
                    location_type
               FROM competitions
              WHERE is_active = 1
                AND (CURDATE() BETWEEN start_registration_date AND finish_registration_date)`
  if (location_type) {
    sql += ' AND location_type = ?'
    params.push(location_type)
  }
  sql += ' ORDER BY start_registration_date ASC LIMIT 100'
  const rows = await query(sql, params)
  res.json({ competitions: rows })
})

export default router

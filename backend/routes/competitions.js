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

export default router

import { Router } from 'express'
import { query } from '../db.js'

const router = Router()

// List latest news (public)
router.get('/news', async (_req, res) => {
  const rows = await query(
    `SELECT id,
            title,
            category,
            content,
            image,
            slug,
            created_at AS createdAt
       FROM beritas
      WHERE is_status IS NULL OR is_status = 1
      ORDER BY created_at DESC
      LIMIT 50`
  )
  res.json({ news: rows })
})

// Detail by id or slug
router.get('/news/:idOrSlug', async (req, res) => {
  const { idOrSlug } = req.params
  let rows
  if (/^\\d+$/.test(idOrSlug)) {
    rows = await query(
      `SELECT id, title, category, content, image, slug, created_at AS createdAt
         FROM beritas
        WHERE id = ?
        LIMIT 1`,
      [Number(idOrSlug)]
    )
  } else {
    rows = await query(
      `SELECT id, title, category, content, image, slug, created_at AS createdAt
         FROM beritas
        WHERE slug = ?
        LIMIT 1`,
      [idOrSlug]
    )
  }
  if (!rows.length) return res.status(404).json({ message: 'Berita tidak ditemukan' })
  res.json({ news: rows[0] })
})

export default router

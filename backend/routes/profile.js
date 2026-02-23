import { Router } from 'express'
import { query } from '../db.js'
import { authRequired } from '../auth.js'

const router = Router()

// Require auth; uses user id from token
router.get('/profile', authRequired(), async (req, res) => {
  const userId = req.user?.id
  if (!userId) return res.status(401).json({ message: 'Unauthorized' })
  const [user] = await query(
    `SELECT id, name, email, whatsapp, level_id, kelas_id, tanggal_lahir, agama,
            jenis_kelamin, provinsi, kabupaten, kecamatan, nama_sekolah
       FROM users WHERE id = ? LIMIT 1`,
    [userId]
  )
  if (!user) return res.status(404).json({ message: 'User tidak ditemukan' })

  const levels = await query('SELECT id, level_name FROM levels')
  const kelas = await query('SELECT id, nama_kelas FROM kelas')

  const provinces = await query(
    'SELECT DISTINCT province_code AS code, province_name AS name FROM provinces ORDER BY province_name'
  )
  const cities = await query(
    'SELECT DISTINCT regency_code AS code, regency_name AS name FROM provinces ORDER BY regency_name'
  )
  const districts = await query(
    'SELECT DISTINCT district_code AS code, district_name AS name FROM provinces ORDER BY district_name'
  )

  res.json({
    user,
    levels,
    kelas,
    geographic: { provinces, cities, districts },
  })
})

export default router

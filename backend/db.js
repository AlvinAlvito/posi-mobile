import mysql from 'mysql2/promise'
import dotenv from 'dotenv'

dotenv.config()

const url = process.env.DATABASE_URL
if (!url) {
  throw new Error('DATABASE_URL is required')
}

const parsed = new URL(url.replace('mysql://', 'mysql://'))

export const pool = mysql.createPool({
  host: parsed.hostname,
  port: Number(parsed.port || 3306),
  user: decodeURIComponent(parsed.username),
  password: decodeURIComponent(parsed.password),
  database: parsed.pathname.replace('/', ''),
  waitForConnections: true,
  connectionLimit: 10,
  charset: 'utf8mb4',
})

export async function query(sql, params = []) {
  const [rows] = await pool.execute(sql, params)
  return rows
}

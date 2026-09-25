export async function listOrders(db, userId, limit = 50) {
  const n = Math.min(Math.max(Number.parseInt(limit, 10) || 50, 1), 200);
  return db.query(
    "SELECT id, total, created_at FROM orders WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2",
    [userId, n],
  );
}

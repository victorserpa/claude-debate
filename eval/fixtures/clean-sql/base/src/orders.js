export async function listOrders(db, userId) {
  return db.query("SELECT id, total FROM orders WHERE user_id = $1 LIMIT 50", [userId]);
}

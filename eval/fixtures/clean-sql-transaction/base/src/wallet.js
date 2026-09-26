export async function balance(db, userId) {
  const { rows } = await db.query("SELECT balance FROM wallets WHERE user_id = $1", [userId]);
  return rows[0]?.balance ?? 0;
}

export async function balance(db, userId) {
  const { rows } = await db.query("SELECT balance FROM wallets WHERE user_id = $1", [userId]);
  return rows[0]?.balance ?? 0;
}

export async function spend(db, userId, amount) {
  const current = await balance(db, userId);
  if (current < amount) throw new Error("insufficient funds");
  await db.query("UPDATE wallets SET balance = $1 WHERE user_id = $2", [current - amount, userId]);
}

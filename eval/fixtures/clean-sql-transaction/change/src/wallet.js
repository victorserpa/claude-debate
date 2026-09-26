export async function balance(db, userId) {
  const { rows } = await db.query("SELECT balance FROM wallets WHERE user_id = $1", [userId]);
  return rows[0]?.balance ?? 0;
}

// One statement: the check and the write happen together, so two spends
// at once cannot both pass the check.
export async function spend(db, userId, amount) {
  if (!Number.isInteger(amount) || amount <= 0) throw new Error("amount must be a positive whole number");
  const { rowCount } = await db.query(
    "UPDATE wallets SET balance = balance - $1 WHERE user_id = $2 AND balance >= $1",
    [amount, userId],
  );
  if (rowCount === 0) throw new Error("insufficient funds");
}

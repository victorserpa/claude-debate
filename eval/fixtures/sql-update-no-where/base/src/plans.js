export async function setPlan(db, accountId, plan) {
  await db.query("UPDATE accounts SET plan = $1 WHERE id = $2", [plan, accountId]);
}

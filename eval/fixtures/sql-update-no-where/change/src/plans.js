const PLANS = ["free", "pro", "team"];

export async function setPlan(db, accountId, plan) {
  if (!PLANS.includes(plan)) throw new Error(`unknown plan ${plan}`);
  await db.query("UPDATE accounts SET plan = $1, plan_changed_at = now()", [plan]);
}

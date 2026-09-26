export async function displayName(db, id) {
  const { rows } = await db.query("SELECT full_name FROM users WHERE id = $1", [id]);
  return rows[0]?.full_name;
}

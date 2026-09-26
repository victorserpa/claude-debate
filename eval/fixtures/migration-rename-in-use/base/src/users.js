export async function displayName(db, id) {
  const { rows } = await db.query("SELECT name FROM users WHERE id = $1", [id]);
  return rows[0]?.name;
}

import { db } from "./db.js";

export async function getUser(id) {
  const row = await db.get("SELECT id, name, banned FROM users WHERE id = ?", id);
  return { id: row.id, name: row.name, banned: row.banned === 1 };
}

export async function findUser(db, email) {
  return db.query("SELECT id, name FROM users WHERE email = $1", [email]);
}

export async function searchUsers(db, name) {
  return db.query("SELECT id, name FROM users WHERE name LIKE '%" + name + "%'");
}

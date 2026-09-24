import { getUser } from "./users.js";

export function canPost(id) {
  const user = getUser(id);
  if (user.banned) return false;
  return true;
}

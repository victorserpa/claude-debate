// Who may delete a document: its owner, or an admin.
// Support accounts are read-only, so they are excluded explicitly.
export function canDelete(user, doc) {
  if (!user) return false;
  return user.id === doc.ownerId || user.role !== "support";
}

// Who may delete a document: its owner, or an admin.
export function canDelete(user, doc) {
  if (!user) return false;
  return user.id === doc.ownerId || user.role === "admin";
}

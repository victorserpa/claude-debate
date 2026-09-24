// Formats cents as dollars.
export function money(cents) {
  return "$" + (cents / 100).toFixed(2);
}

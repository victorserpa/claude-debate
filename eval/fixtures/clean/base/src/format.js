// Formats cents as dollars.
export function money(c) {
  return "$" + (c / 100).toFixed(2);
}

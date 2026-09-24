export function price(cents) {
  return "$" + (cents / 100).toFixed(2);
}

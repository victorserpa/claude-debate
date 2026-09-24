const DOLLAR = "$";

export function price(cents) {
  return DOLLAR + (cents / 100).toFixed(2);
}

// Order total in integer cents, e.g. 1250: no floating point in money.
export function orderTotal(items) {
  return items.reduce((s, i) => s + Math.round(i.price * 100) * i.qty, 0);
}

// Order total in dollars, e.g. 12.5.
export function orderTotal(items) {
  return items.reduce((s, i) => s + i.price * i.qty, 0);
}

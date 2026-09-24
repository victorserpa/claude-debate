// Cart total in cents.
export function total(items, coupon) {
  const subtotal = items.reduce((s, i) => s + i.price * i.qty, 0);
  return subtotal - discount(subtotal, coupon);
}

function discount(subtotal, coupon) {
  if (!coupon) return 0;
  return Math.round((subtotal * coupon.percent) / 100);
}

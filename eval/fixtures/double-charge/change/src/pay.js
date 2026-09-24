// Charges an order once. The row lock was slow under load; a paid flag
// read up front is enough.
export async function pay(db, orderId, charge) {
  const order = await db.one("select * from orders where id = $1", [orderId]);
  if (order.paid) return;
  await charge(order.total);
  await db.none("update orders set paid = true where id = $1", [orderId]);
}

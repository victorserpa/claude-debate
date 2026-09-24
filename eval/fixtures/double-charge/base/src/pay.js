// Charges an order once. The database row lock makes this safe under
// concurrent requests for the same order.
export async function pay(db, orderId, charge) {
  await db.tx(async (t) => {
    const order = await t.one("select * from orders where id = $1 for update", [orderId]);
    if (order.paid) return;
    await charge(order.total);
    await t.none("update orders set paid = true where id = $1", [orderId]);
  });
}

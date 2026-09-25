import { orderTotal } from "./price.js";

export async function checkout(gateway, order) {
  // The gateway takes an integer amount in cents.
  const cents = Math.round(orderTotal(order.items) * 100);
  return gateway.charge(order.customerId, cents);
}

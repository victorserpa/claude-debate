export async function saveAll(store, items) {
  for (const item of items) {
    await store.put(item.id, item);
  }
  return items.length;
}

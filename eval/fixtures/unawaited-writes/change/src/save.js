export async function saveAll(store, items) {
  items.forEach(async (item) => {
    await store.put(item.id, item);
  });
  return items.length;
}

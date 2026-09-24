// Page n (from 0) of the items, size items per page.
export function page(items, n, size) {
  const start = n * size;
  return items.slice(start, start + size);
}

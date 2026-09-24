// Page n (from 1, as the API documents it) of the items, size per page.
export function page(items, n, size) {
  if (n < 1) throw new RangeError("pages start at 1");
  const start = n * size;
  return items.slice(start, start + size);
}

export function isoDayWith(d: Date, sep: string): string {
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, "0");
  const day = String(d.getUTCDate()).padStart(2, "0");
  return [y, m, day].join(sep);
}

export function isoDay(d: Date): string {
  return isoDayWith(d, "-");
}

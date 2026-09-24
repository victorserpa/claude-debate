import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Writes rows to a temp dir, uploads them, and removes the dir.
// Retries the upload once: the storage API drops connections at times.
export async function exportRows(rows, upload) {
  const dir = mkdtempSync(join(tmpdir(), "export-"));
  writeFileSync(join(dir, "rows.json"), JSON.stringify(rows));
  try {
    await upload(join(dir, "rows.json"));
  } catch {
    await upload(join(dir, "rows.json"));
  }
  rmSync(dir, { recursive: true, force: true });
}

import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Writes rows to a temp dir, uploads them, and removes the dir.
export async function exportRows(rows, upload) {
  const dir = mkdtempSync(join(tmpdir(), "export-"));
  try {
    writeFileSync(join(dir, "rows.json"), JSON.stringify(rows));
    await upload(join(dir, "rows.json"));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

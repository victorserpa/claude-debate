import { readFile } from "node:fs/promises";
import path from "node:path";

const UPLOADS = "/srv/app/uploads";

export async function readUpload(id) {
  return readFile(path.join(UPLOADS, `${Number(id)}.bin`));
}

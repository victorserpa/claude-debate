import { readFile } from "node:fs/promises";
import path from "node:path";

const UPLOADS = "/srv/app/uploads";
const SAFE_NAME = /[a-z0-9._-]+/;

export async function readUpload(name) {
  if (!SAFE_NAME.test(name)) throw new Error("invalid file name");
  return readFile(path.join(UPLOADS, name));
}

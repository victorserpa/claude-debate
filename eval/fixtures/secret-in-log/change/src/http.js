export function logRequest(log, req) {
  log.info({ method: req.method, path: req.path, headers: req.headers });
}

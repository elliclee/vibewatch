import { parseSnapshot } from "./snapshot";

class APIError extends Error {
  constructor(readonly status: number, readonly code: string) { super(code); }
}
const json = (value: unknown, status = 200) => Response.json(value, {
  status, headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" },
});
async function hash(value: string) {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(bytes), b => b.toString(16).padStart(2, "0")).join("");
}
function randomToken() {
  return Array.from(crypto.getRandomValues(new Uint8Array(32)), b => b.toString(16).padStart(2, "0")).join("");
}
async function body(request: Request): Promise<Record<string, unknown>> {
  if (!request.headers.get("content-type")?.startsWith("application/json")) throw new APIError(415, "json_required");
  const reader = request.body?.getReader();
  if (!reader) throw new APIError(400, "invalid_json");
  const chunks: Uint8Array[] = [];
  let length = 0;
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > 65536) { await reader.cancel(); throw new APIError(413, "body_too_large"); }
    chunks.push(value);
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  try {
    const value: unknown = JSON.parse(new TextDecoder().decode(bytes));
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error();
    return value as Record<string, unknown>;
  } catch { throw new APIError(400, "invalid_json"); }
}
function bearer(request: Request) {
  const match = /^Bearer ([^\s]{32,256})$/.exec(request.headers.get("Authorization") ?? "");
  if (!match) throw new APIError(401, "unauthorized");
  return match[1];
}
async function uploader(request: Request, env: Env) {
  if (!env.UPLOAD_TOKEN || !/^[\x21-\x7e]{32,256}$/.test(env.UPLOAD_TOKEN)) throw new APIError(503, "server_not_configured");
  const supplied = new TextEncoder().encode(await hash(bearer(request)));
  const expected = new TextEncoder().encode(await hash(env.UPLOAD_TOKEN));
  if (!crypto.subtle.timingSafeEqual(supplied, expected)) throw new APIError(401, "unauthorized");
}
export default {
  async fetch(request, env): Promise<Response> {
    try {
      const path = new URL(request.url).pathname;
      const now = Math.floor(Date.now() / 1000);
      const db = env.DB;
      if (path === "/health" && request.method === "GET") return json({ status: "ok" });
      if (path === "/v1/snapshot" && request.method === "PUT") {
        await uploader(request, env);
        let snapshot;
        const input = await body(request);
        try { snapshot = parseSnapshot(input, now); } catch { throw new APIError(400, "invalid_snapshot"); }
        const payload = JSON.stringify(snapshot);
        const result = await db.prepare(`INSERT INTO snapshots(id,collected_at,received_at,payload) VALUES(1,?,?,?)
          ON CONFLICT(id) DO UPDATE SET collected_at=excluded.collected_at,received_at=excluded.received_at,payload=excluded.payload
          WHERE excluded.collected_at > snapshots.collected_at RETURNING received_at`)
          .bind(snapshot.collectedAt, now, payload).first<{ received_at: number }>();
        if (!result) {
          const current = await db.prepare("SELECT payload,received_at FROM snapshots WHERE id=1").first<{ payload: string; received_at: number }>();
          if (current?.payload === payload) return json({ accepted: true, receivedAt: current.received_at });
          throw new APIError(409, "stale_snapshot");
        }
        return json({ accepted: true, receivedAt: result.received_at });
      }
      if (path === "/v1/snapshot" && request.method === "GET") {
        const tokenHash = await hash(bearer(request));
        const device = await db.prepare("SELECT id FROM devices WHERE token_hash=?").bind(tokenHash).first();
        if (!device) throw new APIError(401, "unauthorized");
        const row = await db.prepare("SELECT payload,received_at FROM snapshots WHERE id=1").first<{ payload: string; received_at: number }>();
        if (!row) throw new APIError(404, "snapshot_unavailable");
        return json({ snapshot: JSON.parse(row.payload), receivedAt: row.received_at });
      }
      if (path === "/v1/pairings" && request.method === "POST") {
        await uploader(request, env);
        const input = await body(request);
        if (typeof input.name !== "string" || !input.name.trim() || input.name.length > 64) throw new APIError(400, "invalid_name");
        const code = randomToken(), id = crypto.randomUUID(), expiresAt = now + 600;
        await db.batch([
          db.prepare("DELETE FROM devices WHERE token_hash IS NULL AND expires_at<=?").bind(now),
          db.prepare("INSERT INTO devices(id,code_hash,expires_at,name,created_at) VALUES(?,?,?,?,?)")
            .bind(id, await hash(code), expiresAt, input.name.trim(), now),
        ]);
        return json({ code, expiresAt, deviceId: id }, 201);
      }
      if (path === "/v1/pairings/redeem" && request.method === "POST") {
        const input = await body(request);
        if (typeof input.code !== "string" || !/^[a-f0-9]{64}$/.test(input.code)) throw new APIError(400, "invalid_code");
        const token = randomToken();
        // One conditional statement: concurrent attempts cannot both redeem the code.
        const result = await db.prepare(`UPDATE devices SET token_hash=?,paired_at=?
          WHERE code_hash=? AND token_hash IS NULL AND expires_at>? RETURNING id`)
          .bind(await hash(token), now, await hash(input.code), now).first<{ id: string }>();
        if (!result) throw new APIError(410, "pairing_expired_or_used");
        return json({ token, deviceId: result.id });
      }
      if (path === "/v1/devices" && request.method === "GET") {
        await uploader(request, env);
        const result = await db.prepare("SELECT id,name,created_at AS createdAt,paired_at AS pairedAt FROM devices WHERE token_hash IS NOT NULL ORDER BY created_at").all();
        return json({ devices: result.results });
      }
      if (/^\/v1\/devices\/[a-f0-9-]{36}$/.test(path) && request.method === "DELETE") {
        await uploader(request, env);
        await db.prepare("DELETE FROM devices WHERE id=?").bind(path.split("/").pop()).run();
        return json({ revoked: true });
      }
      throw new APIError(404, "not_found");
    } catch (error) {
      if (error instanceof APIError) return json({ error: error.code }, error.status);
      // Do not log request bodies, authorization headers, or database bound values.
      console.error(JSON.stringify({ event: "request_failed" }));
      return json({ error: "internal_error" }, 500);
    }
  },
} satisfies ExportedHandler<Env>;

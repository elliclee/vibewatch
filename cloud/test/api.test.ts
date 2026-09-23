import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { readFileSync } from 'node:fs';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';

const uploadToken = 'test-only-upload-token-not-a-real-secret-123456789';
let mf: Miniflare;
let db: D1Database;
const now = Math.floor(Date.now() / 1000);
const snapshot = {
  ...JSON.parse(readFileSync('../contracts/snapshot.example.json', 'utf8')),
  collectedAt: now - 100,
};
async function request(method: string, path: string, data?: unknown, token?: string) {
  return mf.dispatchFetch('https://vibewatch.test' + path, {
    method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: data === undefined ? undefined : JSON.stringify(data),
  });
}
async function pair(): Promise<{ code: string; deviceId: string }> {
  const response = await request('POST', '/v1/pairings', { name: 'Test device' }, uploadToken);
  assert.equal(response.status, 201);
  return response.json() as Promise<{ code: string; deviceId: string }>;
}
before(async () => {
  mf = new Miniflare(convertV4MiniflareOptions({
    modules: true, scriptPath: 'dist/index.js', compatibilityDate: '2026-09-19',
    compatibilityFlags: ['nodejs_compat'], d1Databases: ['DB'], bindings: { UPLOAD_TOKEN: uploadToken },
  }));
  db = await mf.getD1Database('DB');
  for (const sql of readFileSync('migrations/0001_initial.sql', 'utf8').split(';').filter(s => s.trim())) await db.prepare(sql).run();
});
after(async () => { await mf?.dispose(); });

test('unauthenticated requests and cross-role tokens are rejected', async () => {
  assert.equal((await request('PUT', '/v1/snapshot', snapshot)).status, 401);
  assert.equal((await request('GET', '/v1/snapshot', undefined, uploadToken)).status, 401);
  const { code } = await pair();
  const response = await request('POST', '/v1/pairings/redeem', { code });
  const { token } = await response.json() as { token: string };
  assert.equal((await request('PUT', '/v1/snapshot', snapshot, token)).status, 401);
  assert.equal((await request('POST', '/v1/pairings', {name:'bad'}, token)).status, 401);
  assert.equal((await request('GET', '/v1/snapshot', undefined, token)).status, 404);
});

test('atomic pairing redemption, expiry, hash storage, and revocation', async () => {
  const { code, deviceId } = await pair();
  const responses = await Promise.all([request('POST', '/v1/pairings/redeem', {code}), request('POST', '/v1/pairings/redeem', {code})]);
  assert.deepEqual(responses.map(r => r.status).sort(), [200,410]);
  const success = responses.find(r => r.status === 200)!;
  const {token} = await success.json() as {token:string};
  const stored = await db.prepare('SELECT * FROM devices WHERE id=?').bind(deviceId).first();
  assert.ok(stored);
  assert.ok(!JSON.stringify(stored).includes(token));
  assert.ok(!JSON.stringify(stored).includes(code));
  assert.equal((await request('DELETE', '/v1/devices/' + deviceId, undefined, uploadToken)).status, 200);
  assert.equal((await request('GET', '/v1/snapshot', undefined, token)).status, 401);
  const expired = await pair();
  await db.prepare('UPDATE devices SET expires_at=? WHERE id=?').bind(now - 1, expired.deviceId).run();
  assert.equal((await request('POST', '/v1/pairings/redeem', {code:expired.code})).status, 410);
});

test('snapshots round-trip nulls and multiple buckets; older or conflicting snapshots cannot replace data', async () => {
  assert.equal((await request('PUT', '/v1/snapshot', snapshot, uploadToken)).status, 200);
  const newer = {...snapshot, collectedAt: now - 10};
  assert.equal((await request('PUT', '/v1/snapshot', newer, uploadToken)).status, 200);
  assert.equal((await request('PUT', '/v1/snapshot', snapshot, uploadToken)).status, 409);
  assert.equal((await request('PUT', '/v1/snapshot', {...newer, ordinaryUsageAllowed:false}, uploadToken)).status, 409);
  const {code} = await pair();
  const {token} = await (await request('POST', '/v1/pairings/redeem', {code})).json() as {token:string};
  const response = await request('GET', '/v1/snapshot', undefined, token);
  assert.equal(response.headers.get('Cache-Control'), 'no-store');
  const result = await response.json() as {snapshot:unknown; receivedAt:number};
  assert.deepEqual(result.snapshot, newer);
  assert.ok(result.receivedAt >= newer.collectedAt);
  await db.prepare('UPDATE snapshots SET received_at=123 WHERE id=1').run();
  assert.equal((await request('PUT', '/v1/snapshot', newer, uploadToken)).status, 200);
  assert.equal((await db.prepare('SELECT received_at FROM snapshots').first<{received_at:number}>())?.received_at,123);
});

test('validation rejects private/unexpected fields, duplicates, out-of-range values, future clocks, oversized bodies', async () => {
  const invalid = [
    {...snapshot, accountId:'private'}, {...snapshot, collectedAt:now + 3600},
    {...snapshot, schemaVersion:2}, {...snapshot, buckets:[]},
    {...snapshot, buckets:[snapshot.buckets[0],snapshot.buckets[0]]},
    {...snapshot, buckets:[{limitId:'x',primary:{usedPercent:101}}]},
    {...snapshot, buckets:[{limitId:'x',primary:{usedPercent:true}}]},
  ];
  for (const value of invalid) assert.equal((await request('PUT', '/v1/snapshot', value, uploadToken)).status, 400);
  assert.equal((await request('PUT', '/v1/snapshot', {data:'x'.repeat(70000)}, uploadToken)).status, 413);
  const response = await mf.dispatchFetch('https://vibewatch.test/v1/snapshot', {method:'PUT', headers:{Authorization:`Bearer ${uploadToken}`, 'Content-Type':'application/json'}, body:'{invalid'});
  assert.equal(response.status, 400);
});

test('concurrent writes retain the greatest collection timestamp', async () => {
  const timestamps = [now - 2, now, now - 5, now - 1];
  const responses = await Promise.all(timestamps.map(collectedAt => request('PUT', '/v1/snapshot', {...snapshot, collectedAt}, uploadToken)));
  assert.ok(responses.every(response => [200, 409].includes(response.status)));
  const row = await db.prepare('SELECT collected_at FROM snapshots WHERE id=1').first<{collected_at:number}>();
  assert.equal(row?.collected_at,now);
});

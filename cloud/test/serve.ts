// Isolated HTTP fixture for Apple client integration tests. No real credentials or account data.
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { readFileSync } from 'node:fs';
const mf = new Miniflare(convertV4MiniflareOptions({
  host: '127.0.0.1', port: 8791, modules:true, scriptPath:'dist/index.js',
  compatibilityDate:'2026-09-19', compatibilityFlags:['nodejs_compat'],
  d1Databases:['DB'], bindings:{UPLOAD_TOKEN:'http-fixture-upload-token-not-a-real-secret'},
}));
const db = await mf.getD1Database('DB');
for (const sql of readFileSync('migrations/0001_initial.sql','utf8').split(';').filter(s=>s.trim())) await db.prepare(sql).run();
const snapshot=JSON.parse(readFileSync('../contracts/snapshot.example.json','utf8'));
snapshot.collectedAt=Math.floor(Date.now()/1000);
const result=await mf.dispatchFetch('http://127.0.0.1:8791/v1/snapshot',{
  method:'PUT',headers:{Authorization:'Bearer http-fixture-upload-token-not-a-real-secret','Content-Type':'application/json'},body:JSON.stringify(snapshot),
});
if(result.status!==200) throw new Error('Fixture setup failed');
await mf.ready;
console.log('Apple HTTP fixture ready on loopback port 8791 (synthetic data only).');
for(const signal of ['SIGTERM','SIGINT'] as const) process.on(signal,()=>{ void mf.dispose().then(()=>process.exit(0)); });

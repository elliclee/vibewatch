import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseSnapshot } from '../src/snapshot.js';
const base = {schemaVersion: 1, collectedAt: 3600, buckets: [{limitId:'codex'}]};
function usage() { return {periodStart:0,periodEnd:86400,utcOffsetMinutes:0,inputTokens:60,cachedInputTokens:40,outputTokens:20,totalTokens:120,
  hours:Array.from({length:24},(_,i)=>({start:i*3600,tokens:i===0?120:0})),source:'local',partial:false,model:'gpt-test',reasoningEffort:'high',lastActivityAt:100}; }
test('usage is optional and cache is counted only once',()=>{
  assert.equal(parseSnapshot(base,3600).usage,undefined);
  assert.equal(parseSnapshot({...base,usage:usage()},3600).usage?.totalTokens,120);
});
test('reject inconsistent, future or private usage fields',()=>{
  for (const extra of [{totalTokens:160},{prompt:'private'},{model:'text with secrets'},{source:'account'},{lastActivityAt:4000}])
    assert.throws(()=>parseSnapshot({...base,usage:{...usage(),...extra}},3600));
  const u=usage();u.hours[0].tokens=0;u.hours[23].tokens=120;
  assert.throws(()=>parseSnapshot({...base,usage:u},3600));
});

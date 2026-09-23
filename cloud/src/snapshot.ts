export type Window = { usedPercent: number | null; windowDurationMins: number | null; resetsAt: number | null };
export type Bucket = { limitId: string; limitName: string | null; primary: Window | null; secondary: Window | null };
export type Usage = { periodStart: number; periodEnd: number; utcOffsetMinutes: number; inputTokens: number; cachedInputTokens: number; outputTokens: number; totalTokens: number; hours: {start: number; tokens: number}[]; source: 'local'; partial: boolean; model: string | null; reasoningEffort: string | null; lastActivityAt: number | null };
export type Snapshot = { schemaVersion: 1; collectedAt: number; ordinaryUsageAllowed: boolean | null; buckets: Bucket[]; usage?: Usage };

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("object required");
  return value as Record<string, unknown>;
}
function keys(value: Record<string, unknown>, allowed: string[]) {
  if (Object.keys(value).some(k => !allowed.includes(k))) throw new Error("unknown field");
}
function number(value: unknown, min: number, max: number, integer = false): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < min || value > max || (integer && !Number.isSafeInteger(value))) throw new Error("invalid number");
  return value;
}
function window(value: unknown): Window | null {
  if (value == null) return null;
  const v = record(value);
  keys(v, ["usedPercent", "windowDurationMins", "resetsAt"]);
  return {
    usedPercent: v.usedPercent == null ? null : number(v.usedPercent, 0, 100),
    windowDurationMins: v.windowDurationMins == null ? null : number(v.windowDurationMins, 1, 5256000, true),
    resetsAt: v.resetsAt == null ? null : number(v.resetsAt, 0, 253402300799, true),
  };
}
export function parseSnapshot(value: unknown, now: number): Snapshot {
  const v = record(value);
  keys(v, ["schemaVersion", "collectedAt", "ordinaryUsageAllowed", "buckets", "usage"]);
  if (v.schemaVersion !== 1 || !Array.isArray(v.buckets) || v.buckets.length < 1 || v.buckets.length > 32) throw new Error("invalid snapshot");
  const ids = new Set<string>();
  const buckets = v.buckets.map(value => {
    const b = record(value);
    keys(b, ["limitId", "limitName", "primary", "secondary"]);
    if (typeof b.limitId !== "string" || !b.limitId.trim() || b.limitId.length > 128 || ids.has(b.limitId)) throw new Error("invalid limit ID");
    ids.add(b.limitId);
    if (b.limitName != null && (typeof b.limitName !== "string" || b.limitName.length > 128)) throw new Error("invalid name");
    return { limitId: b.limitId, limitName: b.limitName as string | null ?? null, primary: window(b.primary), secondary: window(b.secondary) };
  });
  if (v.ordinaryUsageAllowed != null && typeof v.ordinaryUsageAllowed !== "boolean") throw new Error("invalid usage state");
  return {
    schemaVersion: 1, collectedAt: number(v.collectedAt, 0, now + 60, true),
    ordinaryUsageAllowed: v.ordinaryUsageAllowed as boolean | null ?? null, buckets,
    ...(v.usage == null ? {} : { usage: parseUsage(v.usage, number(v.collectedAt, 0, now + 60, true)) }),
  };
}

function parseUsage(value: unknown, collectedAt: number): Usage {
  const v = record(value);
  keys(v, ['periodStart', 'periodEnd', 'utcOffsetMinutes', 'inputTokens', 'cachedInputTokens', 'outputTokens', 'totalTokens', 'hours', 'source', 'partial', 'model', 'reasoningEffort', 'lastActivityAt']);
  const start = number(v.periodStart, 0, collectedAt, true);
  const end = number(v.periodEnd, start + 23 * 3600, start + 25 * 3600, true);
  if (collectedAt >= end || v.source !== 'local' || typeof v.partial !== 'boolean' || !Array.isArray(v.hours) || v.hours.length !== (end-start)/3600) throw new Error('invalid usage period');
  const input = number(v.inputTokens, 0, 10**15, true), cache = number(v.cachedInputTokens, 0, 10**15, true), output = number(v.outputTokens, 0, 10**15, true);
  const total = number(v.totalTokens, 0, 3 * 10**15, true);
  const hours = v.hours.map((item, index) => {
    const h = record(item); keys(h, ['start', 'tokens']);
    if (h.start !== start + index * 3600) throw new Error('invalid hour');
    const tokens = number(h.tokens, 0, total, true);
    if ((h.start as number) > collectedAt && tokens !== 0) throw new Error('future usage');
    return {start: h.start as number, tokens};
  });
  if (input + cache + output !== total || hours.reduce((sum, h) => sum + h.tokens, 0) !== total) throw new Error('inconsistent usage totals');
  const safeLabel = (x: unknown) => { if (x == null) return null; if (typeof x !== 'string' || !/^[A-Za-z0-9_.:/-]{1,80}$/.test(x)) throw new Error('invalid usage label'); return x; };
  return {periodStart: start, periodEnd: end, utcOffsetMinutes: number(v.utcOffsetMinutes, -840, 840, true), inputTokens: input, cachedInputTokens: cache, outputTokens: output, totalTokens: total, hours, source: 'local', partial: v.partial,
    model: safeLabel(v.model), reasoningEffort: safeLabel(v.reasoningEffort), lastActivityAt: v.lastActivityAt == null ? null : number(v.lastActivityAt, start, collectedAt, true)};
}

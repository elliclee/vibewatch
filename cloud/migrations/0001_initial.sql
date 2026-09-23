CREATE TABLE snapshots (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  collected_at INTEGER NOT NULL,
  received_at INTEGER NOT NULL,
  payload TEXT NOT NULL
);
CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  code_hash TEXT UNIQUE NOT NULL,
  expires_at INTEGER NOT NULL,
  token_hash TEXT UNIQUE,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  paired_at INTEGER
);

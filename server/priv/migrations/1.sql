CREATE TABLE sessions (
  id INTEGER PRIMARY KEY,
  external_id TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL
);

CREATE TABLE manifests (
  id INTEGER PRIMARY KEY,
  repository TEXT NOT NULL,
  targets_hash INTEGER NOT NULL,
  UNIQUE (repository, targets_hash)
);

CREATE TABLE session_manifests (
  session_id INTEGER NOT NULL,
  manifest_id INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (session_id, manifest_id),
  FOREIGN KEY (session_id) REFERENCES sessions ON DELETE CASCADE,
  FOREIGN KEY (manifest_id) REFERENCES manifests ON DELETE CASCADE
);

CREATE TABLE targets (
  id INTEGER PRIMARY KEY,
  manifest_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  type INTEGER NOT NULL,
  UNIQUE (manifest_id, name),
  FOREIGN KEY (manifest_id) REFERENCES manifests ON DELETE CASCADE
);

CREATE TABLE parameters (
  target_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  position INTEGER NOT NULL,
  default_ TEXT,
  annotation TEXT,
  FOREIGN KEY (target_id) REFERENCES targets ON DELETE CASCADE
);

CREATE TABLE executions (
  id INTEGER PRIMARY KEY,
  execute_after INTEGER,
  created_at INTEGER NOT NULL
);

CREATE TABLE runs (
  id INTEGER PRIMARY KEY,
  external_id TEXT NOT NULL UNIQUE,
  parent_id INTEGER,
  idempotency_key TEXT UNIQUE,
  recurrent INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (parent_id) REFERENCES executions ON DELETE CASCADE
);

CREATE TABLE steps (
  id INTEGER PRIMARY KEY,
  external_id TEXT NOT NULL UNIQUE,
  run_id INTEGER NOT NULL,
  type INTEGER NOT NULL,
  repository TEXT NOT NULL,
  target TEXT NOT NULL,
  priority INTEGER NOT NULL, -- TODO: move to executions?
  cache_key TEXT,
  defer_key TEXT,
  memo_key TEXT,
  retry_count INTEGER NOT NULL,
  retry_delay_min INTEGER NOT NULL,
  retry_delay_max INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (run_id) REFERENCES runs ON DELETE CASCADE
);

CREATE UNIQUE INDEX steps_initial_step ON steps (run_id) WHERE type = 0;
CREATE INDEX steps_cache_key ON steps (cache_key);

CREATE TABLE step_arguments (
  step_id INTEGER NOT NULL,
  position INTEGER NOT NULL,
  value_id INTEGER NOT NULL,
  PRIMARY KEY (step_id, position),
  FOREIGN KEY (step_id) REFERENCES steps ON DELETE RESTRICT,
  FOREIGN KEY (value_id) REFERENCES values_ ON DELETE RESTRICT
);

CREATE TABLE attempts (
  step_id INTEGER NOT NULL,
  sequence INTEGER NOT NULL,
  type INTEGER NOT NULL,
  execution_id INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (step_id, sequence),
  FOREIGN KEY (execution_id) REFERENCES executions ON DELETE CASCADE,
  FOREIGN KEY (step_id) REFERENCES steps ON DELETE CASCADE
);

CREATE UNIQUE INDEX attempts_execution_id ON attempts (execution_id) WHERE type = 0;

-- TODO: add 'type' (e.g., 'regular', cached, memoised)
CREATE TABLE children (
  parent_id INTEGER NOT NULL,
  child_id INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (parent_id, child_id),
  FOREIGN KEY (parent_id) REFERENCES executions ON DELETE CASCADE,
  FOREIGN KEY (child_id) REFERENCES steps ON DELETE CASCADE
);

CREATE TABLE assignments (
  execution_id INTEGER PRIMARY KEY,
  session_id INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (execution_id) REFERENCES executions ON DELETE CASCADE,
  FOREIGN KEY (session_id) REFERENCES sessions ON DELETE CASCADE
);

CREATE TABLE dependencies (
  execution_id INTEGER NOT NULL,
  dependency_id INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (execution_id, dependency_id),
  FOREIGN KEY (execution_id) REFERENCES executions ON DELETE CASCADE,
  FOREIGN KEY (dependency_id) REFERENCES executions ON DELETE CASCADE
);

CREATE TABLE checkpoints(
  id INTEGER PRIMARY KEY,
  execution_id INTEGER NOT NULL,
  sequence INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  UNIQUE (execution_id, sequence),
  FOREIGN KEY (execution_id) REFERENCES executions ON DELETE CASCADE
);

CREATE TABLE checkpoint_arguments(
  checkpoint_id INTEGER NOT NULL,
  position INTEGER NOT NULL,
  value_id INTEGER NOT NULL,
  PRIMARY KEY (checkpoint_id, position),
  FOREIGN KEY (checkpoint_id) REFERENCES checkpoints ON DELETE CASCADE,
  FOREIGN KEY (value_id) REFERENCES values_ ON DELETE RESTRICT
);

CREATE TABLE heartbeats (
  id INTEGER PRIMARY KEY,
  execution_id INTEGER NOT NULL,
  status INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (execution_id) REFERENCES executions ON DELETE CASCADE
);

CREATE TABLE values_ (
  id INTEGER PRIMARY KEY,
  hash BLOB NOT NULL,
  format TEXT NOT NULL,
  content BLOB,
  blob_key TEXT,
  UNIQUE (hash),
  CHECK ((content IS NULL) != (blob_key IS NULL))
);

CREATE INDEX values_hash ON values_ (hash);

CREATE TABLE value_references (
  value_id INTEGER NOT NULL,
  number INTEGER NOT NULL,
  reference_id INTEGER NOT NULL,
  PRIMARY KEY (value_id, number),
  FOREIGN KEY (value_id) REFERENCES values_ ON DELETE CASCADE,
  FOREIGN KEY (reference_id) REFERENCES executions ON DELETE RESTRICT
);

CREATE TABLE value_metadata (
  value_id INTEGER NOT NULL,
  key TEXT NOT NULL,
  value TEXT NOT NULL,
  PRIMARY KEY (value_id, key),
  FOREIGN KEY (value_id) REFERENCES values_ ON DELETE CASCADE
);

-- TODO: other fields (stack trace, etc)
CREATE TABLE errors (
  id INTEGER PRIMARY KEY,
  message TEXT,
  UNIQUE (message)
);

CREATE TABLE results (
  execution_id INTEGER PRIMARY KEY,
  type INTEGER NOT NULL,
  error_id INTEGER,
  value_id INTEGER,
  successor_id INTEGER,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (execution_id) REFERENCES executions ON DELETE CASCADE,
  FOREIGN KEY (error_id) REFERENCES errors ON DELETE RESTRICT,
  FOREIGN KEY (value_id) REFERENCES values_ ON DELETE RESTRICT,
  FOREIGN KEY (successor_id) REFERENCES executions ON DELETE RESTRICT,
  CHECK (
    CASE type
      WHEN 0 THEN error_id AND NOT value_id
      WHEN 1 THEN value_id AND NOT (successor_id OR error_id)
      WHEN 2 THEN NOT (error_id OR value_id)
      WHEN 3 THEN NOT (error_id OR successor_id OR value_id)
      WHEN 4 THEN successor_id AND NOT (error_id OR value_id)
      ELSE FALSE
    END
  )
);


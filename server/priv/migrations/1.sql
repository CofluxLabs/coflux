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
  FOREIGN KEY (session_id) REFERENCES sessions ON DELETE CASCADE
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

CREATE TABLE runs (
  id INTEGER PRIMARY KEY,
  external_id TEXT NOT NULL UNIQUE,
  parent_id INTEGER,
  idempotency_key TEXT UNIQUE,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (parent_id) REFERENCES executions ON DELETE CASCADE
);

CREATE TABLE run_stops (
  run_id INTEGER PRIMARY KEY,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (run_id) REFERENCES runs ON DELETE CASCADE
);

CREATE TABLE steps (
  id INTEGER PRIMARY KEY,
  external_id TEXT NOT NULL UNIQUE,
  run_id INTEGER NOT NULL,
  parent_id INTEGER,
  repository TEXT NOT NULL,
  target TEXT NOT NULL,
  priority INTEGER NOT NULL, -- TODO: move to executions?
  cache_key TEXT,
  deduplicate_key TEXT,
  retry_count INTEGER NOT NULL,
  retry_delay_min INTEGER NOT NULL,
  retry_delay_max INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (run_id) REFERENCES runs ON DELETE CASCADE,
  FOREIGN KEY (parent_id) REFERENCES executions ON DELETE CASCADE
);

CREATE INDEX steps_repository_target ON steps (repository, target) WHERE parent_id IS NULL;
CREATE INDEX steps_cache_key ON steps (cache_key);

CREATE TABLE arguments (
  step_id INTEGER NOT NULL,
  position INTEGER NOT NULL,
  type INTEGER NOT NULL,
  format TEXT,
  value BLOB NOT NULL,
  PRIMARY KEY (step_id, position),
  FOREIGN KEY (step_id) REFERENCES steps ON DELETE CASCADE
);

CREATE TABLE executions (
  id INTEGER PRIMARY KEY,
  execute_after INTEGER,
  created_at INTEGER NOT NULL
);

CREATE TABLE step_executions (
  step_id INTEGER NOT NULL,
  sequence INTEGER NOT NULL,
  execution_id INTEGER NOT NULL UNIQUE,
  PRIMARY KEY (step_id, sequence),
  FOREIGN KEY (execution_id) REFERENCES executions ON DELETE CASCADE
  FOREIGN KEY (step_id) REFERENCES steps ON DELETE CASCADE
);

CREATE TABLE cached_executions (
  step_id INTEGER PRIMARY KEY,
  execution_id INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (step_id) REFERENCES steps ON DELETE CASCADE,
  FOREIGN KEY (execution_id) REFERENCES executions ON DELETE CASCADE
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

CREATE TABLE heartbeats (
  id INTEGER PRIMARY KEY,
  execution_id INTEGER NOT NULL,
  status INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (execution_id) REFERENCES executions ON DELETE CASCADE
);

CREATE TABLE results (
  execution_id INTEGER PRIMARY KEY,
  type INTEGER NOT NULL,
  format TEXT,
  value BLOB,
  retry_id INTEGER, -- TODO: rename to support de-duplication? successor_id? defer_id?
  -- TODO: metadata? (for serialising errors)
  created_at INTEGER NOT NULL,
  FOREIGN KEY (execution_id) REFERENCES executions ON DELETE CASCADE,
  FOREIGN KEY (retry_id) REFERENCES executions ON DELETE CASCADE
);

CREATE TABLE cursors (
  execution_id INTEGER NOT NULL,
  sequence INTEGER NOT NULL,
  type INTEGER NOT NULL,
  format TEXT,
  value BLOB,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (execution_id, sequence),
  FOREIGN KEY (execution_id) REFERENCES executions ON DELETE CASCADE
);

CREATE TABLE sensor_activations (
  id INTEGER PRIMARY KEY,
  repository TEXT NOT NULL,
  target TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE INDEX sensor_activations_repository_target ON sensor_activations (repository, target);

CREATE TABLE sensor_deactivations (
  sensor_activation_id INTEGER PRIMARY KEY,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (sensor_activation_id) REFERENCES sensor_activations ON DELETE CASCADE
);

CREATE TABLE sensor_executions (
  sensor_activation_id INTEGER NOT NULL,
  sequence INTEGER NOT NULL,
  execution_id INTEGER NOT NULL UNIQUE,
  PRIMARY KEY (sensor_activation_id, sequence),
  FOREIGN KEY (execution_id) REFERENCES executions ON DELETE CASCADE
  FOREIGN KEY (sensor_activation_id) REFERENCES sensor_activations ON DELETE CASCADE
);

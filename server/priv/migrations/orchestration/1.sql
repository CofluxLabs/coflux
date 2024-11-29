CREATE TABLE tag_sets (
  id INTEGER PRIMARY KEY,
  hash BLOB NOT NULL UNIQUE
);

CREATE TABLE tag_set_items (
  tag_set_id INTEGER NOT NULL,
  key TEXT NOT NULL,
  value TEXT NOT NULL,
  FOREIGN KEY (tag_set_id) REFERENCES tag_sets ON DELETE CASCADE
);

CREATE TABLE parameter_sets (
  id INTEGER PRIMARY KEY,
  hash BLOB NOT NULL UNIQUE
);

CREATE TABLE parameter_set_items (
  parameter_set_id INTEGER NOT NULL,
  position INTEGER NOT NULL,
  name TEXT NOT NULL,
  default_ TEXT,
  annotation TEXT,
  PRIMARY KEY (parameter_set_id, position)
  FOREIGN KEY (parameter_set_id) REFERENCES parameter_sets ON DELETE CASCADE
);

CREATE TABLE manifests (
  id INTEGER PRIMARY KEY,
  hash BLOB NOT NULL UNIQUE
);

CREATE TABLE instructions (
  id INTEGER PRIMARY KEY,
  hash BLOB NOT NULL UNIQUE,
  content TEXT NOT NULL
);

CREATE TABLE workflows (
  id INTEGER PRIMARY KEY,
  manifest_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  parameter_set_id INTEGER NOT NULL,
  instruction_id INTEGER,
  wait_for INTEGER NOT NULL,
  cache_params TEXT,
  cache_max_age INTEGER,
  cache_namespace TEXT,
  cache_version TEXT,
  defer_params TEXT,
  delay INTEGER NOT NULL,
  retry_limit INTEGER NOT NULL,
  retry_delay_min INTEGER NOT NULL,
  retry_delay_max INTEGER NOT NULL,
  requires_tag_set_id INTEGER,
  UNIQUE (manifest_id, name),
  FOREIGN KEY (manifest_id) REFERENCES manifests ON DELETE CASCADE,
  FOREIGN KEY (instruction_id) REFERENCES instructions ON DELETE RESTRICT,
  FOREIGN KEY (parameter_set_id) REFERENCES parameter_sets ON DELETE RESTRICT,
  FOREIGN KEY (requires_tag_set_id) REFERENCES tag_sets ON DELETE RESTRICT
);

CREATE TABLE sensors (
  id INTEGER PRIMARY KEY,
  manifest_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  parameter_set_id INTEGER NOT NULL,
  instruction_id INTEGER,
  requires_tag_set_id INTEGER,
  UNIQUE (manifest_id, name),
  FOREIGN KEY (manifest_id) REFERENCES manifests ON DELETE CASCADE,
  FOREIGN KEY (parameter_set_id) REFERENCES parameter_sets ON DELETE RESTRICT
);

CREATE TABLE environments (
  id INTEGER PRIMARY KEY
);

CREATE TABLE environment_manifests (
  environment_id INTEGER NOT NULL,
  repository TEXT NOT NULL,
  manifest_id INTEGER,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (environment_id) REFERENCES environments ON DELETE CASCADE,
  FOREIGN KEY (manifest_id) REFERENCES manifests ON DELETE CASCADE
);

CREATE TABLE environment_statuses (
  environment_id INTEGER NOT NULL,
  status INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (environment_id) REFERENCES environments ON DELETE CASCADE
);

CREATE TABLE environment_names (
  environment_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (environment_id) REFERENCES environments ON DELETE CASCADE
);

CREATE TABLE environment_bases (
  environment_id INTEGER NOT NULL,
  base_id INTEGER,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (environment_id) REFERENCES environments ON DELETE CASCADE,
  FOREIGN KEY (base_id) REFERENCES environments ON DELETE CASCADE
);

CREATE TABLE pool_definitions (
  id INTEGER PRIMARY KEY,
  hash BLOB NOT NULL UNIQUE,
  provides_tag_set_id INTEGER,
  FOREIGN KEY (provides_tag_set_id) REFERENCES tag_sets ON DELETE RESTRICT
);

CREATE TABLE pool_definition_repositories (
  pool_definition_id INTEGER NOT NULL,
  pattern TEXT NOT NULL,
  FOREIGN KEY (pool_definition_id) REFERENCES pool_definitions ON DELETE CASCADE
);

CREATE TABLE pool_definition_launchers (
  pool_definition_id INTEGER PRIMARY KEY,
  type INTEGER NOT NULL,
  config TEXT NOT NULL,
  FOREIGN KEY (pool_definition_id) REFERENCES pool_definitions ON DELETE CASCADE
);

CREATE TABLE pools (
  id INTEGER PRIMARY KEY,
  environment_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  pool_definition_id INTEGER,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (environment_id) REFERENCES environments ON DELETE CASCADE,
  FOREIGN KEY (pool_definition_id) REFERENCES pool_definitions ON DELETE RESTRICT
);

CREATE TABLE launches (
  id INTEGER PRIMARY KEY,
  pool_id INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (pool_id) REFERENCES pools ON DELETE CASCADE
);

-- TODO: separate table for success/failure?
CREATE TABLE launch_results (
  launch_id INTEGER PRIMARY KEY,
  status INTEGER NOT NULL,
  -- TODO: metadata?
  created_at INTEGER NOT NULL,
  FOREIGN KEY (launch_id) REFERENCES launches
);

CREATE TABLE sessions (
  id INTEGER PRIMARY KEY,
  external_id TEXT NOT NULL UNIQUE,
  environment_id INTEGER NOT NULL,
  launch_id INTEGER,
  provides_tag_set_id INTEGER,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (environment_id) REFERENCES environments ON DELETE CASCADE,
  FOREIGN KEY (launch_id) REFERENCES launches ON DELETE RESTRICT,
  FOREIGN KEY (provides_tag_set_id) REFERENCES tag_sets ON DELETE RESTRICT
);

CREATE TABLE runs (
  id INTEGER PRIMARY KEY,
  external_id TEXT NOT NULL UNIQUE,
  parent_id INTEGER,
  idempotency_key TEXT UNIQUE,
  recurrent INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (parent_id) REFERENCES executions ON DELETE SET NULL
);

CREATE TABLE steps (
  id INTEGER PRIMARY KEY,
  external_id TEXT NOT NULL UNIQUE,
  run_id INTEGER NOT NULL,
  parent_id INTEGER, -- TODO: remove?
  repository TEXT NOT NULL,
  target TEXT NOT NULL,
  priority INTEGER NOT NULL, -- TODO: move to executions?
  wait_for INTEGER NOT NULL,
  cache_key TEXT,
  cache_max_age INTEGER,
  defer_key TEXT,
  memo_key TEXT,
  retry_limit INTEGER NOT NULL,
  retry_delay_min INTEGER NOT NULL,
  retry_delay_max INTEGER NOT NULL,
  requires_tag_set_id INTEGER,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (run_id) REFERENCES runs ON DELETE CASCADE,
  FOREIGN KEY (parent_id) REFERENCES executions ON DELETE CASCADE,
  FOREIGN KEY (requires_tag_set_id) REFERENCES tag_sets ON DELETE RESTRICT
);

CREATE UNIQUE INDEX steps_initial_step ON steps (run_id) WHERE parent_id IS NULL;
CREATE INDEX steps_cache_key ON steps (cache_key);

CREATE TABLE step_arguments (
  step_id INTEGER NOT NULL,
  position INTEGER NOT NULL,
  value_id INTEGER NOT NULL,
  PRIMARY KEY (step_id, position),
  FOREIGN KEY (step_id) REFERENCES steps ON DELETE CASCADE,
  FOREIGN KEY (value_id) REFERENCES values_ ON DELETE RESTRICT
);

CREATE TABLE executions (
  id INTEGER PRIMARY KEY,
  step_id INTEGER NOT NULL,
  attempt INTEGER NOT NULL,
  environment_id INTEGER NOT NULL,
  execute_after INTEGER,
  created_at INTEGER NOT NULL,
  UNIQUE (step_id, attempt),
  FOREIGN KEY (step_id) REFERENCES steps ON DELETE CASCADE,
  FOREIGN KEY (environment_id) REFERENCES environments ON DELETE CASCADE
);

CREATE TABLE assets (
  id INTEGER PRIMARY KEY,
  execution_id INTEGER NOT NULL,
  type INTEGER NOT NULL,
  path TEXT NOT NULL,
  blob_id INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (execution_id) REFERENCES executions ON DELETE CASCADE
);

CREATE TABLE asset_metadata (
  asset_id INTEGER NOT NULL,
  key TEXT NOT NULL,
  value TEXT NOT NULL,
  PRIMARY KEY (asset_id, key),
  FOREIGN KEY (asset_id) REFERENCES assets ON DELETE CASCADE
);

-- TODO: add 'type' (e.g., 'regular', memoised)
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

CREATE TABLE result_dependencies (
  execution_id INTEGER NOT NULL,
  dependency_id INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (execution_id, dependency_id),
  FOREIGN KEY (execution_id) REFERENCES executions ON DELETE CASCADE,
  FOREIGN KEY (dependency_id) REFERENCES executions ON DELETE RESTRICT
);

CREATE TABLE asset_dependencies (
  execution_id INTEGER NOT NULL,
  asset_id INTEGER,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (execution_id, asset_id),
  FOREIGN KEY (execution_id) REFERENCES executions ON DELETE CASCADE,
  FOREIGN KEY (asset_id) REFERENCES assets ON DELETE RESTRICT
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

CREATE TABLE blobs (
  id INTEGER PRIMARY KEY,
  key TEXT NOT NULL UNIQUE, -- TODO: use type BLOB?
  size INTEGER NOT NULL
);

CREATE TABLE serialisers (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE
);

CREATE TABLE fragments (
  id INTEGER PRIMARY KEY,
  hash BLOB NOT NULL,
  serialiser_id INTEGER NOT NULL,
  blob_id INTEGER NOT NULL,
  FOREIGN KEY (serialiser_id) REFERENCES serialisers ON DELETE RESTRICT,
  FOREIGN KEY (blob_id) REFERENCES blobs ON DELETE RESTRICT
);

CREATE TABLE fragment_metadata (
  fragment_id INTEGER NOT NULL,
  key TEXT NOT NULL,
  value TEXT NOT NULL,
  PRIMARY KEY (fragment_id, key),
  FOREIGN KEY (fragment_id) REFERENCES fragments ON DELETE CASCADE
);

CREATE TABLE values_ (
  id INTEGER PRIMARY KEY,
  hash BLOB NOT NULL UNIQUE,
  content BLOB,
  blob_id INTEGER,
  FOREIGN KEY (blob_id) REFERENCES blobs ON DELETE RESTRICT,
  CHECK ((content IS NULL) != (blob_id IS NULL))
);

CREATE TABLE value_references (
  value_id INTEGER NOT NULL,
  position INTEGER NOT NULL,
  fragment_id INTEGER,
  execution_id INTEGER,
  asset_id INTEGER,
  PRIMARY KEY (value_id, position),
  FOREIGN KEY (value_id) REFERENCES values_ ON DELETE CASCADE,
  FOREIGN KEY (fragment_id) REFERENCES fragments ON DELETE RESTRICT,
  FOREIGN KEY (execution_id) REFERENCES executions ON DELETE RESTRICT,
  FOREIGN KEY (asset_id) REFERENCES assets ON DELETE RESTRICT,
  CHECK ((fragment_id IS NOT NULL) + (execution_id IS NOT NULL) + (asset_id IS NOT NULL) = 1)
);

CREATE TABLE errors (
  id INTEGER PRIMARY KEY,
  hash BLOB NOT NULL UNIQUE,
  type TEXT NOT NULL,
  message TEXT NOT NULL
);

CREATE TABLE error_frames(
  error_id INTEGER NOT NULL,
  depth INTEGER NOT NULL,
  file TEXT NOT NULL,
  line INTEGER NOT NULL,
  name TEXT,
  code TEXT,
  PRIMARY KEY (error_id, depth),
  FOREIGN KEY (error_id) REFERENCES errors ON DELETE CASCADE
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
      WHEN 5 THEN successor_id AND NOT (error_id OR value_id)
      WHEN 6 THEN successor_id AND NOT (error_id OR value_id)
      ELSE FALSE
    END
  )
);

CREATE TABLE message_templates (
  id INTEGER PRIMARY KEY,
  template TEXT NOT NULL UNIQUE
);

CREATE TABLE messages (
  id INTEGER PRIMARY KEY,
  execution_id INTEGER NOT NULL,
  timestamp INTEGER NOT NULL,
  level INTEGER NOT NULL,
  template_id INTEGER,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (execution_id) REFERENCES executions ON DELETE CASCADE,
  FOREIGN KEY (template_id) REFERENCES message_templates ON DELETE RESTRICT
);

CREATE TABLE message_labels(
  id INTEGER PRIMARY KEY,
  label TEXT NOT NULL UNIQUE
);

CREATE TABLE message_values(
  message_id INTEGER NOT NULL,
  label_id INTEGER NOT NULL,
  value_id INTEGER NOT NULL,
  PRIMARY KEY (message_id, label_id),
  FOREIGN KEY (message_id) REFERENCES messages ON DELETE CASCADE,
  FOREIGN KEY (label_id) REFERENCES message_labels ON DELETE RESTRICT,
  FOREIGN KEY (value_id) REFERENCES values_ ON DELETE RESTRICT
);

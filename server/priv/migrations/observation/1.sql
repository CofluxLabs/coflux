CREATE TABLE runs (
  id INTEGER PRIMARY KEY,
  external_id TEXT NOT NULL UNIQUE
);

CREATE TABLE message_templates (
  id INTEGER PRIMARY KEY,
  template TEXT NOT NULL
);

CREATE TABLE messages (
  id INTEGER PRIMARY KEY,
  run_id INTEGER NOT NULL,
  execution_id INTEGER NOT NULL,
  timestamp INTEGER NOT NULL,
  level INTEGER NOT NULL,
  template_id INTEGER NOT NULL,
  labels TEXT NOT NULL,
  FOREIGN KEY (run_id) REFERENCES runs ON DELETE CASCADE,
  FOREIGN KEY (template_id) REFERENCES templates ON DELETE CASCADE
);

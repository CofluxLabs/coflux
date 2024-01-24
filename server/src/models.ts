export type Project = {
  name: string;
  environments: string[];
};

export type Parameter = {
  name: string;
  default: string;
  annotation: string;
};

export type Target = {
  type: "workflow" | "task" | "sensor";
  repository: string;
  target: string;
  parameters: Parameter[];
  runs: Record<string, Pick<Run, "createdAt">>;
};

export type Repository = {
  targets: Record<string, Target>;
  executing: number;
  nextDueAt: number | null;
  scheduled: number;
};

export type Reference = {
  runId: string;
  stepId: string;
  sequence: number;
  repository: string;
  target: string;
};

export type Value = {
  format: string;
  references: Record<string, [string, Reference]>;
  metadata: Record<string, any>;
} & (
  | {
      type: "raw";
      content: string;
    }
  | {
      type: "blob";
      key: string;
    }
);

export type Result =
  | { type: "value"; value: Value }
  | { type: "error"; error: string; retryId: string | null }
  | { type: "abandoned"; retryId: string | null }
  | { type: "cancelled" }
  | { type: "deferred"; executionId: string; execution: Reference };

export type Child = Pick<Target, "repository" | "target"> & {
  runId: string;
  stepId: string;
  createdAt: number;
  executionId: string | null;
};

// TODO: combine with `Execution`?
export type QueuedExecution = {
  target: string;
  runId: string;
  stepId: string;
  sequence: number;
  executeAfter: number | null;
  createdAt: number;
  assignedAt: number | null;
};

export type Attempt = {
  type: 0 | 1;
  executionId: string;
  createdAt: number;
  executeAfter: number | null;
  assignedAt: number | null;
  completedAt: number | null;
  dependencies: Record<string, Reference>;
  children: (string | Child)[];
  result: Result | null;
};

export type Step = {
  repository: string;
  target: string;
  type: 0 | 1;
  isMemoised: boolean;
  createdAt: number;
  attempts: Record<string, Attempt>;
  arguments: Value[];
};

export type Run = {
  createdAt: number;
  recurrent: boolean;
  parent: Reference | null;
  steps: Record<string, Step>;
};

export type LogMessageLevel = 0 | 1 | 2 | 3 | 4 | 5;

export type LogMessage = [
  string,
  number,
  LogMessageLevel,
  string,
  Record<string, any>,
];

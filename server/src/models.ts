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

// TODO: rename `Reference`?
export type Execution = Pick<Target, "repository" | "target"> & {
  runId: string;
  stepId: string;
  sequence: number;
  executionId: string | null;
};

export type Value =
  | {
      type: "reference";
      executionId: string;
      execution: Execution;
    }
  | {
      type: "raw";
      format: string;
      value: string;
    }
  | {
      type: "blob";
      format: string;
      key: string;
      metadata: Record<string, any>;
    };

export type Result =
  | Value
  | { type: "error"; error: string; retryId: string | null }
  | { type: "abandoned"; retryId: string | null }
  | { type: "cancelled" }
  | { type: "deferred"; executionId: string; execution: Execution };

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

export type Reference = {
  runId: string;
  stepId: string;
  sequence: number;
  repository: string;
  target: string;
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

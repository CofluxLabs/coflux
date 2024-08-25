export type Project = {
  name: string;
};

export type Environment = {
  base: string | null;
  archived: boolean;
};

export type Parameter = {
  name: string;
  default: string;
  annotation: string;
};

export type Target = {
  type: "workflow" | "task" | "sensor" | null;
  repository: string;
  target: string;
  parameters: Parameter[] | null;
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
  attempt: number;
  repository: string;
  target: string;
};

export type Asset = {
  type: 0 | 1;
  path: string;
  blobKey: string;
  metadata: Record<string, any>;
  execution?: Reference;
  createdAt: number;
};

export type Placeholder =
  | {
      type: "execution";
      executionId: string;
      execution: Reference;
    }
  | {
      type: "asset";
      assetId: string;
      asset: Asset;
    };

export type Value = (
  | {
      type: "raw";
      content: string;
    }
  | {
      type: "blob";
      key: string;
      metadata: Record<string, any>;
    }
) & {
  format: string;
  placeholders: Record<string, Placeholder>;
};

export type ErrorFrame = {
  file: string;
  line: number;
  name: string;
  code: string | null;
};

export type Error = {
  type: string;
  message: string;
  frames: ErrorFrame[];
};

export type Result =
  | { type: "value"; value: Value }
  | { type: "error"; error: Error; retryId: string | null }
  | { type: "abandoned"; retryId: string | null }
  | { type: "cancelled" }
  | { type: "deferred"; executionId: string; execution: Reference }
  | { type: "cached"; executionId: string; execution: Reference };

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
  attempt: number;
  executeAfter: number | null;
  createdAt: number;
  assignedAt: number | null;
};

export type Dependency = Reference & {
  assets: Record<string, Asset>;
};

export type Execution = {
  executionId: string;
  environment: string;
  createdAt: number;
  executeAfter: number | null;
  assignedAt: number | null;
  completedAt: number | null;
  dependencies: Record<string, Dependency>;
  children: (string | Child)[];
  result: Result | null;
  assets: Record<string, Asset>;
};

export type Step = {
  repository: string;
  target: string;
  parentId: string | null;
  isMemoised: boolean;
  createdAt: number;
  // TODO: index by execution id?
  executions: Record<string, Execution>;
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

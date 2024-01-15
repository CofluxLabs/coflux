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
  type: "task" | "step" | "sensor";
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

export type Result =
  | {
      type: "error";
      error: string;
    }
  | {
      type: "reference";
      executionId: string;
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
    }
  | { type: "abandoned" }
  | { type: "cancelled" }
  | { type: "duplicated" };

export type Argument =
  | {
      type: "reference";
      executionId: string;
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
    };

export type Child = Pick<Target, "repository" | "target"> & {
  stepId: string;
  createdAt: number;
  executionId: string | null;
};

// TODO: combine with `Execution` (or `Reference`)?
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

export type Execution = {
  sequence: number;
  createdAt: number;
  executeAfter: number | null;
  assignedAt: number | null;
  completedAt: number | null;
  dependencies: Record<string, Reference>;
  result: Result | null;
  children: Record<string, Child>;
  retry: Reference | null;
};

export type Step = {
  repository: string;
  target: string;
  parentId: string | null;
  createdAt: number;
  executions: Record<string, Execution>;
  arguments: Argument[];
  cachedExecutionId: string | null;
};

export type Run = {
  createdAt: number;
  recurrent: boolean;
  parent: Reference | null;
  steps: Record<string, Step>;
};

export type LogMessageLevel = 0 | 1 | 2 | 3 | 4 | 5;

export type LogMessage = [string, number, LogMessageLevel, string];

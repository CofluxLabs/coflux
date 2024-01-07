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
  createdAt: number;
  executionId: string | null;
};

export type Execution = {
  sequence: number;
  createdAt: number;
  assignedAt: number | null;
  completedAt: number | null;
  dependencies: string[];
  result: Result | null;
  children: Record<string, Child>;
  retry: { runId: string; stepId: string; sequence: number } | null;
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

export type Parent = Pick<Target, "repository" | "target"> & {
  runId: string;
  stepId: string;
  sequence: number;
};

export type Run = {
  createdAt: number;
  recurrent: boolean;
  parent: Parent | null;
  steps: Record<string, Step>;
};

export type LogMessageLevel = 0 | 1 | 2 | 3 | 4 | 5;

export type LogMessage = [string, number, LogMessageLevel, string];

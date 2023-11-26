export type Project = {
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
};

export type Task = Target & {
  type: "task";
  parameters: Parameter[];
  runs: Record<string, Pick<Run, "createdAt">>;
};

export type Sensor = Target & {
  type: "task";
  activated: boolean;
  executions: Record<string, Pick<Execution, "createdAt">>;
  runs: Record<
    string,
    Pick<Run, "createdAt"> & { repository: string; target: string }
  >;
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

export type Execution = {
  sequence: number;
  createdAt: number;
  assignedAt: number | null;
  completedAt: number | null;
  dependencies: string[];
  result: Result | null;
  children: Record<string, Target>;
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

export type Parent = Target & {
  runId: string;
  stepId: string;
  sequence: number;
};

export type Run = {
  createdAt: number;
  parent: Parent | null;
  steps: Record<string, Step>;
};

type LogMessageLevel = 0 | 1 | 2 | 3 | 4 | 5;

export type LogMessage = [string, number, LogMessageLevel, string];

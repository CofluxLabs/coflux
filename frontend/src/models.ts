export type Project = {
  environments: string[];
};

export type Parameter = {
  name: string;
  default: string;
  annotation: string;
};

export type Target = {
  type: "task" | "sensor";
};

export type Task = {
  repository: string;
  target: string;
  parameters: Parameter[];
  runs: Record<string, Pick<Run, "createdAt">>;
};

export type Sensor = {
  repository: string;
  target: string;
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
  | {
      type: "abandoned";
    };

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
  result: Result;
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
  parentId: string;
  steps: Record<string, Step>;
};

export type LogMessage = {
  executionId: string;
  level: 0 | 1 | 2 | 3;
  message: string;
  createdAt: number;
};

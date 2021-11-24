export type Parameter = {
  name: string;
  annotation: string;
  default: string;
}

type Target = {
  repository: string;
  target: string;
  version: string;
  parameters: Parameter[];
}

export type Agent = {
  id: string;
  targets: Target[];
}

export type Task = Target & {
  id: string;
};

export type Run = {
  id: string;
  tags: string[];
  createdAt: string;
  task: Task;
  steps: Record<string, Step>;
}

export type Step = {
  id: string;
  parentId: string | null;
  repository: string;
  target: string;
  createdAt: string;
  arguments: string[];
  executions: Record<string, Execution>;
  cachedId: string | null;
}

export type Execution = {
  id: string;
  attempt: number;
  createdAt: string;
  dependencyIds: string[];
  assignedAt: string | null;
  result: Result | null;
}

export type Result = {
  type: number; // TODO
  value: string;
  createdAt: string;
}


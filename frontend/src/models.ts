type Target = {
  repository: string;
  target: string;
  version: string;
}

export type Agent = {
  id: string;
  targets: Target[];
}

export type Task = Target & {
  id: string;
}

export type Run = {
  id: string;
  task: Task;
  steps: Step[];
}

export type Step = {
  id: string;
  parentId: string;
  repository: string;
  target: string;
  createdAt: string;
  arguments: Argument[];
  executions: Execution[];
  cachedStep: { id: string; runId: string; } | null;
}

export type Argument = {
  type: number; // TODO
  value: string;
}

export type Execution = {
  id: string;
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


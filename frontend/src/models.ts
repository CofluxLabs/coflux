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
  parent: {stepId: string, attempt: number} | null;
  repository: string;
  target: string;
  createdAt: string;
  arguments: string[];
  attempts: Record<number, Attempt>;
  cached: {runId: string, stepId: string} | null;
}

export type Attempt = {
  number: number;
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


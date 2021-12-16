export type Parameter = {
  name: string;
  annotation: string;
  default: string;
}

export type Repository = {
  version: string;
  tasks: Record<string, Parameter[]>;
  sensors: string[];
}

export type Task = {
  repository: string;
  target: string;
  version: string;
  parameters: Parameter[];
}

export type BaseRun = {
  id: string;
  createdAt: string;
  // TODO: ?
}

export type Run = BaseRun & {
  tags: string[];
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
  executionId: string | null;
  createdAt: string;
  dependencyIds: string[];
  runIds: string[];
  assignedAt: string | null;
  result: Result | null;
}

export type Result = {
  type: number; // TODO
  value: string;
  createdAt: string;
}

export type SensorActivation = {
  repository: string;
  target: string;
  tags: string[];
  createdAt: string;
  deactivatedAt: string | null;
  runs: Record<string, BaseRun>;
}

export type LogMessage = {
  executionId: string;
  level: 0 | 1 | 2 | 3;
  message: string;
  createdAt: string;
}

export type Task = {
  id: string;
  repository: string;
  target: string;
  version: string;
}

export type Run = {
  id: string;
  steps: Step[];
}

export type Step = {
  id: string;
  repository: string;
  target: string;
  createdAt: string;
  arguments: Argument[];
  executions: Execution[];
}

export type Argument = {
  type: number; // TODO
  value: string;
}

export type Execution = {
  id: string;
  createdAt: string;
  childSteps: Pick<Step, 'id'>[];
  dependencyIds: string[];
  assignedAt: string;
  result: Result | null;
}

export type Result = {
  type: number; // TODO
  value: string;
  createdAt: string;
}


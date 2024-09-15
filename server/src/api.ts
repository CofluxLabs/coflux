export class RequestError extends Error {
  readonly code: string;
  readonly details: Record<string, string>;

  constructor(code: string, details: Record<string, string>) {
    super(`request error (${code})`);
    this.code = code;
    this.details = details;
  }
}

async function request(name: string, data: Record<string, any>) {
  const res = await fetch(`/api/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data),
  });
  if (res.status == 200) {
    return await res.json();
  } else if (res.status == 400) {
    const data = await res.json();
    throw new RequestError(data.error, data.details);
  } else {
    throw new Error(`request failed (${res.status})`);
  }
}

export function createProject(projectName: string) {
  return request("create_project", { projectName });
}

export function createEnvironment(
  projectId: string,
  name: string,
  baseId: string | null,
) {
  return request("create_environment", { projectId, name, baseId });
}

export function scheduleWorkflow(
  projectId: string,
  repository: string,
  target: string,
  environmentName: string,
  arguments_: ["json", string][],
  options?: Partial<{
    waitFor: number[];
    cache: {
      params: number[] | true;
      maxAge?: number;
      namespace?: string;
      version?: string;
    };
    defer: {
      params: number[] | true;
    };
    executeAfter: number | null;
    retries: {
      limit: number;
      delayMin?: number;
      delayMax?: number;
    };
    requires: Record<string, string[]>;
  }>,
) {
  return request("schedule_workflow", {
    ...options,
    projectId,
    repository,
    target,
    environmentName,
    arguments: arguments_,
  });
}

export function scheduleSensor(
  projectId: string,
  repository: string,
  target: string,
  environmentName: string,
  arguments_: ["json", string][],
  options?: Partial<{
    requires: Record<string, string[]>;
  }>,
) {
  return request("schedule_sensor", {
    ...options,
    projectId,
    repository,
    target,
    environmentName,
    arguments: arguments_,
  });
}

export function rerunStep(
  projectId: string,
  stepId: string,
  environmentName: string,
) {
  return request("rerun_step", { projectId, stepId, environmentName });
}

export function cancelRun(projectId: string, runId: string) {
  return request("cancel_run", { projectId, runId });
}

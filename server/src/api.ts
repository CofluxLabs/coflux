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
  base: string | null,
) {
  return request("create_environment", { projectId, name, base });
}

export function schedule(
  projectId: string,
  repository: string,
  target: string,
  environment: string,
  arguments_: ["json", string][],
) {
  return request("schedule", {
    projectId,
    repository,
    target,
    environment,
    arguments: arguments_,
  });
}

export function rerunStep(
  projectId: string,
  stepId: string,
  environment: string,
) {
  return request("rerun_step", { projectId, stepId, environment });
}

export function cancelRun(projectId: string, runId: string) {
  return request("cancel_run", { projectId, runId });
}

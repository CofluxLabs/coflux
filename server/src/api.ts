import { toPairs } from "lodash";

export class RequestError extends Error {
  readonly code: string;
  readonly details: Record<string, string>;

  constructor(code: string, details: Record<string, string>) {
    super(`request error (${code})`);
    this.code = code;
    this.details = details;
  }
}

async function handleResponse(res: Response) {
  if (res.status == 200) {
    return await res.json();
  } else if (res.status == 204) {
    return;
  } else if (res.status == 400) {
    const data = await res.json();
    throw new RequestError(data.error, data.details);
  } else {
    throw new Error(`request failed (${res.status})`);
  }
}

async function post(name: string, data: Record<string, any>) {
  const res = await fetch(`/api/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data),
  });
  return await handleResponse(res);
}

async function get(name: string, params?: Record<string, any>) {
  const queryString =
    params &&
    toPairs(params)
      .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
      .join("&");
  const res = await fetch(
    `/api/${name}${queryString ? `?${queryString}` : ""}`,
  );
  return await handleResponse(res);
}

export function createProject(projectName: string) {
  return post("create_project", { projectName });
}

export function createEnvironment(
  projectId: string,
  name: string,
  baseId: string | null,
) {
  return post("create_environment", { projectId, name, baseId });
}

export function pauseEnvironment(projectId: string, environmentId: string) {
  return post("pause_environment", { projectId, environmentId });
}

export function resumeEnvironment(projectId: string, environmentId: string) {
  return post("resume_environment", { projectId, environmentId });
}

export function archiveRepository(
  projectId: string,
  environmentName: string,
  repositoryName: string,
) {
  return post("archive_repository", {
    projectId,
    environmentName,
    repositoryName,
  });
}

export function stopAgent(
  projectId: string,
  environmentName: string,
  agentId: string,
) {
  return post("stop_agent", {
    projectId,
    environmentName,
    agentId,
  });
}

export function resumeAgent(
  projectId: string,
  environmentName: string,
  agentId: string,
) {
  return post("resume_agent", {
    projectId,
    environmentName,
    agentId,
  });
}

export function submitWorkflow(
  projectId: string,
  repository: string,
  target: string,
  environmentName: string,
  arguments_: ["json", string][],
  options?: Partial<{
    waitFor: number[];
    cache: {
      params: number[] | true;
      maxAge: number | null;
      namespace: string | null;
      version: string | null;
    } | null;
    defer: {
      params: number[] | true;
    } | null;
    executeAfter: number | null;
    retries: {
      limit: number;
      delayMin?: number;
      delayMax?: number;
    } | null;
    requires: Record<string, string[]>;
  }>,
) {
  return post("submit_workflow", {
    ...options,
    projectId,
    repository,
    target,
    environmentName,
    arguments: arguments_,
  });
}

export function startSensor(
  projectId: string,
  repository: string,
  target: string,
  environmentName: string,
  arguments_: ["json", string][],
  options?: Partial<{
    requires: Record<string, string[]>;
  }>,
) {
  return post("start_sensor", {
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
  return post("rerun_step", { projectId, stepId, environmentName });
}

export function cancelExecution(projectId: string, executionId: string) {
  return post("cancel_execution", { projectId, executionId });
}

export function search(
  projectId: string,
  environmentId: string,
  query: string,
) {
  return get("search", { projectId, environmentId, query });
}

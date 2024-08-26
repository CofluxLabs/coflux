import { useTopic } from "@topical/react";

import * as models from "./models";

export function useProjects() {
  const [projects] = useTopic<Record<string, models.Project>>("projects");
  return projects;
}

export function useEnvironments(projectId: string | undefined) {
  const [environments] = useTopic<Record<string, models.Environment>>(
    "projects",
    projectId,
    "environments",
  );
  return environments;
}

export function useRepositories(
  projectId: string | undefined,
  environmentId: string | undefined,
) {
  const [repositories] = useTopic<Record<string, models.Repository>>(
    "projects",
    projectId,
    "repositories",
    environmentId,
  );
  return repositories;
}

export function useAgents(
  projectId: string | undefined,
  environmentId: string | undefined,
) {
  const [agents] = useTopic<Record<string, Record<string, string[]>>>(
    "projects",
    projectId,
    "agents",
    environmentId,
  );
  return agents;
}

export function useTarget(
  projectId: string | undefined,
  repository: string | undefined,
  targetName: string | undefined,
  environmentId: string | undefined,
) {
  const [target] = useTopic<models.Target>(
    "projects",
    projectId,
    "targets",
    repository,
    targetName,
    environmentId,
  );
  return target;
}

export function useExecutions(
  projectId: string | undefined,
  repositoryName: string | undefined,
  environmentId: string | undefined,
) {
  const [executions] = useTopic<Record<string, models.QueuedExecution>>(
    "projects",
    projectId,
    "repositories",
    repositoryName,
    environmentId,
  );
  return executions;
}

export function useRun(
  projectId: string | undefined,
  runId: string | undefined,
  environmentId: string | undefined,
) {
  const [run] = useTopic<models.Run>(
    "projects",
    projectId,
    "runs",
    runId,
    environmentId,
  );
  return run;
}
export function useLogs(
  projectId: string | undefined,
  runId: string | undefined,
  environmentId: string | undefined,
) {
  const [logs] = useTopic<models.LogMessage[]>(
    "projects",
    projectId,
    "runs",
    runId,
    "logs",
    environmentId,
  );
  return logs;
}

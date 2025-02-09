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

export function usePools(
  projectId: string | undefined,
  environmentId: string | undefined,
) {
  const [pools] = useTopic<models.Pools>(
    "projects",
    projectId,
    "pools",
    environmentId,
  );
  return pools;
}

export function usePool(
  projectId: string | undefined,
  environmentId: string | undefined,
  poolName: string | undefined,
) {
  const [pool] = useTopic<{
    pool: models.Pool | null;
    agents: Record<string, models.Agent>;
  }>("projects", projectId, "pools", environmentId, poolName);
  return pool;
}

export function useSessions(
  projectId: string | undefined,
  environmentId: string | undefined,
) {
  const [sessions] = useTopic<Record<string, models.Session>>(
    "projects",
    projectId,
    "sessions",
    environmentId,
  );
  return sessions;
}

export function useWorkflow(
  projectId: string | undefined,
  repository: string | undefined,
  targetName: string | undefined,
  environmentId: string | undefined,
) {
  const [target] = useTopic<models.Workflow>(
    "projects",
    projectId,
    "workflows",
    repository,
    targetName,
    environmentId,
  );
  return target;
}

export function useSensor(
  projectId: string | undefined,
  repository: string | undefined,
  targetName: string | undefined,
  environmentId: string | undefined,
) {
  const [target] = useTopic<models.Sensor>(
    "projects",
    projectId,
    "sensors",
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

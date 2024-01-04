import { useTopic } from "@topical/react";
import { useCallback } from "react";

import * as models from "./models";

export function useRunTopic(
  projectId: string | undefined,
  environmentName: string | undefined,
  runId: string | undefined
): [models.Run | undefined, (stepId: string) => Promise<number>, () => void] {
  const [run, { execute }] = useTopic<models.Run>(
    "projects",
    projectId,
    "environments",
    environmentName,
    "runs",
    runId
  );
  const rerunStep = useCallback(
    (stepId: string) => execute("rerun_step", stepId),
    [execute]
  );
  const cancelRun = useCallback(() => execute("cancel_run"), [execute]);
  return [run, rerunStep, cancelRun];
}

export function useTargetTopic(
  projectId: string | undefined,
  environmentName: string | undefined,
  repository: string | undefined,
  targetName: string | undefined
): [
  models.Target | undefined,
  (parameters: ["json", string][]) => Promise<string>
] {
  const [target, { execute }] = useTopic<models.Target>(
    "projects",
    projectId,
    "environments",
    environmentName,
    "targets",
    repository,
    targetName
  );
  const startRun = useCallback(
    (paremeters: ["json", string][]) => {
      return execute("start_run", paremeters);
    },
    [execute]
  );
  return [target, startRun];
}

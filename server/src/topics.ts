import { useTopic } from "@topical/react";

import * as models from "./models";

export function useRunTopic(
  projectId: string | undefined,
  runId: string | undefined,
): models.Run | undefined {
  const [run] = useTopic<models.Run>("projects", projectId, "runs", runId);
  return run;
}

export function useTargetTopic(
  projectId: string | undefined,
  repository: string | undefined,
  targetName: string | undefined,
  environmentName: string | undefined,
): models.Target | undefined {
  const [target] = useTopic<models.Target>(
    "projects",
    projectId,
    "targets",
    repository,
    targetName,
    environmentName,
  );
  return target;
}

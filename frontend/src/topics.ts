import { useTopic } from '@topical/react';
import { useCallback } from 'react';

import * as models from './models';

export function useRunTopic(
  projectId: string | undefined,
  environmentName: string | undefined,
  runId: string | undefined
): [models.Run | undefined, (stepId: string) => Promise<number>] {
  const [run, { execute }] = useTopic<models.Run>("projects", projectId, "environments", environmentName, "runs", runId);
  const rerunStep = useCallback((stepId: string) => {
    return execute('rerun_step', stepId);
  }, [execute]);
  return [run, rerunStep];
}

export function useTaskTopic(
  projectId: string | undefined,
  environmentName: string | undefined,
  repository: string | undefined,
  target: string | undefined
): [models.Task | undefined, (parameters: ['json', string][]) => Promise<string>] {
  const [task, { execute }] = useTopic<models.Task>("projects", projectId, "environments", environmentName, "tasks", repository, target);
  const startRun = useCallback((paremeters: ['json', string][]) => {
    return execute('start_run', paremeters);
  }, [execute]);
  return [task, startRun];
}

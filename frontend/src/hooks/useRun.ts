import useSWR from 'swr';

import * as models from '../models';

export default function useRun(projectId: string | null, runId: string | null) {
  const { data, error } = useSWR<models.Run>(projectId && runId && `/projects/${projectId}/runs/${runId}`);
  return { run: data, error };
}

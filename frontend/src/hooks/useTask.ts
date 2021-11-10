import useSWR from 'swr';

import * as models from '../models';

export default function useTask(projectId: string | null, taskId: string | null) {
  const { data, error } = useSWR<models.Task>(projectId && taskId && `/projects/${projectId}/tasks/${taskId}`);
  return { task: data, error };
}

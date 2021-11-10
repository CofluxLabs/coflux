import useSWR from 'swr';

import * as models from '../models';

export default function useTasks(projectId: string | null) {
  const { data, error } = useSWR<models.Task[]>(projectId && `/projects/${projectId}/tasks`);
  return { tasks: data, error };
}

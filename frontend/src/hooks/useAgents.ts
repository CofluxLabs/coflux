import useSWR from 'swr';

import * as models from '../models';

export default function useAgents(projectId: string | null) {
  const { data, error } = useSWR<models.Agent[]>(projectId && `/projects/${projectId}/agents`);
  return { agents: data, error };
}

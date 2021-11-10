import useSWR from 'swr';

export default function useTaskRuns(projectId: string | null, taskId: string | null) {
  const { data, error } = useSWR<{ id: string, createdAt: string }[]>(projectId && taskId && `/projects/${projectId}/tasks/${taskId}/runs`);
  return { runs: data, error };
}

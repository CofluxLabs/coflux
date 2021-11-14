import React from 'react';
import Link from 'next/link';

import useTaskRuns from '../hooks/useTaskRuns';

type Props = {
  projectId: string | null;
  taskId: string | null;
}

export default function TaskRunsList({ projectId, taskId }: Props) {
  const { runs, error } = useTaskRuns(projectId, taskId);
  if (error) {
    return <div>Error</div>;
  } else if (!runs) {
    return <div>Loading...</div>;
  } else {
    return (
      <ul>
        {runs.map((run) => (
          <li key={run.id}>
            <Link href={`/projects/${projectId}/runs/${run.id}`}>
              <a className="underline">{run.createdAt}</a>
            </Link>
          </li>
        ))}
      </ul>
    );
  }
}

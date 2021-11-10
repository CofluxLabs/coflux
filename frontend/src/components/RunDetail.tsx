import React from 'react';

import useRun from '../hooks/useRun';
import RunTimeline from './RunTimeline';

type Props = {
  projectId: string | null;
  runId: string | null;
}

export default function RunDetail({ projectId, runId }: Props) {
  const { run, error } = useRun(projectId, runId);
  if (error) {
    return <div>Error</div>;
  } else if (!run) {
    return <div>Loading...</div>;
  } else {
    return (
      <div>
        <RunTimeline run={run} />
      </div>
    );
  }
}


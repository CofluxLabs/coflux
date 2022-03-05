import { useParams, useSearchParams } from 'react-router-dom';

import RunTimeline from '../components/RunTimeline';
import { useRun } from '../layouts/RunLayout';

export default function TimelinePage() {
  const run = useRun();
  const { project: projectId } = useParams();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get('environment');
  const activeStepId = searchParams.get('step');
  return (
    <div>
      <RunTimeline run={run} projectId={projectId} environmentName={environmentName} activeStepId={activeStepId} />
    </div>
  );
}

import { useParams, useSearchParams } from 'react-router-dom';

import RunGraph from '../components/RunGraph';
import { useRun } from '../layouts/RunLayout';

export default function GraphPage() {
  const run = useRun();
  const { project: projectId } = useParams();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get('environment') || undefined;
  const activeStepId = searchParams.get('step') || undefined;
  const activeAttemptNumber = searchParams.has('attempt') ? parseInt(searchParams.get('attempt')) : undefined;
  return (
    <div>
      <RunGraph
        run={run}
        projectId={projectId}
        environmentName={environmentName}
        activeStepId={activeStepId}
        activeAttemptNumber={activeAttemptNumber}
      />
    </div>
  );
}

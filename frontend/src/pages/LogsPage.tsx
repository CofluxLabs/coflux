import { useParams, useSearchParams } from 'react-router-dom';

import * as models from '../models';
import useSubscription from '../hooks/useSubscription';
import { useRun } from '../layouts/RunLayout';
import RunLogs from '../components/RunLogs';

export default function LogsPage() {
  const run = useRun();
  const logs = useSubscription<Record<string, models.LogMessage>>('run_logs', run.id);
  const { project: projectId } = useParams();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get('environment');
  const activeStepId = searchParams.get('step');
  const activeAttemptNumber = searchParams.has('attempt') ? parseInt(searchParams.get('attempt')) : null;
  return (
    <div>
      {logs && (
        <RunLogs
          run={run}
          logs={logs}
          projectId={projectId}
          environmentName={environmentName}
          activeStepId={activeStepId}
          activeAttemptNumber={activeAttemptNumber}
        />
      )}
    </div>
  );
}

import { Fragment } from 'react';

import * as models from '../models';
import RunButton from './RunButton';
import RunSelector from './RunSelector';
import TargetHeader from './TargetHeader';

type Props = {
  task: models.Task;
  projectId: string;
  runId?: string;
  environmentName: string | undefined;
  onRun: (parameters: ['json', string][]) => Promise<void>;
}

export default function TaskHeader({ task, projectId, runId, environmentName, onRun }: Props) {
  return (
    <TargetHeader target={task.target} repository={task.repository}>
      <div className="flex-1 flex items-center justify-between">
        <div className="flex items-center">
          {runId && (
            <Fragment>
              <span className="ml-2">→</span>
              <RunSelector className="ml-2" runs={task.runs} projectId={projectId} runId={runId} environmentName={environmentName} />
            </Fragment>
          )}
        </div>
        {environmentName && (
          <RunButton task={task} onRun={onRun} />
        )}
      </div>
    </TargetHeader >
  );
}

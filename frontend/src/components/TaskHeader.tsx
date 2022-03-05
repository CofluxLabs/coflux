import { Fragment } from 'react';

import * as models from '../models';
import RunButton from './RunButton';
import RunSelector from './RunSelector';

type Props = {
  task: models.Task;
  projectId: string;
  runId?: string;
  environmentName: string | undefined;
}

export default function TaskHeader({ task, projectId, runId, environmentName }: Props) {
  return (
    <div className="p-4 flex">
      <h1 className="flex items-center flex-1">
        <span className="text-xl font-bold font-mono">{task.target}</span>
        <span className="ml-2 text-gray-500">({task.repository})</span>
        {runId && (
          <Fragment>
            <span className="ml-2">→</span>
            <RunSelector className="ml-2" runs={task.runs} projectId={projectId} runId={runId} environmentName={environmentName} />
          </Fragment>
        )}
      </h1>
      {environmentName && (
        <RunButton task={task} projectId={projectId} environmentName={environmentName} />
      )}
    </div>
  );
}

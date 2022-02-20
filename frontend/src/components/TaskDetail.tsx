import React from 'react';
import Router from 'next/router';
import { maxBy } from 'lodash';

import * as models from '../models';
import Heading from './Heading';
import { useSubscription } from '../hooks/useSocket';
import RunButton from './RunButton';

type State = models.Task & {
  runs: Record<string, models.BaseRun>
};

type Props = {
  projectId: string;
  taskId: string;
  environmentName: string;
}

export default function TaskDetail({ projectId, taskId, environmentName }: Props) {
  const [repository, target] = taskId.split(':', 2);
  const task = useSubscription<State>('task', repository, target, environmentName);
  if (task === undefined) {
    return <p>Loading...</p>
  } else if (task === null) {
    return <p>Not found</p>
  } else if (!Object.keys(task.runs).length) {
    return (
      <div className="px-4 py-3">
        <div className="flex items-center">
          <Heading className="flex-1"><span className="font-mono">{task.target}</span> <span className="text-gray-500">({task.repository})</span></Heading>
          <RunButton projectId={projectId} repository={repository} target={target} environmentName={environmentName} />
        </div>
        <p className="text-slate-500">This task hasn&apos;t been run yet.</p>
      </div>
    );
  } else {
    const latestRun = maxBy(Object.values(task.runs), 'createdAt');
    Router.replace(`/projects/${projectId}/runs/${latestRun!.id}`);
    return null;
  }
}

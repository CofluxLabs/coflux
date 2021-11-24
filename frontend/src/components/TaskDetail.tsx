import React, { Fragment, useCallback, useState } from 'react';
import Router from 'next/router';
import Link from 'next/link';
import classNames from 'classnames';
import { sortBy } from 'lodash';

import * as models from '../models';
import Heading from './Heading';
import RunDialog from './RunDialog';
import useSocket, { useSubscription } from '../hooks/useSocket';

type State = models.Task & {
  runs: Record<string, { id: string, createdAt: string }>
};

type Props = {
  projectId: string | null;
  taskId: string | null;
}

export default function TaskDetail({ projectId, taskId }: Props) {
  const { socket } = useSocket();
  const [starting, setStarting] = useState(false);
  const [runDialogOpen, setRunDialogOpen] = useState(false);
  const handleRunClick = useCallback(() => {
    setRunDialogOpen(true);
  }, []);
  const handleStartRun = useCallback((args) => {
    setStarting(true);
    socket?.request('start_run', [taskId, args], (runId) => {
      setStarting(false);
      setRunDialogOpen(false);
      Router.push(`/projects/${projectId}/runs/${runId}`);
    });
  }, [projectId, taskId, socket]);
  const handleRunDialogClose = useCallback(() => setRunDialogOpen(false), []);
  const task = useSubscription<State>(`tasks.${taskId}`);
  if (!task) {
    return <p>Loading...</p>
  } else {
    return (
      <Fragment>
        <div className="flex">
          <Heading className="flex-1"><span className="font-mono">{task.target}</span> <span className="text-gray-500">({task.repository})</span></Heading>
          <button
            className="px-4 py-2 my-3 border border-blue-400 text-blue-500 rounded font-bold hover:bg-blue-100"
            onClick={handleRunClick}
          >
            Run...
          </button>
          <RunDialog task={task} open={runDialogOpen} starting={starting} onRun={handleStartRun} onClose={handleRunDialogClose} />
        </div>
        <ul>
          {sortBy(Object.values(task.runs), 'createdAt').map((run) => (
            <li key={run.id}>
              <Link href={`/projects/${projectId}/runs/${run.id}`}>
                <a className="underline">{run.id} ({run.createdAt})</a>
              </Link>
            </li>
          ))}
        </ul>
      </Fragment>
    );
  }
}

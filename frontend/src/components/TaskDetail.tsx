import React, { Fragment, useCallback, useState } from 'react';
import Router from 'next/router';
import Link from 'next/link';
import classNames from 'classnames';
import { sortBy } from 'lodash';

import * as models from '../models';
import Heading from './Heading';
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
  const handleRunClick = useCallback(() => {
    setStarting(true);
    socket?.request('start_run', [taskId], (runId) => {
      setStarting(false);
      Router.push(`/projects/${projectId}/runs/${runId}`);
    });
  }, [socket, projectId, taskId]);
  const task = useSubscription<State>(`tasks.${taskId}`);
  if (!task) {
    return <p>Loading...</p>
  } else {
    return (
      <Fragment>
        <div className="flex">
          <Heading className="flex-1"><span className="font-mono">{task.target}</span> <span className="text-gray-500">({task.repository})</span></Heading>
          <button
            className={classNames("px-4 py-2 my-3 bg-blue-600 rounded text-white font-bold", starting ? 'opacity-50' : 'hover:bg-blue-700')}
            disabled={starting}
            onClick={handleRunClick}
          >
            Run
          </button>
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

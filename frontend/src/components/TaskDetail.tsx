import React, { Fragment, useCallback } from 'react';
import Router from 'next/router';
import Link from 'next/link';

import * as models from '../models';
import Heading from './Heading';
import { useSubscription } from '../hooks/useSocket';

type State = models.Task & { runs: {
  id: string;
  createdAt: string;
}[] };

type Props = {
  projectId: string | null;
  taskId: string | null;
}

export default function TaskDetail({ projectId, taskId }: Props) {
  const handleRunClick = useCallback(() => {
    // TODO: get base URL from config?
    fetch(`http://localhost:7070/projects/${projectId}/tasks/${taskId}/runs`, { method: 'POST' })
      .then((response) => response.json())
      .then((result) => {
        Router.push(`/projects/${projectId}/runs/${result.id}`);
      });
  }, [projectId, taskId]);
  const task = useSubscription<State>(`tasks.${taskId}`);
  if (!task) {
    return <p>Loading...</p>
  } else {
    return (
      <Fragment>
        <div className="flex">
          <Heading className="flex-1"><span className="font-mono">{task.target}</span> <span className="text-gray-500">({task.repository})</span></Heading>
          <button
            className="px-4 py-2 my-3 bg-blue-600 hover:bg-blue-700 rounded text-white font-bold"
            onClick={handleRunClick}
          >
            Run
          </button>
        </div>
        <ul>
          {task.runs.map((run) => (
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

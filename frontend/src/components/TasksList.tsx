import React from 'react';
import Link from 'next/link';
import classNames from 'classnames';

import * as models from '../models';
import { useSubscription } from '../hooks/useSocket';

function extractTasks(repositories: Record<string, models.Repository>) {
  return Object.entries(repositories).flatMap(([repositoryName, repository]) => {
    return Object.keys(repository.tasks).map((target) => (
      {
        id: `${repositoryName}:${target}`,
        repository: repositoryName,
        target: target
      }
    ))
  });
}

type Props = {
  projectId: string | null;
  taskId?: string | null;
}

export default function TasksList({ projectId, taskId: activeTaskId }: Props) {
  const repositories = useSubscription<Record<string, models.Repository>>('repositories');
  if (repositories === undefined) {
    return <div>Loading...</div>;
  } else {
    const tasks = extractTasks(repositories);
    return (
      <div className="py-2">
        <div className="flex items-center mt-4 p-1 pl-4">
          <h2 className="flex-1 font-bold uppercase text-gray-500 text-sm">Tasks</h2>
        </div>
        {tasks.length ? (
          <ul>
            {tasks.map((task) => (
              <li key={task.id}>
                <Link href={`/projects/${projectId}/tasks/${task.id}`}>
                  <a className={classNames('block hover:bg-gray-300 px-4 py-2', { 'bg-gray-300': task.id == activeTaskId })}>
                    <div className="font-mono">{task.target}</div>
                    <div className="text-sm text-gray-500">{task.repository}</div>
                  </a>
                </Link>
              </li>
            ))}
          </ul>
        ) : (
          <p className="px-4 text-gray-400 italic">No tasks</p>
        )}
      </div>
    );
  }
}

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
          <h2 className="flex-1 font-bold uppercase text-gray-400 text-sm">Tasks</h2>
        </div>
        {tasks.length ? (
          <ul>
            {tasks.map((task) => {
              const isActive = task.id == activeTaskId;
              return (
                <li key={task.id}>
                  <Link href={`/projects/${projectId}/tasks/${task.id}`}>
                    <a className={classNames('block px-4 py-2 group', isActive && 'bg-gray-600')}>
                      <div className={classNames('font-mono text-gray-100', !isActive && 'group-hover:underline')}>{task.target}</div>
                      <div className="text-sm text-gray-400">{task.repository}</div>
                    </a>
                  </Link>
                </li>
              );
            })}
          </ul>
        ) : (
          <p className="px-4 text-gray-400 italic">No tasks</p>
        )}
      </div>
    );
  }
}

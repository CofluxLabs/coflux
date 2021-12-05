import React from 'react';
import Link from 'next/link';
import classNames from 'classnames';

import * as models from '../models';
import { useSubscription } from '../hooks/useSocket';

type Props = {
  projectId: string | null;
  taskId?: string | null;
}

export default function TasksList({ projectId, taskId: activeTaskId }: Props) {
  const repositories = useSubscription<Record<string, models.Repository>>('repositories');
  if (repositories === undefined) {
    return <div>Loading...</div>;
  } else {
    return (
      <div>
        {Object.keys(repositories).length ? (
          <ul>
            {Object.keys(repositories).sort().map((repository) => (
              <li key={repository}>
                <h3 className="px-3 pt-3 py-2 flex items-center">
                  <span className="font-bold text-gray-900">{repository}</span>
                  <span className="text-sm text-gray-500 truncate ml-1">@{repositories[repository].version}</span>
                </h3>
                <ul>
                  {Object.keys(repositories[repository].tasks).sort().map((target) => {
                    const taskId = `${repository}:${target}`;
                    return (
                      <li key={target}>
                        <Link href={`/projects/${projectId}/tasks/${taskId}`}>
                          <a className={classNames('block font-mono hover:bg-gray-300 px-4 py-1', { 'bg-gray-300': taskId == activeTaskId })}>
                            {target}
                          </a>
                        </Link>
                      </li>
                    );
                  })}
                </ul>
              </li>
            ))}
          </ul>
        ) : (
          <p>No repositories</p>
        )}
      </div>
    );
  }
}

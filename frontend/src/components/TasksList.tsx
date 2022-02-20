import React, { Fragment } from 'react';
import Link from 'next/link';
import classNames from 'classnames';

import * as models from '../models';
import { useSubscription } from '../hooks/useSocket';

type Props = {
  projectId: string;
  environmentName: string;
  taskId?: string | null;
}

export default function TasksList({ projectId, environmentName, taskId: activeTaskId }: Props) {
  const repositories = useSubscription<Record<string, models.Manifest>>('repositories', environmentName);
  if (repositories === undefined) {
    return <div>Loading...</div>;
  } else {
    return (
      <div className="p-2">
        {Object.values(repositories).map((manifest) => (
          <Fragment key={manifest.repository}>
            <div className="flex items-center mt-4 py-1 px-2">
              <h2 className="flex-1 font-bold uppercase text-slate-400 text-sm">{manifest.repository}</h2>
            </div>
            <ul>
              {Object.keys(manifest.tasks).map((target) => {
                const taskId = `${manifest.repository}:${target}`;
                const isActive = taskId == activeTaskId;
                return (
                  <li key={target}>
                    <Link href={`/projects/${projectId}/tasks/${taskId}?environment=${environmentName}`}>
                      <a className={classNames('block px-2 py-0.5 my-0.5 rounded-md', isActive ? 'bg-slate-200' : 'hover:bg-slate-200/50')}>
                        <div className={classNames('font-mono text-slate-900')}>{target}</div>
                      </a>
                    </Link>
                  </li>
                );
              })}
            </ul>
          </Fragment>
        ))}
      </div>
    );
  }
}

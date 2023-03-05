import { useTopic } from '@topical/react';
import classNames from 'classnames';
import { Fragment } from 'react';
import { Link } from 'react-router-dom';

import * as models from '../models';
import { buildUrl } from '../utils';
import Loading from './Loading';

type TasksListProps = {
  projectId: string | undefined;
  environmentName: string | undefined;
  activeTarget: { repository: string, target: string } | undefined;
}

export default function TasksList({ projectId, environmentName, activeTarget }: TasksListProps) {
  const [repositories, _] = useTopic<Record<string, models.Manifest>>("projects", projectId, "environments", environmentName, "repositories");
  if (!repositories) {
    return <Loading />;
  } else if (!Object.keys(repositories).length) {
    return (
      <div className="p-2">
        <p className="text-slate-400">No repositories</p>
      </div>
    );
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
                const isActive = activeTarget && activeTarget.repository == manifest.repository && activeTarget.target == target;
                return (
                  <li key={target}>
                    <Link
                      to={buildUrl(`/projects/${projectId}/tasks/${manifest.repository}/${target}`, { environment: environmentName })}
                      className={classNames('block px-2 py-0.5 my-0.5 rounded-md', isActive ? 'bg-slate-200' : 'hover:bg-slate-200/50')}
                    >
                      <div className={classNames('font-mono text-slate-900')}>{target}</div>
                    </Link>
                  </li>
                );
              })}
              {manifest.sensors.map((target) => {
                const isActive = activeTarget && activeTarget.repository == manifest.repository && activeTarget.target == target;
                return (
                  <li key={target}>
                    <Link
                      to={buildUrl(`/projects/${projectId}/sensors/${manifest.repository}/${target}`, { environment: environmentName })}
                      className={classNames('block px-2 py-0.5 my-0.5 rounded-md', isActive ? 'bg-slate-200' : 'hover:bg-slate-200/50')}
                    >
                      <div className={classNames('font-mono text-slate-900')}>{target}</div>
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

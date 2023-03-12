import { useTopic } from '@topical/react';
import classNames from 'classnames';
import { ComponentType, Fragment } from 'react';
import { Link } from 'react-router-dom';
import { IconSubtask, IconCpu, TablerIconsProps } from '@tabler/icons-react';

import * as models from '../models';
import { buildUrl } from '../utils';
import Loading from './Loading';


type TargetProps = {
  url: string;
  icon: ComponentType<TablerIconsProps>;
  target: string;
  isActive: boolean;
}

function Target({ url, icon: Icon, target, isActive }: TargetProps) {
  return (
    <li>
      <Link
        to={url}
        className={classNames('block px-2 py-0.5 my-0.5 rounded-md text-slate-900 flex gap-1', isActive ? 'bg-slate-200' : 'hover:bg-slate-200/50')}
      >
        <Icon size={20} strokeWidth={1} className="text-slate-500" />
        <div className="font-mono flex-1">{target}</div>
      </Link>
    </li>
  );
}

type Props = {
  projectId: string | undefined;
  environmentName: string | undefined;
  activeTarget: { repository: string, target: string } | undefined;
}

export default function TargetsList({ projectId, environmentName, activeTarget }: Props) {
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
                  <Target key={target} target={target} icon={IconSubtask} url={buildUrl(`/projects/${projectId}/tasks/${manifest.repository}/${target}`, { environment: environmentName })} isActive={isActive} />
                );
              })}
              {manifest.sensors.map((target) => {
                const isActive = activeTarget && activeTarget.repository == manifest.repository && activeTarget.target == target;
                return (
                  <Target key={target} target={target} icon={IconCpu} url={buildUrl(`/projects/${projectId}/sensors/${manifest.repository}/${target}`, { environment: environmentName })} isActive={isActive} />
                );
              })}
            </ul>
          </Fragment>
        ))}
      </div>
    );
  }
}
import React, { Fragment, ReactNode, useCallback } from 'react';
import classNames from 'classnames';

import * as models from '../models';
import useSocket, { useSubscription } from '../hooks/useSocket';
import TasksList from './TasksList';
import SensorsList from './SensorsList';
import { SocketStatus } from '../socket';


function optionsForSocketStatus(status: SocketStatus | undefined) {
  switch (status) {
    case 'connected':
      return ['●', 'text-emerald-400', 'Connected'];
    case 'connecting':
      return ['○', 'text-slate-400', 'Connecting...'];
    default:
      return ['○', 'text-slate-200', 'Disconnected'];
  }
}

type EnvironmentSelectorProps = {
  selectedName: string | null | undefined;
  className?: string;
  onChange: (environmentName: string) => void;
}

function EnvironmentSelector({ selectedName, className, onChange }: EnvironmentSelectorProps) {
  const environments = useSubscription<Record<string, models.Environment>>('environments');
  const handleChange = useCallback((ev) => onChange(ev.target.value), [onChange]);
  return (
    <div className={className}>
      {environments === undefined ? (
        <p>Loading...</p>
      ) : !Object.keys(environments).length ? (
        <p>No environments</p>
      ) : (
        <select
          value={selectedName || ""}
          onChange={handleChange}
          className="text-slate-300 bg-slate-700 rounded p-2 w-full"
        >
          <option value="">Select...</option>
          {Object.entries(environments).map(([environmentId, environment]) => (
            <option value={environment.name} key={environmentId}>
              {environment.name}
            </option>
          ))}
        </select>
      )}
    </div>
  );
}

type Props = {
  projectId: string | null;
  environmentName: string | null | undefined;
  taskId?: string | null;
  sensorId?: string | null;
  children: ReactNode;
  onEnvironmentChange: (environmentName: string) => void;
}

export default function ProjectLayout({ projectId, environmentName, taskId, sensorId, children, onEnvironmentChange }: Props) {
  const { status } = useSocket();
  const [statusIcon, statusIconClassName, statusText] = optionsForSocketStatus(status);
  return (
    <div className="flex flex-col min-h-screen max-h-screen">
      <div className="flex bg-slate-700 px-3 items-center h-14 flex-none">
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="currentColor" className="fill-slate-200 mr-2" viewBox="0 0 16 16">
          <path d="M3.1.7a.5.5 0 0 1 .4-.2h9a.5.5 0 0 1 .4.2l2.976 3.974c.149.185.156.45.01.644L8.4 15.3a.5.5 0 0 1-.8 0L.1 5.3a.5.5 0 0 1 0-.6l3-4zm11.386 3.785-1.806-2.41-.776 2.413 2.582-.003zm-3.633.004.961-2.989H4.186l.963 2.995 5.704-.006zM5.47 5.495 8 13.366l2.532-7.876-5.062.005zm-1.371-.999-.78-2.422-1.818 2.425 2.598-.003zM1.499 5.5l5.113 6.817-2.192-6.82L1.5 5.5zm7.889 6.817 5.123-6.83-2.928.002-2.195 6.828z" />
        </svg>
        <span className="text-slate-100 font-bold text-lg mr-5">Coflux</span>
        <EnvironmentSelector selectedName={environmentName} onChange={onEnvironmentChange} />
        <span className="flex-1"></span>
        <span className="text-slate-100 rounded px-3 py-1 hover:bg-slate-600 mr-1">
          {projectId}
          <span className="text-slate-600 text-xs ml-2">▼</span>
        </span>
      </div>
      <div className="flex-auto flex overflow-hidden">
        <div className="w-64 bg-slate-100 text-gray-100 border-r border-slate-200 overflow-auto flex flex-col">
          <div className="flex-1">
            {projectId && environmentName && (
              <Fragment>
                <TasksList projectId={projectId} environmentName={environmentName} taskId={taskId} />
                <SensorsList projectId={projectId} sensorId={sensorId} />
              </Fragment>
            )}
          </div>
          <div className="p-3 flex items-center border-t border-slate-200">
            <span className={classNames("text-emerald-400 text-opacity-70", statusIconClassName)}>
              {statusIcon}
            </span>
            <span className="ml-1 text-slate-700">{statusText}</span>
          </div>
        </div>
        <div className="flex-1 flex flex-col">
          {children}
        </div>
      </div>
    </div>
  );
}

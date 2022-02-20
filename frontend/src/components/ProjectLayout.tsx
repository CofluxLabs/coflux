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
  onChange: (environmentName: string) => void;
}

function EnvironmentSelector({ selectedName, onChange }: EnvironmentSelectorProps) {
  const environments = useSubscription<Record<string, models.Environment>>('environments');
  const handleChange = useCallback((ev) => onChange(ev.target.value), [onChange]);
  return (
    <div className="p-2 pt-2 pb-4 border-b border-slate-600">
      <label className="uppercase text-xs text-slate-500 font-bold px-1">Environment</label>
      {environments === undefined ? (
        <p>Loading...</p>
      ) : !Object.keys(environments).length ? (
        <p>No environments</p>
      ) : (
        <select
          value={selectedName || ""}
          onChange={handleChange}
          className="text-slate-300 bg-slate-800/50 rounded p-2 w-full"
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
    <div className="flex h-screen">
      <div className="w-64 bg-slate-700 text-gray-100 shadow-inner flex flex-col">
        <EnvironmentSelector selectedName={environmentName} onChange={onEnvironmentChange} />
        <div className="flex-1 overflow-auto">
          {projectId && environmentName && (
            <Fragment>
              <TasksList projectId={projectId} environmentName={environmentName} taskId={taskId} />
              <SensorsList projectId={projectId} sensorId={sensorId} />
            </Fragment>
          )}
        </div>
        <div className="px-4 py-3 border-t border-slate-600">
          <div className="flex items-center">
            <span className={classNames("text-emerald-400 text-opacity-70 text-xs", statusIconClassName)}>
              {statusIcon}
            </span>
            <span className="ml-1 text-sm text-slate-200">{statusText}</span>
          </div>
        </div>
      </div>
      <div className="px-5 py-2 flex-1 overflow-auto">
        {children}
      </div>
    </div>
  );
}

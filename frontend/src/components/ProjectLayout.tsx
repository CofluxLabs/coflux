import React, { ReactNode } from 'react';
import classNames from 'classnames';

import useSocket from '../hooks/useSocket';
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

type Props = {
  projectId: string | null;
  taskId?: string | null;
  sensorId?: string | null;
  children: ReactNode;
}

export default function ProjectLayout({ projectId, taskId, sensorId, children }: Props) {
  const { status } = useSocket();
  const [statusIcon, statusIconClassName, statusText] = optionsForSocketStatus(status);
  return (
    <div className="flex h-screen">
      <div className="w-64 bg-slate-700 text-gray-100 shadow-inner flex flex-col">
        <div className="flex-1 overflow-auto">
          <TasksList projectId={projectId} taskId={taskId} />
          <SensorsList projectId={projectId} sensorId={sensorId} />
        </div>
        <div className="p-2 border-t border-slate-600">
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

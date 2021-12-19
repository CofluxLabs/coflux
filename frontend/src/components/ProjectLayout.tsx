import React, { ReactNode } from 'react';

import useSocket from '../hooks/useSocket';
import TasksList from './TasksList';
import SensorsList from './SensorsList';

type Props = {
  projectId: string | null;
  taskId?: string | null;
  sensorId?: string | null;
  children: ReactNode;
}

export default function ProjectLayout({ projectId, taskId, sensorId, children }: Props) {
  const { status } = useSocket();
  return (
    <div className="flex h-screen">
      <div className="w-64 bg-slate-700 text-gray-100 shadow-inner flex flex-col">
        <div className="flex-1 overflow-auto">
          <TasksList projectId={projectId} taskId={taskId} />
          <SensorsList projectId={projectId} sensorId={sensorId} />
        </div>
        <div className="p-2">
          {status}
        </div>
      </div>
      <div className="px-5 py-2 flex-1 overflow-auto">
        {children}
      </div>
    </div>
  );
}

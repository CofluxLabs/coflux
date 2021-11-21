import React, { ReactNode } from 'react';

import useSocket from '../hooks/useSocket';
import TasksList from './TasksList';

type Props = {
  projectId: string | null;
  taskId?: string | null;
  agentId?: string | null;
  children: ReactNode;
}

export default function ProjectLayout({ projectId, taskId, children }: Props) {
  const { status } = useSocket();
  return (
    <div className="flex h-screen">
      <div className="w-64 bg-gray-200 shadow-inner flex flex-col">
        <div className="flex-1 overflow-auto">
          <h2 className="font-bold uppercase text-gray-500 text-sm px-3 pt-7 pb-2">Tasks</h2>
          <TasksList projectId={projectId} taskId={taskId} />
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

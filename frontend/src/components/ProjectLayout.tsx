import React, { ReactNode } from 'react';

import TasksList from './TasksList';
import AgentsList from './AgentsList';

type Props = {
  projectId: string | null;
  taskId?: string | null;
  agentId?: string | null;
  children: ReactNode;
}

export default function ProjectLayout({ projectId, taskId, agentId, children }: Props) {
  return (
    <div className="flex h-screen overflow-auto">
      <div className="w-64 bg-gray-200 shadow-inner">
        <h2 className="font-bold uppercase text-gray-500 text-sm px-3 pt-7 pb-2">Tasks</h2>
        <TasksList projectId={projectId} taskId={taskId} />
        <h2 className="font-bold uppercase text-gray-500 text-sm px-3 pt-7 pb-2">Agents</h2>
        <AgentsList projectId={projectId} agentId={agentId} />
      </div>
      <div className="px-5 py-2 flex-1 overflow-auto">
        {children}
      </div>
    </div>
  );
}

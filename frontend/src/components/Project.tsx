import React, { ReactNode } from 'react';

import TasksList from './TasksList';
import AgentsList from './AgentsList';

type Props = {
  projectId: string | null;
  children: ReactNode;
}

export default function Project({ projectId, children }: Props) {
  return (
    <div className="flex h-screen overflow-auto">
      <div className="w-64 bg-gray-200">
        <h2 className="font-bold uppercase text-gray-500 text-sm px-3 pt-7 pb-2">Tasks</h2>
        <TasksList projectId={projectId} />
        <h2 className="font-bold uppercase text-gray-500 text-sm px-3 pt-7 pb-2">Agents</h2>
        <AgentsList projectId={projectId} />
      </div>
      <div className="px-5 py-2 flex-1 overflow-auto">
        {children}
      </div>
    </div>
  );
}

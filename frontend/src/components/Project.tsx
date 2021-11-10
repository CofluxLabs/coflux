import React, { ReactNode } from 'react';

import TasksList from './TasksList';

type Props = {
  projectId: string | null;
  children: ReactNode;
}

export default function Project({ projectId, children }: Props) {
  return (
    <div className="flex h-screen">
      <div className="w-64 bg-gray-200">
        <TasksList projectId={projectId} />
      </div>
      <div className="px-5 py-2 flex-1 overflow-auto">
        {children}
      </div>
    </div>
  );
}

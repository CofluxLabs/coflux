import React from 'react';
import Link from 'next/link';
import classNames from 'classnames';
import { sortBy } from 'lodash';

import * as models from '../models';
import { useSubscription } from '../hooks/useSocket';

type TaskItemProps = {
  task: models.Task;
  agents: models.Agent[] | undefined;
  isActive: boolean;
}

export function TaskItem({ task, agents, isActive }: TaskItemProps) {
  const taskAgents = agents?.filter((a) => a.targets.some((t) => t.repository == task.repository && t.target == task.target));
  const agentsCount = taskAgents?.length;
  return (
    <div className="flex items-center">
      <div className="flex-1">
        <div className={classNames('font-mono', {'font-bold': isActive})}>{task.target}</div>
        <div className="text-sm text-gray-500">{task.repository}</div>
      </div>
      {agentsCount ? (
        <span className="text-green-400" title={`Running on ${agentsCount} agent(s)`}>●</span>
      ) : (
        <span className="text-gray-400" title="Not running">○</span>
      )}
    </div>
  )
}

type Props = {
  projectId: string | null;
  taskId?: string | null;
}

export default function TasksList({ projectId, taskId: activeTaskId }: Props) {
  const tasks = useSubscription<models.Task[]>('tasks');
  const agents: models.Agent[] = []; // TODO
  if (tasks === undefined) {
    return <div>Loading...</div>;
  } else {
    return (
      <div>
        {Object.keys(tasks).length ? (
          <ul>
            {sortBy(Object.values(tasks), 'target').map((task) => {
              const taskId = `${task.repository}:${task.target}`;
              return (
                <li key={taskId}>
                  <Link href={`/projects/${projectId}/tasks/${taskId}`}>
                    <a className={classNames('block hover:bg-gray-300 px-4 py-2', { 'bg-gray-300': taskId == activeTaskId })}>
                      <TaskItem task={task} agents={agents} isActive={taskId == activeTaskId} />
                    </a>
                  </Link>
                </li>
              );
            })}
          </ul>
        ) : (
          <p>No tasks</p>
        )}
      </div>
    );
  }
}

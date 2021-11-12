import React from 'react';
import Link from 'next/link';

import * as models from '../models';
import useTasks from '../hooks/useTasks';
import useAgents from '../hooks/useAgents';

type TaskItemProps = {
  task: models.Task;
  agents: models.Agent[] | undefined;
}

export function TaskItem({ task, agents }: TaskItemProps) {
  const taskAgents = agents?.filter((a) => a.targets.some((t) => t.repository == task.repository && t.target == task.target));
  const agentsCount = taskAgents?.length;
  return (
    <div className="flex items-center">
      <div className="flex-1">
        <div className="font-mono">{task.target}</div>
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
}

export default function TasksList({ projectId }: Props) {
  const { tasks, error: tasksError } = useTasks(projectId);
  const { agents, error: agentsError } = useAgents(projectId);
  if (tasksError || agentsError) {
    return <div>Error</div>
  } else if (!tasks) {
    return <div>Loading...</div>;
  } else {
    return (
      <div>
        {tasks.length ? (
          <ul>
            {tasks.map((task) => (
              <li key={task.id} className="">
                <Link href={`/projects/${projectId}/tasks/${task.id}`}>
                  <a className="block hover:bg-gray-300 px-4 py-2">
                    <TaskItem task={task} agents={agents} />
                  </a>
                </Link>
              </li>
            ))}
          </ul>
        ) : (
          <p>No tasks</p>
        )}
      </div>
    );
  }
}

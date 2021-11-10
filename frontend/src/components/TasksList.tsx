import React from 'react';
import Link from 'next/link';

import useTasks from '../hooks/useTasks';

type Props = {
  projectId: string | null;
}

export default function TasksList({ projectId }: Props) {
  const { tasks, error } = useTasks(projectId);
  if (error) {
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
                  <a className="block hover:bg-gray-300 px-3 py-2">
                    <div className="font-mono">{task.target}</div>
                    <div className="text-sm text-gray-500">{task.repository}</div>
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

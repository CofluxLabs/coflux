import React, { ReactNode } from 'react';
import Link from 'next/link';
import classNames from 'classnames';

import * as models from '../models';
import useRun from '../hooks/useRun';
import useTask from '../hooks/useTask';
import Heading from './Heading';

type TabProps = {
  href: string;
  title: string;
  isActive: boolean;
}

function Tab({ title, href, isActive }: TabProps) {
  return (
    <Link href={href}>
      <a className={classNames('mr-2 px-3 py-2 rounded-md', isActive ? 'bg-gray-200' : 'bg-gray-100')}>{title}</a>
    </Link>
  );
}

type Props = {
  projectId: string | null;
  taskId: string | null;
  runId: string | null;
  activeTab: 'overview' | 'timeline';
  children: (run: models.Run) => ReactNode;
}

export default function RunDetail({ projectId, taskId, runId, activeTab, children }: Props) {
  const { task, error: taskError } = useTask(projectId, taskId);
  const { run, error: runError } = useRun(projectId, runId);
  if (taskError || runError) {
    return <div>Error</div>;
  } else if (!task || !run) {
    return <div>Loading...</div>;
  } else {
    return (
      <div>
        <Heading>
          <Link href={`/projects/${projectId}/tasks/${taskId}`}>
            <a><span className="font-mono">{task.target}</span> <span className="text-gray-500">({task.repository})</span></a>
          </Link>
          <span className="mx-3">&rarr;</span>
          <span className="font-mono">{runId}</span>
        </Heading>
        <div className="my-6">
          <Tab title="Overview" href={`/projects/${projectId}/tasks/${taskId}/runs/${runId}`} isActive={activeTab == 'overview'} />
          <Tab title="Timeline" href={`/projects/${projectId}/tasks/${taskId}/runs/${runId}/timeline`} isActive={activeTab == 'timeline'} />
        </div>
        {children(run)}
      </div>
    );
  }
}


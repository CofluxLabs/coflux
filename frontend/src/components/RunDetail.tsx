import React, { ReactNode } from 'react';
import Link from 'next/link';
import classNames from 'classnames';

import * as models from '../models';
import useRun from '../hooks/useRun';
import Heading from './Heading';
import ProjectLayout from './ProjectLayout';

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
  runId: string | null;
  activeTab: 'overview' | 'timeline';
  children: (run: models.Run) => ReactNode;
}

export default function RunDetail({ projectId, runId, activeTab, children }: Props) {
  const { run, error } = useRun(projectId, runId);
  if (error) {
    return <div>Error</div>;
  } else if (!run) {
    return <div>Loading...</div>;
  } else {
    return (
      <ProjectLayout projectId={projectId} taskId={run.task.id}>
        <Heading>
          <Link href={`/projects/${projectId}/tasks/${run.task.id}`}>
            <a><span className="font-mono">{run.task.target}</span> <span className="text-gray-500">({run.task.repository})</span></a>
          </Link>
          <span className="mx-3">&rarr;</span>
          <span className="font-mono">{runId}</span>
        </Heading>
        <div className="my-6">
          <Tab title="Overview" href={`/projects/${projectId}/runs/${runId}`} isActive={activeTab == 'overview'} />
          <Tab title="Timeline" href={`/projects/${projectId}/runs/${runId}/timeline`} isActive={activeTab == 'timeline'} />
        </div>
        {children(run)}
      </ProjectLayout>
    );
  }
}


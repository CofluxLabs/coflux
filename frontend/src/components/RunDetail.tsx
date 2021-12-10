import React, { Fragment, ReactNode } from 'react';
import Link from 'next/link';
import classNames from 'classnames';
import { Transition } from '@headlessui/react';

import * as models from '../models';
import Heading from './Heading';
import ProjectLayout from './ProjectLayout';
import StepPanel from './StepPanel';
import { useSubscription } from '../hooks/useSocket';
import usePrevious from '../hooks/usePrevious';

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

type DetailPanelProps = {
  step: models.Step | null;
}

function DetailPanel({ step }: DetailPanelProps) {
  const previousStep = usePrevious(step);
  const stepOrPrevious = step || previousStep;
  return (
    <Transition
      as={Fragment}
      show={!!step}
      enter="transform transition ease-in-out duration-150"
      enterFrom="translate-x-full"
      enterTo="translate-x-0"
      leave="transform transition ease-in-out duration-300"
      leaveFrom="translate-x-0"
      leaveTo="translate-x-full"
    >
      <div className="fixed inset-y-0 right-0 w-1/4 bg-gray-50 shadow-xl border-l border-gray-200 h-screen">
        {stepOrPrevious && (
          <StepPanel step={stepOrPrevious} />
        )}
      </div>
    </Transition>
  );
}

type Props = {
  projectId: string | null;
  runId: string | null;
  activeTab: 'overview' | 'timeline';
  activeStepId: string | null;
  children: (run: models.Run) => ReactNode;
}

export default function RunDetail({ projectId, runId, activeTab, activeStepId, children }: Props) {
  const run = useSubscription<models.Run>(`runs.${runId}`);
  const initialStep = run && Object.values(run.steps).find((s) => !s.parent);
  const taskId = initialStep && `${initialStep.repository}:${initialStep.target}`;
  return (
    <ProjectLayout projectId={projectId} taskId={taskId}>
      {run && initialStep ? (
        <Fragment>
          <Heading>
            <Link href={`/projects/${projectId}/tasks/${taskId}`}>
              <a><span className="font-mono">{initialStep.target}</span> <span className="text-gray-500">({initialStep.repository})</span></a>
            </Link>
            <span className="mx-3">&rarr;</span>
            <span className="font-mono">{runId}</span>
          </Heading>
          <div className="my-6">
            <Tab title="Overview" href={`/projects/${projectId}/runs/${runId}`} isActive={activeTab == 'overview'} />
            <Tab title="Timeline" href={`/projects/${projectId}/runs/${runId}/timeline`} isActive={activeTab == 'timeline'} />
          </div>
          {children(run)}
          <DetailPanel step={activeStepId ? run.steps[activeStepId] : null} />
        </Fragment>
      ) : (
        <p>Loading...</p>
      )}
    </ProjectLayout>
  );
}

import React, { Fragment, ReactNode, useCallback, useState } from 'react';
import Link from 'next/link';
import classNames from 'classnames';
import { Dialog, Transition } from '@headlessui/react';

import * as models from '../models';
import Heading from './Heading';
import ProjectLayout from './ProjectLayout';
import StepDetail from './StepDetail';
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
  stepId: string | null;
  attemptNumber: number | null;
  run: models.Run;
  projectId: string;
  environmentName: string | null;
  onFrameUrlChange: (url: string | undefined) => void;
}

function DetailPanel({ stepId, attemptNumber, run, projectId, environmentName, onFrameUrlChange }: DetailPanelProps) {
  const step = stepId && run.steps[stepId];
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
      <div className="fixed inset-y-0 right-0 w-1/3 bg-slate-100 shadow-xl border-l border-slate-200 h-screen flex">
        {stepOrPrevious && (
          <StepDetail
            step={stepOrPrevious}
            attemptNumber={attemptNumber || 1}
            run={run}
            projectId={projectId}
            environmentName={run.environment.name}
            className="flex-1"
            onFrameUrlChange={onFrameUrlChange}
          />
        )}
      </div>
    </Transition>
  );
}

type FrameProps = {
  url: string | undefined;
  onUrlChange: (url: string | undefined) => void;
}

function Frame({ url, onUrlChange }: FrameProps) {
  return (
    <Dialog
      open={!!url}
      onClose={() => onUrlChange(undefined)}
      className="fixed z-10 inset-0 overflow-y-auto"
    >
      <div className="flex min-h-screen">
        <Dialog.Overlay className="fixed inset-0 bg-black opacity-70" />
        <iframe className="relative m-8 bg-white rounded w-full" src={url} />
      </div>
    </Dialog>
  );
}

type Props = {
  projectId: string | null;
  runId: string | null;
  environmentName: string | null;
  activeTab: 'overview' | 'timeline' | 'logs';
  activeStepId: string | null;
  activeAttemptNumber: number | null;
  children: (run: models.Run) => ReactNode;
  onEnvironmentChange: (environmentName: string) => void;
}

export default function RunDetail({ projectId, runId, environmentName, activeTab, activeStepId, activeAttemptNumber, children, onEnvironmentChange }: Props) {
  const run = useSubscription<models.Run>('run', runId);
  const [frameUrl, setFrameUrl] = useState<string>();
  const initialStep = run && Object.values(run.steps).find((s) => !s.parent);
  const taskId = initialStep && `${initialStep.repository}:${initialStep.target}`;
  const buildUrl = useCallback(
    (page: string | null = null) => `/projects/${projectId}/runs/${runId}${page ? '/' + page : ''}${environmentName ? `?environment=${environmentName}` : ''}${activeStepId ? '#' + activeStepId + (activeAttemptNumber ? '/' + activeAttemptNumber : '') : ''}`,
    [projectId, runId, environmentName, activeStepId, activeAttemptNumber]);
  const handleEnvironmentChange = useCallback((environmentName) => {
    const name = (run && run.environment.name != environmentName) ? environmentName : null;
    onEnvironmentChange(name);
  }, [run, onEnvironmentChange]);
  return (
    <ProjectLayout projectId={projectId} environmentName={environmentName || run && run.environment.name} taskId={taskId} onEnvironmentChange={handleEnvironmentChange}>
      {(run === undefined || initialStep === undefined) ? (
        <p>Loading...</p>
      ) : (run === null || initialStep === null) ? (
        <p>Not found</p>
      ) : (
        <Fragment>
          <Heading>
            <Link href={`/projects/${projectId}/tasks/${taskId}`}>
              <a><span className="font-mono">{initialStep.target}</span> <span className="text-gray-500">({initialStep.repository})</span></a>
            </Link>
            <span className="mx-3">&rarr;</span>
            <span className="font-mono">{runId}</span>
            {environmentName && environmentName != run.environment.name && (
              <span className="rounded bg-gray-300 text-sm px-1 py-0.5 ml-2">{run.environment.name}</span>
            )}
          </Heading>
          <div className="my-6">
            <Tab title="Overview" href={buildUrl()} isActive={activeTab == 'overview'} />
            <Tab title="Timeline" href={buildUrl('timeline')} isActive={activeTab == 'timeline'} />
            <Tab title="Logs" href={buildUrl('logs')} isActive={activeTab == 'logs'} />
          </div>
          {children(run)}
          <DetailPanel
            stepId={activeStepId}
            attemptNumber={activeAttemptNumber}
            run={run}
            projectId={projectId!}
            environmentName={environmentName}
            onFrameUrlChange={setFrameUrl}
          />
          <Frame url={frameUrl} onUrlChange={setFrameUrl} />
        </Fragment>

      )}
    </ProjectLayout>
  );
}

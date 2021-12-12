import React, { CSSProperties, Fragment, ReactNode, useCallback } from 'react';
import classNames from 'classnames';
import { findKey, sortBy } from 'lodash';
import { DateTime } from 'luxon';
import Link from 'next/link';
import { Listbox, Transition } from '@headlessui/react';

import * as models from '../models';
import Badge from './Badge';

function findStepForExecution(run: models.Run, executionId: string) {
  return findKey(run.steps, (s) => Object.values(s.attempts).some((a) => a.executionId == executionId));
}

type ResultProps = {
  result: models.Result;
  run: models.Run;
  projectId: string;
  onFrameUrlChange: (url: string | undefined) => void;
}

function Result({ result, run, projectId, onFrameUrlChange }: ResultProps) {
  const handleBlobClick = useCallback((ev) => {
    if (!ev.ctrlKey) {
      ev.preventDefault();
      onFrameUrlChange(ev.target.href);
    }
  }, [onFrameUrlChange]);
  switch (result.type) {
    case 0:
      return (
        <div className="font-mono p-2 mt-2 rounded bg-white border border-gray-200">
          {result.value}
        </div>
      );
    case 1:
      return (
        <a
          href={`http://localhost:7070/projects/${projectId}/blobs/${result.value}`}
          className="border border-blue-500 hover:bg-blue-50 text-blue-500 rounded px-2 py-1 my-2 inline-block"
          onClick={handleBlobClick}
        >
          Blob
        </a>
      );
    case 2:
      const stepId = findStepForExecution(run, result.value);
      if (stepId) {
        return (
          <Link href={`/projects/${projectId}/runs/${run.id}#${stepId}`}>
            <a className="border border-blue-500 hover:bg-blue-50 text-blue-500 rounded px-2 py-1 my-2 inline-block">
              Result
            </a>
          </Link>
        );
      } else {
        return <em>Unrecognised execution</em>
      }
    case 3:
      return (
        <div className="font-mono p-2 mt-2 rounded bg-red-50 border border-red-200">
          {result.value}
        </div>
      );
    default:
      return null;
  }
}

type AttemptProps = {
  attempt: models.Attempt;
  run: models.Run;
  projectId: string;
  onFrameUrlChange: (url: string | undefined) => void;
}

function Attempt({ attempt, run, projectId, onFrameUrlChange }: AttemptProps) {
  const scheduledAt = DateTime.fromISO(attempt.createdAt);
  const assignedAt = attempt.assignedAt ? DateTime.fromISO(attempt.assignedAt) : null;
  const resultAt = attempt.result && DateTime.fromISO(attempt.result.createdAt);
  return (
    <Fragment>
      <div className="p-4">
        <h3 className="uppercase text-sm font-bold text-gray-400">Execution</h3>
        <p>Started: {scheduledAt.toLocaleString(DateTime.DATETIME_FULL_WITH_SECONDS)}</p>
        {resultAt ? (
          <p>Duration: {resultAt.diff(assignedAt!).toMillis()}ms <span className="text-gray-500 text-sm">(+{assignedAt!.diff(scheduledAt).toMillis()}ms wait)</span></p>
        ) : assignedAt ? (
          <p>Executing...</p>
        ) : null}
      </div>
      {attempt.result && (
        <div className="p-4">
          <h3 className="uppercase text-sm font-bold text-gray-400">Result</h3>
          <Result result={attempt.result} run={run} projectId={projectId} onFrameUrlChange={onFrameUrlChange} />
        </div>
      )}
    </Fragment>
  );
}

type AttemptSelectorProps = {
  selectedNumber: number;
  attempts: Record<number, models.Attempt>;
  onChange: (number: number) => void;
  children: (attempt: models.Attempt, selected: boolean, active: boolean) => ReactNode;
}

function AttemptSelector({ selectedNumber, attempts, onChange, children }: AttemptSelectorProps) {
  const selectedAttempt = attempts[selectedNumber];
  return (
    <Listbox value={selectedNumber} onChange={onChange}>
      <div className="relative mt-1">
        <Listbox.Button className="relative w-full p-2 bg-white text-left border rounded-lg">
          {children(selectedAttempt, true, false)}
        </Listbox.Button>
        <Transition
          as={Fragment}
          leave="transition ease-in duration-100"
          leaveFrom="opacity-100"
          leaveTo="opacity-0"
        >
          <Listbox.Options className="absolute right-0 py-1 mt-1 overflow-auto text-base bg-white rounded-md shadow-lg max-h-60">
            {sortBy(Object.values(attempts), 'number').map((attempt) => (
              <Listbox.Option
                key={attempt.number}
                className="relative cursor-default"
                value={attempt.number}
              >
                {({ selected, active }) => (
                  <div className={classNames('p-2', selected && 'font-bold', active && 'bg-gray-100')}>
                    {children(attempt, selected, active)}
                  </div>
                )}
              </Listbox.Option>
            ))}
          </Listbox.Options>
        </Transition>
      </div>
    </Listbox>
  );
}

type Props = {
  step: models.Step;
  attemptNumber: number;
  run: models.Run;
  projectId: string;
  className?: string;
  style?: CSSProperties;
  onFrameUrlChange: (url: string | undefined) => void;
}

export default function StepDetail({ step, attemptNumber, run, projectId, className, style, onFrameUrlChange }: Props) {
  const handleAttemptChange = useCallback((number) => { window.location.hash = `#${step.id}/${number}`; }, [step]);
  const attempt = step.attempts[attemptNumber];
  return (
    <div className={classNames('divide-y overflow-hidden', className)} style={style}>
      <div className="p-4 pt-5 flex items-center">
        <h2 className="flex-1"><span className="font-mono text-xl">{step.target}</span> <span className="text-gray-500">({step.repository})</span></h2>
        {step.cached ? (
          <Badge intent="none" label="Cached" />
        ) : !Object.keys(step.attempts).length ? (
          <Badge intent="info" label="Scheduling" />
        ) : (
          <AttemptSelector selectedNumber={attemptNumber} attempts={step.attempts} onChange={handleAttemptChange}>
            {(attempt) => (
              <div className="flex items-center">
                <span className="mr-1 flex-1">
                  #{attempt.number}
                </span>
                {!attempt.assignedAt ? (
                  <Badge intent="info" label="Assigning" />
                ) : !attempt.result ? (
                  <Badge intent="info" label="Running" />
                ) : attempt.result.type <= 2 ? (
                  <Badge intent="success" label="Completed" />
                ) : attempt.result.type == 3 ? (
                  <Badge intent="danger" label="Failed" />
                ) : attempt.result.type == 4 ? (
                  <Badge intent="warning" label="Abandoned" />
                ) : null}
              </div>
            )}
          </AttemptSelector>
        )}
      </div>
      {step.arguments.length > 0 && (
        <div className="p-4">
          <h3 className="uppercase text-sm font-bold text-gray-400">Arguments</h3>
          <ol className="list-disc list-inside ml-1">
            {step.arguments.map((argument, index) => (
              <li key={index}><span className="font-mono truncate">{argument}</span></li>
            ))}
          </ol>
        </div>
      )}
      {attempt && (
        <Attempt
          key={attempt.number}
          attempt={attempt}
          run={run}
          projectId={projectId}
          onFrameUrlChange={onFrameUrlChange}
        />
      )}
    </div>
  );
}
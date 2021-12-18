import React, { CSSProperties, Fragment, ReactNode, useCallback, useState } from 'react';
import classNames from 'classnames';
import { filter, findKey, sortBy } from 'lodash';
import { DateTime } from 'luxon';
import Link from 'next/link';
import { Listbox, Transition } from '@headlessui/react';

import * as models from '../models';
import Badge from './Badge';
import useSocket, { useSubscription } from '../hooks/useSocket';

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
          className="border border-blue-300 hover:border-blue-600 text-blue-600 text-sm rounded px-2 py-1 my-2 inline-block"
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
            <a className="border border-blue-300 hover:border-blue-600 text-blue-600 text-sm rounded px-2 py-1 my-2 inline-block">
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

type LogMessageProps = {
  message: models.LogMessage;
}

const LOG_LEVELS = {
  0: ['Debug', 'bg-gray-400'],
  1: ['Info', 'bg-blue-400'],
  2: ['Warning', 'bg-yellow-500'],
  3: ['Error', 'bg-red-600']
}

function LogMessage({ message }: LogMessageProps) {
  const [name, className] = LOG_LEVELS[message.level];
  return (
    <div className="my-2">
      <div className="my-1">
        <span className={classNames('rounded p-1 text-xs uppercase text-white mr-1 font-bold', className)}>{name}</span>
      </div>
      <div className="my-1">
        {message.message}
      </div>
      <div className="text-xs text-gray-500 my-1">{message.createdAt}</div>
    </div>
  );
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
  const logs = useSubscription<Record<string, models.LogMessage>>(`logs.${run.id}`);
  const attemptLogs = logs && attempt.executionId !== null && filter(logs, {executionId: attempt.executionId});
  return (
    <Fragment>
      <div className="p-4">
        <h3 className="uppercase text-sm font-bold text-gray-400">Execution</h3>
        <p>Started: {scheduledAt.toLocaleString(DateTime.DATETIME_FULL_WITH_SECONDS)}</p>
        {assignedAt && resultAt ? (
          <p>Duration: {resultAt.diff(assignedAt).toMillis()}ms <span className="text-gray-500 text-sm">(+{assignedAt!.diff(scheduledAt).toMillis()}ms wait)</span></p>
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
      <div className="p-4">
        <h3 className="uppercase text-sm font-bold text-gray-400">Logs</h3>
        {attemptLogs === undefined ? (
          <p><em>Loading...</em></p>
        ) : Object.keys(attemptLogs).length == 0 ? (
          <p><em>None</em></p>
        ) : (
          <ol>
            {sortBy(Object.values(attemptLogs), 'createdAt').map((message, index) => (
              <li key={index}>
                <LogMessage message={message} />
              </li>
            ))}
          </ol>
        )}
      </div>
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
      <div className="relative">
        <Listbox.Button className="relative w-full p-1 pl-2 bg-white text-left border border-blue-300 text-blue-600 hover:border-blue-600 rounded">
          {selectedAttempt && children(selectedAttempt, true, false)}
        </Listbox.Button>
        <Transition
          as={Fragment}
          leave="transition ease-in duration-100"
          leaveFrom="opacity-100"
          leaveTo="opacity-0"
        >
          <Listbox.Options className="absolute right-0 py-1 mt-1 overflow-auto text-base bg-white rounded shadow-lg max-h-60">
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
  const { socket } = useSocket();
  const [rerunning, setRerunning] = useState(false);
  const handleAttemptChange = useCallback((number) => { window.location.hash = `#${step.id}/${number}`; }, [step]);
  const handleRetryClick = useCallback(() => {
    setRerunning(true);
    socket?.request('rerun_step', [run.id, step.id], (attempt) => {
      setRerunning(false);
      handleAttemptChange(attempt);
    });
  }, [socket, run, step, handleAttemptChange]);
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
          <div className="flex">
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
            <button
              className={classNames('ml-1 rounded border border-blue-300 text-blue-600 bg-white hover:border-blue-600 px-2 py-1 text-sm', rerunning && 'text-gray-500')}
              disabled={rerunning}
              onClick={handleRetryClick}
            >
              Retry
            </button>
          </div>
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
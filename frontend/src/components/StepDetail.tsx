import React, { CSSProperties, useCallback } from 'react';
import classNames from 'classnames';
import { findKey, maxBy, sortBy } from 'lodash';
import { DateTime } from 'luxon';

import * as models from '../models';
import Badge from './Badge';
import Link from 'next/link';

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
    <div key={attempt.number} className="p-4">
      <h3 className="text-sm flex mb-2">
        <span className="uppercase font-bold text-gray-400 flex-1">
          Attempt {attempt.number}
        </span>
        <span className="ml-2 text-gray-400">
          {scheduledAt.toLocaleString(DateTime.DATETIME_FULL_WITH_SECONDS)}
        </span>
      </h3>
      {resultAt ? (
        <p>Duration: {resultAt.diff(assignedAt!).toMillis()}ms <span className="text-gray-500 text-sm">(+{assignedAt!.diff(scheduledAt).toMillis()}ms wait)</span></p>
      ) : assignedAt ? (
        <p>Executing...</p>
      ) : null}
      {attempt.result && (
        <Result result={attempt.result} run={run} projectId={projectId} onFrameUrlChange={onFrameUrlChange} />
      )}
    </div>
  );
}

type Props = {
  step: models.Step;
  run: models.Run;
  projectId: string;
  className?: string;
  style?: CSSProperties;
  onFrameUrlChange: (url: string | undefined) => void;
}

export default function StepDetail({ step, run, projectId, className, style, onFrameUrlChange }: Props) {
  const latestAttempt = maxBy(Object.values(step.attempts), 'number')
  return (
    <div className={classNames('divide-y overflow-hidden', className)} style={style}>
      <div className="p-4 pt-5 flex items-center">
        <h2 className="flex-1"><span className="font-mono text-xl">{step.target}</span> <span className="text-gray-500">({step.repository})</span></h2>
        {step.cached ? (
          <Badge intent="none" label="Cached" />
        ) : !latestAttempt ? (
          <Badge intent="info" label="Scheduling" />
        ) : !latestAttempt.assignedAt ? (
          <Badge intent="info" label="Assigning" />
        ) : !latestAttempt.result ? (
          <Badge intent="info" label="Running" />
        ) : latestAttempt.result.type <= 2 ? (
          <Badge intent="success" label="Completed" />
        ) : latestAttempt.result.type == 3 ? (
          <Badge intent="danger" label="Failed" />
        ) : latestAttempt.result.type == 4 ? (
          <Badge intent="warning" label="Abandoned" />
        ) : null}
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
      {sortBy(Object.values(step.attempts), 'number').map((attempt) => (
        <Attempt
          key={attempt.number}
          attempt={attempt}
          run={run}
          projectId={projectId}
          onFrameUrlChange={onFrameUrlChange}
        />
      ))}
    </div>
  );
}
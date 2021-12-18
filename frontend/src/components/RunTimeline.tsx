import { DateTime } from 'luxon';
import React, { Fragment } from 'react';
import classNames from 'classnames';
import { maxBy, sortBy } from 'lodash';
import Link from 'next/link';

import * as models from '../models';
import useNow from '../hooks/useNow';

function loadExecutionTimes(run: models.Run): { [key: string]: [DateTime, DateTime | null, DateTime | null] } {
  return Object.values(run.steps).reduce((times, step) => {
    return Object.values(step.attempts).reduce((times, attempt) => {
      return {
        ...times, [`${step.id}:${attempt.number}`]: [
          DateTime.fromISO(attempt.createdAt),
          attempt.assignedAt ? DateTime.fromISO(attempt.assignedAt) : null,
          attempt.result ? DateTime.fromISO(attempt.result.createdAt) : null
        ]
      };
    }, times);
  }, {});
}

function loadStepTimes(run: models.Run): { [key: string]: DateTime } {
  return Object.values(run.steps).reduce((times, step) => ({ ...times, [step.id]: DateTime.fromISO(step.createdAt) }), {});
}

function percentage(value: number) {
  return `${(value * 100).toFixed(2)}%`;
}

type BarProps = {
  x0: DateTime;
  x1: DateTime;
  x2: DateTime;
  d: number;
  className: string;
}

function Bar({ x1, x2, x0, d, className }: BarProps) {
  const left = x1.diff(x0).toMillis() / d;
  const width = Math.max(0.001, x2.diff(x1).toMillis() / d);
  const style = { left: percentage(left), width: percentage(width) };
  return (
    <div className={classNames('absolute h-6 rounded', className)} style={style}></div>
  );
}

function classNameForResult(result: models.Result | null) {
  if (!result) {
    return 'bg-blue-300';
  } else if (result.type <= 2) {
    return 'bg-green-300';
  } else if (result.type == 3) {
    return 'bg-red-300';
  } else {
    return 'bg-yellow-300';
  }
}

function isRunning(run: models.Run) {
  return Object.values(run.steps).some((step) => Object.values(step.attempts).some((a) => !a.result));
}

function formatElapsed(millis: number) {
  if (millis < 500) {
    return `${millis}ms`;
  } else {
    return `${(millis / 1000).toFixed(1)}s`;
  }
}

function buildUrl(runId: string, stepId: string | null, attempt: number | undefined) {
  return `/projects/project_1/runs/${runId}/timeline${stepId ? `#${stepId}${attempt ? `/${attempt}` : ''}` : ''}`;
}

type Props = {
  run: models.Run;
  activeStepId: string | null;
}

export default function RunTimeline({ run, activeStepId }: Props) {
  const running = isRunning(run);
  const now = useNow(running ? 100 : 0);
  const stepTimes = loadStepTimes(run);
  const executionTimes = loadExecutionTimes(run);
  const times = [...(Object.values(stepTimes)), ...(Object.values(executionTimes).flat().filter((t): t is DateTime => t !== null))];
  const earliestTime = DateTime.min(...times);
  const latestTime = running ? DateTime.fromJSDate(now) : DateTime.max(...times);
  const totalMillis = latestTime.diff(earliestTime).toMillis();
  const steps = sortBy(Object.values(run.steps).filter(s => !s.cached), 'createdAt');
  return (
    <div className="relative divide-y divide-gray-200">
      <div className="flex">
        <div className="w-40 truncate self-center mr-2">
        </div>
        <div className="flex-1 text-right">
          {formatElapsed(totalMillis)}
        </div>
      </div>
      {steps.map((step) => {
        const latestAttempt = maxBy(Object.values(step.attempts), 'number');
        const stepFinishedAt = (latestAttempt ? executionTimes[`${step.id}:${latestAttempt.number}`][2] : null) || latestTime;
        const isActive = step.id == activeStepId;
        return (
          <div key={step.id} className={classNames('flex rounded px-2', isActive && 'ring ring-offset-2')}>
            <div className="w-40 truncate self-center mr-2">
              <Link href={buildUrl(run.id, isActive ? null : step.id, latestAttempt?.number)}>
                <a>
                  <span className="font-mono">{step.target}</span> <span className="text-gray-500 text-sm">({step.repository})</span>
                </a>
              </Link>
            </div>
            <div className="flex-1 my-2 relative h-6">
              <Link href={buildUrl(run.id, isActive ? null : step.id, latestAttempt?.number)}>
                <a>
                  <Bar x1={stepTimes[step.id]} x2={stepFinishedAt} x0={earliestTime} d={totalMillis} className="bg-gray-100" />
                  {Object.values(step.attempts).map((attempt) => {
                    const [createdAt, assignedAt, resultAt] = executionTimes[`${step.id}:${attempt.number}`];
                    return (
                      <Fragment key={attempt.number}>
                        <Bar x1={createdAt} x2={stepFinishedAt} x0={earliestTime} d={totalMillis} className="bg-gray-200" />
                        {assignedAt && <Bar x1={assignedAt} x2={resultAt || latestTime} x0={earliestTime} d={totalMillis} className={classNameForResult(attempt.result)} />}
                      </Fragment>
                    );
                  })}
                </a>
              </Link>
            </div>
          </div>
        );
      })}
    </div>
  );
}

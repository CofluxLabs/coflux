import { DateTime } from 'luxon';
import React, { Fragment } from 'react';
import classNames from 'classnames';
import { maxBy, sortBy } from 'lodash';

import * as models from '../models';

function loadExecutionTimes(run: models.Run): { [key: string]: [DateTime, DateTime | null, DateTime | null] } {
  return Object.values(run.steps).reduce((times, step) => {
    return Object.values(step.executions).reduce((times, execution) => {
      return {
        ...times, [execution.id]: [
          DateTime.fromISO(execution.createdAt),
          execution.assignedAt ? DateTime.fromISO(execution.assignedAt) : null,
          execution.result ? DateTime.fromISO(execution.result.createdAt) : null
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
  const width = x2.diff(x1).toMillis() / d;
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

type Props = {
  run: models.Run;
}

export default function RunTimeline({ run }: Props) {
  const stepTimes = loadStepTimes(run);
  const executionTimes = loadExecutionTimes(run);
  const times = [...(Object.values(stepTimes)), ...(Object.values(executionTimes).flat().filter((t): t is DateTime => t !== null))];
  const earliestTime = DateTime.min(...times);
  const latestTime = DateTime.max(...times);
  const totalMillis = latestTime.diff(earliestTime).toMillis();
  const steps = sortBy(Object.values(run.steps).filter(s => !s.cachedId), 'createdAt');
  return (
    <div className="relative divide-y divide-gray-200">
      {steps.map((step) => {
        const latestExecution = maxBy(Object.values(step.executions), 'attempt');
        const stepFinishedAt = (latestExecution ? executionTimes[latestExecution.id][2] : null) || latestTime;
        return (
          <div key={step.id} className="flex">
            <div className="w-40 truncate self-center mr-2">
              {step.target} <span className="text-gray-500 text-sm">({step.repository})</span>
            </div>
            <div className="flex-1 my-2 relative h-6">
              <Bar x1={stepTimes[step.id]} x2={stepFinishedAt} x0={earliestTime} d={totalMillis} className="bg-gray-100" />
              {Object.values(step.executions).map((execution) => {
                const [createdAt, assignedAt, resultAt] = executionTimes[execution.id];
                return (
                  <Fragment key={execution.id}>
                    <Bar x1={createdAt} x2={stepFinishedAt} x0={earliestTime} d={totalMillis} className="bg-gray-200" />
                    {assignedAt && <Bar x1={assignedAt} x2={resultAt || latestTime} x0={earliestTime} d={totalMillis} className={classNameForResult(execution.result)} />}
                  </Fragment>
                );
              })}
            </div>
          </div>
        );
      })}
    </div>
  );
}

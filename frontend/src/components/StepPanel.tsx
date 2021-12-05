import React, { CSSProperties, Fragment } from 'react';
import classNames from 'classnames';
import { maxBy, sortBy } from 'lodash';
import { DateTime } from 'luxon';

import * as models from '../models';
import Badge from './Badge';

type AttemptProps = {
  attempt: models.Attempt;
}

function Attempt({ attempt }: AttemptProps) {
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
        attempt.result.type <= 2 ? (
          <div className="font-mono p-2 mt-2 rounded bg-white border border-gray-200">
            {attempt.result.value}
          </div>
        ) : attempt.result.type == 3 ? (
          <div className="font-mono p-2 mt-2 rounded bg-red-50 border border-red-200">
            {attempt.result.value}
          </div>
        ) : null
      )}
    </div>
  );
}

type Props = {
  step: models.Step;
  className?: string;
  style?: CSSProperties;
}

export default function StepPanel({ step, className, style }: Props) {
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
        <Attempt key={attempt.number} attempt={attempt} />
      ))}
    </div>
  );
}
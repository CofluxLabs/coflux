import React, { CSSProperties, Fragment } from 'react';
import classNames from 'classnames';
import { maxBy, sortBy } from 'lodash';

import * as models from '../models';
import Badge from './Badge';

type Props = {
  step: models.Step;
  className?: string;
  style?: CSSProperties;
}

export default function StepInfo({ step, className, style }: Props) {
  const latestAttempt = maxBy(Object.values(step.attempts), 'number')
  return (
    <div className={classNames('divide-y overflow-hidden', className)} style={style}>
      <div className="px-3 py-3 flex items-center">
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
        <div className="p-3">
          <h3 className="uppercase text-sm font-bold text-gray-400">Arguments</h3>
          <ol className="list-disc list-inside ml-1">
            {step.arguments.map((argument, index) => (
              <li key={index}><span className="font-mono truncate">{argument}</span></li>
            ))}
          </ol>
        </div>
      )}
      {sortBy(Object.values(step.attempts), 'number').map((attempt) => (
        <div key={attempt.number} className="p-3">
          <h3 className="uppercase text-sm font-bold text-gray-400">Attempt {attempt.number}</h3>
          <p>Scheduled: {attempt.createdAt}</p>
          {attempt.assignedAt && (
            <p>Started: {attempt.assignedAt}</p>
          )}
          {attempt.result && (
            attempt.result.type <= 2 ? (
              <Fragment>
                <p>Completed: {attempt.result.createdAt}</p>
                <p>Result: <span className="font-mono">{attempt.result.value}</span></p>
              </Fragment>
            ) : attempt.result.type == 3 ? (
              <Fragment>
                <p>Failed: {attempt.result.createdAt}</p>
                <p>Error: <span className="font-mono">{attempt.result.value}</span></p>
              </Fragment>
            ) : null
          )}
        </div>
      ))}
    </div>
  );
}
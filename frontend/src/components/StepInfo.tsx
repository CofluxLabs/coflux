import React, { CSSProperties, Fragment } from 'react';
import classNames from 'classnames';

import * as models from '../models';
import Badge from './Badge';

type Props = {
  step: models.Step;
  className?: string;
  style?: CSSProperties;
}

export default function StepInfo({ step, className, style }: Props) {
  const latestExecution = step.executions.length ? step.executions[step.executions.length - 1] : null;
  return (
    <div className={classNames('divide-y overflow-hidden', className)} style={style}>
      <div className="px-3 py-3 flex items-center">
        <h2 className="flex-1"><span className="font-mono text-xl">{step.target}</span> <span className="text-gray-500">({step.repository})</span></h2>
        {step.cachedId ? (
          <Badge intent="none" label="Cached" />
        ) : !latestExecution ? (
          <Badge intent="info" label="Scheduling" />
        ) : !latestExecution.assignedAt ? (
          <Badge intent="info" label="Assigning" />
        ) : !latestExecution.result ? (
          <Badge intent="info" label="Running" />
        ) : latestExecution.result.type <= 2 ? (
          <Badge intent="success" label="Completed" />
        ) : latestExecution.result.type == 3 ? (
          <Badge intent="danger" label="Failed" />
        ) : latestExecution.result.type == 4 ? (
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
      {step.executions.map((execution) => (
        <div key={execution.id} className="p-3">
          <h3 className="uppercase text-sm font-bold text-gray-400">Attempt {execution.attempt}</h3>
          <p>Scheduled: {execution.createdAt}</p>
          {execution.assignedAt && (
            <p>Started: {execution.assignedAt}</p>
          )}
          {execution.result && (
            execution.result.type <= 2 ? (
              <Fragment>
                <p>Completed: {execution.result.createdAt}</p>
                <p>Result: <span className="font-mono">{execution.result.value}</span></p>
              </Fragment>
            ) : execution.result.type == 3 ? (
              <Fragment>
                <p>Failed: {execution.result.createdAt}</p>
                <p>Error: <span className="font-mono">{execution.result.value}</span></p>
              </Fragment>
            ) : null
          )}
        </div>
      ))}
    </div>
  );
}
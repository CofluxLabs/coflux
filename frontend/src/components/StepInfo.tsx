import React, { Fragment } from 'react';

import * as models from '../models';
import Badge from './Badge';

type Props = {
  step: models.Step;
}

export default function StepInfo({ step }: Props) {
  const latestExecution = step.executions.length ? step.executions[step.executions.length - 1] : null;
  return (
    <div className="divide-y">
      <div className="px-2 py-3 flex items-center">
        <h2 className="flex-1"><span className="font-mono text-xl">{step.target}</span> <span className="text-gray-500">({step.repository})</span></h2>
        {!latestExecution ? (
          <Badge intent="info" label="Scheduling" />
        ) : !latestExecution.assignedAt ? (
          <Badge intent="info" label="Assigning" />
        ) : !latestExecution.result ? (
          <Badge intent="info" label="Running" />
        ) : latestExecution.result.type <= 2 ? (
          <Badge intent="success" label="Completed" />
        ) : latestExecution.result.type == 3 ? (
          <Badge intent="danger" label="Failed" />
        ) : null}
      </div>
      {step.arguments.length > 0 && (
        <div className="p-2">
          <h3 className="uppercase text-sm font-bold text-gray-400">Arguments</h3>
          <ol className="list-disc list-inside ml-1">
            {step.arguments.map((argument, index) => (
              <li key={index}><span className="font-mono truncate">{argument.value}</span></li>
            ))}
          </ol>
        </div>
      )}
      {step.executions.map((execution, index) => (
        <div key={execution.id} className="p-2">
          <h3 className="uppercase text-sm font-bold text-gray-400">Execution {index + 1}</h3>
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
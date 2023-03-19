import { CSSProperties, Fragment, ReactNode, useCallback, useState } from 'react';
import classNames from 'classnames';
import { filter, findKey, sortBy } from 'lodash';
import { DateTime } from 'luxon';
import { Listbox, Transition } from '@headlessui/react';
import { Link, useNavigate } from 'react-router-dom';
import { useTopic } from '@topical/react';

import * as models from '../models';
import Badge from './Badge';
import { buildUrl } from '../utils';
import Loading from './Loading';
import LogMessage from './LogMessage';

function findExecution(run: models.Run, executionId: string) {
  const stepId = findKey(run.steps, (s) => Object.values(s.attempts).some((a) => a.executionId == executionId));
  if (stepId) {
    const attempt = findKey(run.steps[stepId].attempts, (a) => a.executionId == executionId);
    return [stepId, attempt];
  } else {
    return null;
  }
}

type ResultProps = {
  result: models.Result;
  run: models.Run;
  projectId: string;
  environmentName: string;
}

function Result({ result, run, projectId, environmentName }: ResultProps) {
  switch (result.type) {
    case 0:
      return (
        <div className="font-mono p-2 mt-2 rounded bg-white border border-slate-200">
          {result.value}
        </div>
      );
    case 1:
      return (
        <a
          href={`http://localhost:7070/projects/${projectId}/blobs/${result.value}`}
          className="border border-slate-300 hover:border-slate-600 text-slate-600 text-sm rounded px-2 py-1 my-2 inline-block"
        >
          Blob
        </a>
      );
    case 2:
      const stepAttempt = findExecution(run, result.value);
      if (stepAttempt) {
        const [stepId, attempt] = stepAttempt;
        return (
          <Link
            to={buildUrl(`/projects/${projectId}/runs/${run.id}`, { environment: environmentName, step: stepId, attempt })}
            className="border border-slate-300 hover:border-slate-600 text-slate-600 text-sm rounded px-2 py-1 my-2 inline-block"
          >
            Result
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

type LogMessageItemProps = {
  message: models.LogMessage;
  startTime: DateTime;
}

function LogMessageItem({ message, startTime }: LogMessageItemProps) {
  const createdAt = DateTime.fromISO(message.createdAt);
  return (
    <li>
      <div className="my-2">
        <LogMessage message={message} className="my-1" />
        <div className="text-xs text-slate-500 my-1">
          {createdAt.toLocaleString(DateTime.DATETIME_SHORT_WITH_SECONDS)} (+{(createdAt.diff(startTime).toMillis())}ms)
        </div>
      </div>
    </li>
  )
}

type AttemptProps = {
  attempt: models.Attempt;
  run: models.Run;
  projectId: string;
  environmentName: string;
}

function Attempt({ attempt, run, projectId, environmentName }: AttemptProps) {
  const scheduledAt = DateTime.fromISO(attempt.createdAt);
  const assignedAt = attempt.assignedAt ? DateTime.fromISO(attempt.assignedAt) : null;
  const resultAt = attempt.result && DateTime.fromISO(attempt.result.createdAt);
  // TODO: subscribe to execution logs
  const [logs, _] = useTopic<Record<string, models.LogMessage>>("projects", projectId, "runs", run.id, "logs");
  const attemptLogs = logs && attempt.executionId !== null && filter(logs, { executionId: attempt.executionId });
  return (
    <Fragment>
      <div className="p-4">
        <h3 className="uppercase text-sm font-bold text-slate-400">Execution</h3>
        <p>Started: {scheduledAt.toLocaleString(DateTime.DATETIME_FULL_WITH_SECONDS)}</p>
        {assignedAt && resultAt ? (
          <p>Duration: {resultAt.diff(assignedAt).toMillis()}ms <span className="text-slate-500 text-sm">(+{assignedAt!.diff(scheduledAt).toMillis()}ms wait)</span></p>
        ) : assignedAt ? (
          <p>Executing...</p>
        ) : null}
      </div>
      {attempt.result && (
        <div className="p-4">
          <h3 className="uppercase text-sm font-bold text-slate-400">Result</h3>
          <Result result={attempt.result} run={run} projectId={projectId} environmentName={environmentName} />
        </div>
      )}
      <div className="p-4">
        <h3 className="uppercase text-sm font-bold text-slate-400">Logs</h3>
        {attemptLogs === undefined ? (
          <Loading />
        ) : Object.keys(attemptLogs).length == 0 ? (
          <p><em>None</em></p>
        ) : (
          <ol>
            {sortBy(Object.values(attemptLogs), 'createdAt').map((message, index) => (
              <LogMessageItem key={index} message={message} startTime={scheduledAt} />
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
        <Listbox.Button className="relative w-full p-1 pl-2 bg-white text-left border border-slate-300 text-slate-600 hover:border-slate-600 rounded">
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
                  <div className={classNames('p-2', selected && 'font-bold', active && 'bg-slate-100')}>
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

type ArgumentProps = {
  argument: string;
  run: models.Run;
  projectId: string;
  environmentName: string;
}

function Argument({ argument, run, projectId, environmentName }: ArgumentProps) {
  const [type, value] = argument.split(':', 2);
  switch (type) {
    case 'json':
      return (
        <span className="font-mono truncate">
          {value}
        </span>
      );
    case 'result':
      const stepAttempt = findExecution(run, value);
      if (stepAttempt) {
        const [stepId, attempt] = stepAttempt;
        return (
          <Link
            to={buildUrl(`/projects/${projectId}/runs/${run.id}`, { environment: environmentName, step: stepId, attempt })}
            className="border border-slate-300 hover:border-slate-600 text-slate-600 text-sm rounded px-1 py-0.5 my-0.5 inline-block"
          >
            Result
          </Link>
        );
      } else {
        return <em>Unrecognised execution</em>
      }
    case 'blob':
      return (
        <span>
          <a
            href={`http://localhost:7070/projects/${projectId}/blobs/${value}`}
            className="border border-slate-300 hover:border-slate-600 text-slate-600 text-sm rounded px-1 py-0.5 my-0.5 inline-block"
          >
            Blob
          </a>
        </span>
      );
    default:
      throw new Error(`Unhandled argument type (${type})`);
  }
}

type Props = {
  step: models.Step;
  attemptNumber: number;
  run: models.Run;
  projectId: string;
  environmentName: string;
  className?: string;
  style?: CSSProperties;
  onRerunStep: (stepId: string, environmentName: string) => Promise<number>;
}

export default function StepDetail({ step, attemptNumber, run, projectId, environmentName, className, style, onRerunStep }: Props) {
  const [rerunning, setRerunning] = useState(false);
  const navigate = useNavigate();
  const changeAttempt = useCallback((attempt: number) => {
    // TODO: keep tab
    navigate(buildUrl(`/projects/${projectId}/runs/${run.id}`, { environment: environmentName, step: step.id, attempt }));
  }, [projectId, run, environmentName, step, navigate]);
  const handleRetryClick = useCallback(() => {
    setRerunning(true);
    onRerunStep(step.id, environmentName).then((attempt) => {
      setRerunning(false);
      changeAttempt(attempt);
    });
  }, [onRerunStep, step, environmentName, changeAttempt]);
  const attempt = step.attempts[attemptNumber];
  return (
    <div className={classNames('divide-y divide-slate-200 overflow-hidden', className)} style={style}>
      <div className="p-4 pt-5 flex items-center">
        <h2 className="flex-1"><span className="font-mono text-xl">{step.target}</span> <span className="text-slate-500">({step.repository})</span></h2>
        {step.cached ? (
          <Badge intent="none" label="Cached" />
        ) : !Object.keys(step.attempts).length ? (
          <Badge intent="info" label="Scheduling" />
        ) : (
          <div className="flex">
            <AttemptSelector selectedNumber={attemptNumber} attempts={step.attempts} onChange={changeAttempt}>
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
              className={classNames('ml-1 rounded border border-slate-300 text-slate-600 bg-white hover:border-slate-600 px-2 py-1 text-sm', rerunning && 'text-slate-500')}
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
          <h3 className="uppercase text-sm font-bold text-slate-400">Arguments</h3>
          <ol className="list-decimal list-inside ml-1 marker:text-gray-400 marker:text-xs">
            {step.arguments.map((argument, index) => (
              <li key={index}>
                <Argument argument={argument} run={run} projectId={projectId} environmentName={environmentName} />
              </li>
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
          environmentName={environmentName}
        />
      )}
    </div>
  );
}
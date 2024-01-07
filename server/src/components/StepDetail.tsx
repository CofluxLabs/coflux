import {
  CSSProperties,
  Fragment,
  ReactNode,
  useCallback,
  useState,
} from "react";
import classNames from "classnames";
import { findKey, sortBy } from "lodash";
import { DateTime } from "luxon";
import { Listbox, Transition } from "@headlessui/react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import { useTopic } from "@topical/react";
import { IconChevronDown } from "@tabler/icons-react";

import * as models from "../models";
import Badge from "./Badge";
import { buildUrl } from "../utils";
import Loading from "./Loading";
import Button from "./common/Button";
import RunLogs from "./RunLogs";
import StepLink from "./StepLink";

function findExecution(
  run: models.Run,
  executionId: string
): [string, models.Execution] | null {
  const stepId = findKey(run.steps, (j) => executionId in j.executions);
  if (stepId) {
    const attempt = run.steps[stepId].executions[executionId];
    return [stepId, attempt];
  } else {
    return null;
  }
}

type ResultProps = {
  runId: string;
  run: models.Run;
  result: models.Result;
};

function Result({ runId, run, result }: ResultProps) {
  switch (result.type) {
    case "raw":
      return (
        <div className="font-mono p-2 mt-2 rounded bg-white border border-slate-200">
          {result.value}
        </div>
      );
    case "blob":
      return (
        <a
          href={`/blobs/${result.key}`}
          className="border border-slate-300 hover:border-slate-600 text-slate-600 text-sm rounded px-2 py-1 my-2 inline-block"
        >
          Blob
        </a>
      );
    case "reference":
      const stepAttempt = findExecution(run, result.executionId);
      if (stepAttempt) {
        const [stepId, attempt] = stepAttempt;
        return (
          <StepLink
            runId={runId}
            stepId={stepId}
            attemptNumber={attempt.sequence}
            className="border border-slate-300 hover:border-slate-600 text-slate-600 text-sm rounded px-2 py-1 my-2 inline-block"
          >
            Result
          </StepLink>
        );
      } else {
        return <em>Unrecognised execution</em>;
      }
    case "error":
      return (
        <div className="font-mono p-2 mt-2 rounded bg-red-50 border border-red-200">
          {result.error}
        </div>
      );
    default:
      return null;
  }
}

type DependencyProps = {
  runId: string;
  run: models.Run;
  dependency: string;
};

function Dependency({ runId, run, dependency }: DependencyProps) {
  const execution = findExecution(run, dependency);
  if (execution) {
    return (
      <StepLink
        runId={runId}
        stepId={execution[0]}
        attemptNumber={execution[1].sequence}
        className="border border-slate-300 text-slate-600 text-sm rounded px-2 py-1 my-2 inline-block"
        hoveredClassName="border-slate-600"
      >
        {dependency}
      </StepLink>
    );
  } else {
    return <span>{dependency}</span>;
  }
}

type AttemptProps = {
  attempt: models.Execution;
  executionId: string;
  runId: string;
  run: models.Run;
  projectId: string;
  environmentName: string;
};

function Attempt({
  attempt,
  executionId,
  runId,
  run,
  projectId,
  environmentName,
}: AttemptProps) {
  const scheduledAt = DateTime.fromMillis(attempt.createdAt);
  const assignedAt = attempt.assignedAt
    ? DateTime.fromMillis(attempt.assignedAt)
    : null;
  const completedAt =
    attempt.completedAt !== null
      ? DateTime.fromMillis(attempt.completedAt)
      : null;
  const [logs, _] = useTopic<models.LogMessage[]>(
    "projects",
    projectId,
    "environments",
    environmentName,
    "runs",
    runId,
    "logs"
  );
  const attemptLogs = logs && logs.filter((l) => l[0] == executionId);
  return (
    <Fragment>
      <div>
        <h3 className="uppercase text-sm font-bold text-slate-400">
          Execution
        </h3>
        <p>
          Started:{" "}
          {scheduledAt.toLocaleString(DateTime.DATETIME_FULL_WITH_SECONDS)}
        </p>
        {assignedAt && completedAt ? (
          <p>
            Duration: {completedAt.diff(assignedAt).toMillis()}ms{" "}
            <span className="text-slate-500 text-sm">
              (+{assignedAt!.diff(scheduledAt).toMillis()}ms wait)
            </span>
          </p>
        ) : assignedAt ? (
          <p>Executing...</p>
        ) : null}
      </div>
      <div>
        <h3 className="uppercase text-sm font-bold text-slate-400">
          Dependencies
        </h3>
        {attempt.dependencies.length ? (
          <ul className="flex flex-wrap gap-1">
            {attempt.dependencies.map((dependency) => {
              return (
                <li key={dependency}>
                  <Dependency runId={runId} run={run} dependency={dependency} />
                </li>
              );
            })}
          </ul>
        ) : (
          <p>None</p>
        )}
      </div>
      {attempt.result?.type == "duplicated" ? (
        <div>
          <h3 className="uppercase text-sm font-bold text-slate-400">
            De-duplication
          </h3>
          <p>After: {completedAt!.diff(scheduledAt).toMillis()}ms</p>
          {attempt.retry && (
            <Fragment>
              <Link
                to={buildUrl(
                  `/projects/${projectId}/runs/${attempt.retry.runId}/graph`,
                  {
                    environment: environmentName,
                    step: attempt.retry.stepId,
                    attempt: attempt.retry.sequence,
                  }
                )}
                className="border border-slate-300 hover:border-slate-600 text-slate-600 text-sm rounded px-2 py-1 my-2 inline-block"
              >
                Successor
              </Link>
              {attempt.retry.runId != runId ? `(${attempt.retry.runId})` : null}
            </Fragment>
          )}
        </div>
      ) : (
        <Fragment>
          {attempt.result &&
            attempt.result?.type != "abandoned" &&
            attempt.result?.type != "cancelled" && (
              <div>
                <h3 className="uppercase text-sm font-bold text-slate-400">
                  Result
                </h3>
                <Result result={attempt.result} runId={runId} run={run} />
              </div>
            )}
          <div>
            <h3 className="uppercase text-sm font-bold text-slate-400">Logs</h3>
            {attemptLogs === undefined ? (
              <Loading />
            ) : (
              <RunLogs
                startTime={scheduledAt}
                logs={attemptLogs}
                darkerTimestampRule={true}
              />
            )}
          </div>
        </Fragment>
      )}
    </Fragment>
  );
}

type AttemptSelectorProps = {
  selectedNumber: number;
  attempts: Record<number, models.Execution>;
  onChange: (number: number) => void;
  children: (
    attempt: models.Execution,
    selected: boolean,
    active: boolean
  ) => ReactNode;
};

function AttemptSelector({
  selectedNumber,
  attempts,
  onChange,
  children,
}: AttemptSelectorProps) {
  const selectedAttempt = Object.values(attempts).find(
    (a) => a.sequence == selectedNumber
  );
  return (
    <Listbox value={selectedNumber} onChange={onChange}>
      <div className="relative">
        <Listbox.Button className="flex items-center gap-1 relative p-1 pl-2 bg-white text-left text-slate-600 border border-slate-300 rounded-md shadow-sm font-bold">
          {selectedAttempt && children(selectedAttempt, true, false)}
          <IconChevronDown size={16} className="opacity-40" />
        </Listbox.Button>
        <Transition
          as={Fragment}
          enter="transition ease-in duration-100"
          enterFrom="opacity-0 scale-95"
          enterTo="opacity-100 scale-100"
          leave="transition ease-in duration-100"
          leaveFrom="opacity-100 scale-100"
          leaveTo="opacity-0 scale-95"
        >
          <Listbox.Options className="absolute p-1 mt-1 overflow-auto text-base bg-white rounded shadow-lg max-h-60">
            {sortBy(Object.values(attempts), "sequence").map((attempt) => (
              <Listbox.Option key={attempt.sequence} value={attempt.sequence}>
                {({ selected, active }) => (
                  <div
                    className={classNames(
                      "p-1 cursor-default rounded",
                      selected && "font-bold",
                      active && "bg-slate-100"
                    )}
                  >
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
  argument: models.Argument;
  runId: string;
  run: models.Run;
};

function Argument({ runId, run, argument }: ArgumentProps) {
  switch (argument.type) {
    case "raw":
      return <span className="font-mono truncate">{argument.value}</span>;
    case "reference":
      const stepAttempt = findExecution(run, argument.executionId);
      if (stepAttempt) {
        const [stepId, attempt] = stepAttempt;
        return (
          <StepLink
            runId={runId}
            stepId={stepId}
            attemptNumber={attempt.sequence}
            className="border border-slate-300 hover:border-slate-600 text-slate-600 text-sm rounded px-1 py-0.5 my-0.5 inline-block"
          >
            Result
          </StepLink>
        );
      } else {
        return <em>Unrecognised execution</em>;
      }
    case "blob":
      return (
        <span>
          <a
            href={`/blobs/${argument.key}`}
            className="border border-slate-300 hover:border-slate-600 text-slate-600 text-sm rounded px-1 py-0.5 my-0.5 inline-block"
          >
            Blob
          </a>
          ({argument.format})
        </span>
      );
    default:
      throw new Error(`Unhandled argument type (${argument})`);
  }
}

type Props = {
  runId: string;
  stepId: string;
  sequence: number;
  run: models.Run;
  projectId: string;
  environmentName: string;
  className?: string;
  style?: CSSProperties;
  onRerunStep: (stepId: string, environmentName: string) => Promise<number>;
};

export default function StepDetail({
  runId,
  stepId,
  sequence,
  run,
  projectId,
  environmentName,
  className,
  style,
  onRerunStep,
}: Props) {
  const step = run.steps[stepId];
  const [rerunning, setRerunning] = useState(false);
  const navigate = useNavigate();
  const location = useLocation();
  const changeAttempt = useCallback(
    (attempt: number) => {
      navigate(
        buildUrl(location.pathname, {
          environment: environmentName,
          step: stepId,
          attempt,
        })
      );
    },
    [projectId, run, environmentName, step, navigate, location]
  );
  const handleRetryClick = useCallback(() => {
    setRerunning(true);
    onRerunStep(stepId, environmentName).then((attempt) => {
      setRerunning(false);
      changeAttempt(attempt);
    });
  }, [onRerunStep, stepId, environmentName, changeAttempt]);
  const executionId = Object.keys(step.executions).find(
    (id) => step.executions[id].sequence == sequence
  );
  const attempt = executionId && step.executions[executionId];
  return (
    <div
      className={classNames("overflow-hidden flex flex-col", className)}
      style={style}
    >
      <div className="p-4 pt-5 flex items-center border-b border-slate-200">
        <div className="flex-1">
          <h2>
            <span className="font-mono text-xl">{step.target}</span>{" "}
            <span className="text-slate-500">({step.repository})</span>
          </h2>
          {!step.cachedExecutionId && (
            <div className="flex items-center gap-1 mt-1">
              <AttemptSelector
                selectedNumber={sequence}
                attempts={step.executions}
                onChange={changeAttempt}
              >
                {(attempt) => (
                  <div className="flex items-center gap-2">
                    <span className="flex-1 text-sm">#{attempt.sequence}</span>
                    {attempt.result?.type == "duplicated" ? (
                      <Badge intent="none" label="Duplicated" />
                    ) : !attempt.assignedAt ? (
                      <Badge intent="info" label="Assigning" />
                    ) : !attempt.result ? (
                      <Badge intent="info" label="Running" />
                    ) : ["reference", "raw", "blob"].includes(
                        attempt.result.type
                      ) ? (
                      <Badge intent="success" label="Completed" />
                    ) : attempt.result.type == "error" ? (
                      <Badge intent="danger" label="Failed" />
                    ) : attempt.result.type == "abandoned" ? (
                      <Badge intent="warning" label="Abandoned" />
                    ) : attempt.result.type == "cancelled" ? (
                      <Badge intent="warning" label="Cancelled" />
                    ) : null}
                  </div>
                )}
              </AttemptSelector>

              <Button
                disabled={rerunning}
                outline={true}
                size="sm"
                onClick={handleRetryClick}
              >
                Retry
              </Button>
            </div>
          )}
        </div>
        {step.cachedExecutionId ? (
          <Badge intent="none" label="Cached" />
        ) : !Object.keys(step.executions).length ? (
          <Badge intent="info" label="Scheduling" />
        ) : null}
      </div>
      <div className="flex flex-col overflow-auto p-4 gap-5">
        {step.arguments?.length > 0 && (
          <div>
            <h3 className="uppercase text-sm font-bold text-slate-400">
              Arguments
            </h3>
            <ol className="list-decimal list-inside ml-1 marker:text-slate-400 marker:text-xs">
              {step.arguments.map((argument, index) => (
                <li key={index}>
                  <Argument runId={runId} run={run} argument={argument} />
                </li>
              ))}
            </ol>
          </div>
        )}
        {attempt && (
          <Attempt
            key={attempt.sequence}
            attempt={attempt}
            executionId={executionId}
            runId={runId}
            run={run}
            projectId={projectId}
            environmentName={environmentName}
          />
        )}
      </div>
    </div>
  );
}

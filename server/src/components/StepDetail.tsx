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
import { useLocation, useNavigate } from "react-router-dom";
import { useTopic } from "@topical/react";
import { IconChevronDown } from "@tabler/icons-react";

import * as models from "../models";
import Badge from "./Badge";
import { buildUrl, formatDiff } from "../utils";
import Loading from "./Loading";
import Button from "./common/Button";
import RunLogs from "./RunLogs";
import StepLink from "./StepLink";

function findAttempt(
  run: models.Run,
  executionId: string,
): [string, number] | null {
  const stepId = findKey(run.steps, (s) =>
    Object.values(s.attempts).some(
      (a) => a.type == 0 && a.executionId == executionId,
    ),
  );
  if (stepId) {
    const attemptNumber = findKey(
      run.steps[stepId].attempts,
      (a) => a.type == 0 && a.executionId == executionId,
    );
    return [stepId, parseInt(attemptNumber!, 10)];
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
      const stepAttempt = findAttempt(run, result.executionId);
      if (stepAttempt) {
        const [stepId, attemptNumber] = stepAttempt;
        return (
          <StepLink
            runId={runId}
            stepId={stepId}
            attemptNumber={attemptNumber}
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

type AttemptProps = {
  attempt: models.Attempt;
  runId: string;
  run: models.Run;
  projectId: string;
  environmentName: string;
};

function Attempt({
  attempt,
  runId,
  run,
  projectId,
  environmentName,
}: AttemptProps) {
  const scheduledAt = DateTime.fromMillis(
    attempt.executeAfter || attempt.createdAt,
  );
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
    "logs",
  );
  const attemptLogs = logs && logs.filter((l) => l[0] == attempt.executionId);
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
            Duration:{" "}
            {formatDiff(
              completedAt.diff(assignedAt, [
                "days",
                "hours",
                "minutes",
                "seconds",
                "milliseconds",
              ]),
            )}{" "}
            <span className="text-slate-500 text-sm">
              (+
              {formatDiff(
                assignedAt!.diff(scheduledAt, [
                  "days",
                  "hours",
                  "minutes",
                  "seconds",
                  "milliseconds",
                ]),
                true,
              )}{" "}
              wait)
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
        {Object.keys(attempt.dependencies).length ? (
          <ul className="">
            {Object.entries(attempt.dependencies).map(
              ([dependencyId, dependency]) => {
                return (
                  <li key={dependencyId}>
                    <StepLink
                      runId={dependency.runId}
                      stepId={dependency.stepId}
                      attemptNumber={dependency.sequence}
                      className="rounded text-sm ring-offset-1 px-1"
                      hoveredClassName="ring-2 ring-slate-300"
                    >
                      <span className="font-mono">{dependency.target}</span>{" "}
                      <span className="text-slate-500">
                        ({dependency.repository})
                      </span>
                    </StepLink>
                  </li>
                );
              },
            )}
          </ul>
        ) : (
          <p>None</p>
        )}
      </div>
      <div>
        <h3 className="uppercase text-sm font-bold text-slate-400">Children</h3>
        {attempt.children.length ? (
          <ul className="">
            {attempt.children.map((child) => {
              if (typeof child == "string") {
                const step = run.steps[child];
                return (
                  <li key={child}>
                    <StepLink
                      runId={runId}
                      stepId={child}
                      attemptNumber={1}
                      className="rounded text-sm ring-offset-1 px-1"
                      hoveredClassName="ring-2 ring-slate-300"
                    >
                      <span className="font-mono">{step.target}</span>{" "}
                      <span className="text-slate-500">
                        ({step.repository})
                      </span>
                    </StepLink>
                  </li>
                );
              } else {
                return (
                  <li key={child.stepId}>
                    <StepLink
                      runId={child.runId}
                      stepId={child.stepId}
                      attemptNumber={1}
                      className="rounded text-sm ring-offset-1 px-1"
                      hoveredClassName="ring-2 ring-slate-300"
                    >
                      <span className="font-mono">{child.target}</span>{" "}
                      <span className="text-slate-500">
                        ({child.repository})
                      </span>
                    </StepLink>
                  </li>
                );
              }
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
          <p>
            After:{" "}
            {formatDiff(
              scheduledAt.diff(completedAt!, [
                "days",
                "hours",
                "minutes",
                "seconds",
                "milliseconds",
              ]),
            )}
          </p>
          {attempt.retry && (
            <p>
              To:{" "}
              <StepLink
                runId={attempt.retry.runId}
                stepId={attempt.retry.stepId}
                attemptNumber={attempt.retry.sequence}
                className="rounded text-sm ring-offset-1 px-1"
                hoveredClassName="ring-2 ring-slate-300"
              >
                <span className="font-mono">{attempt.retry.target}</span>{" "}
                <span className="text-slate-500">
                  ({attempt.retry.repository})
                </span>
              </StepLink>
            </p>
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
  attempts: Record<number, models.Attempt>;
  onChange: (number: number) => void;
  children: (
    sequence: number,
    attempt: models.Attempt,
    selected: boolean,
    active: boolean,
  ) => ReactNode;
};

function AttemptSelector({
  selectedNumber,
  attempts,
  onChange,
  children,
}: AttemptSelectorProps) {
  const selectedAttempt = attempts[selectedNumber];
  return (
    <Listbox value={selectedNumber} onChange={onChange}>
      <div className="relative">
        <Listbox.Button className="flex items-center gap-1 relative p-1 pl-2 bg-white text-left text-slate-600 border border-slate-300 rounded-md shadow-sm font-bold">
          {selectedAttempt &&
            children(selectedNumber, selectedAttempt, true, false)}
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
            {sortBy(Object.entries(attempts), "sequence").map(
              ([attemptNumber, attempt]) => (
                <Listbox.Option key={attemptNumber} value={attemptNumber}>
                  {({ selected, active }) => (
                    <div
                      className={classNames(
                        "p-1 cursor-default rounded",
                        selected && "font-bold",
                        active && "bg-slate-100",
                      )}
                    >
                      {children(
                        parseInt(attemptNumber, 10),
                        attempt,
                        selected,
                        active,
                      )}
                    </div>
                  )}
                </Listbox.Option>
              ),
            )}
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
      const stepAttempt = findAttempt(run, argument.executionId);
      if (stepAttempt) {
        const [stepId, attemptNumber] = stepAttempt;
        return (
          <StepLink
            runId={runId}
            stepId={stepId}
            attemptNumber={attemptNumber}
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
  onRerunStep: (stepId: string, environmentName: string) => Promise<any>;
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
        }),
      );
    },
    [projectId, run, environmentName, step, navigate, location],
  );
  const handleRetryClick = useCallback(() => {
    setRerunning(true);
    onRerunStep(stepId, environmentName).then(({ sequence }) => {
      setRerunning(false);
      changeAttempt(sequence);
    });
  }, [onRerunStep, stepId, environmentName, changeAttempt]);
  const attempt = step.attempts[sequence];
  return (
    <div
      className={classNames("overflow-hidden flex flex-col", className)}
      style={style}
    >
      <div className="p-4 pt-5 flex items-center border-b border-slate-200">
        <div className="flex-1">
          <h2>
            <span
              className={classNames(
                "font-mono text-xl",
                step.type == 0 && "font-bold",
              )}
            >
              {step.target}
            </span>{" "}
            <span className="text-slate-500">({step.repository})</span>
          </h2>
          <div className="flex items-center gap-1 mt-1">
            <AttemptSelector
              selectedNumber={sequence}
              attempts={step.attempts}
              onChange={changeAttempt}
            >
              {(attemptNumber, attempt) => (
                <div className="flex items-center gap-2">
                  <span className="flex-1 text-sm">#{attemptNumber}</span>
                  {attempt.type == 1 ? (
                    <Badge intent="none" label="Cached" />
                  ) : attempt.result?.type == "duplicated" ? (
                    <Badge intent="none" label="Duplicated" />
                  ) : !attempt.assignedAt ? (
                    <Badge intent="info" label="Assigning" />
                  ) : !attempt.result ? (
                    <Badge intent="info" label="Running" />
                  ) : ["reference", "raw", "blob"].includes(
                      attempt.result.type,
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
        </div>
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
        {attempt?.type == 0 ? (
          <Attempt
            attempt={attempt}
            runId={runId}
            run={run}
            projectId={projectId}
            environmentName={environmentName}
          />
        ) : attempt?.type == 1 ? (
          <div>{/* TODO: link to execution */}</div>
        ) : undefined}
      </div>
    </div>
  );
}

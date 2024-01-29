import { CSSProperties, Fragment, useCallback, useState } from "react";
import classNames from "classnames";
import { sortBy } from "lodash";
import { DateTime } from "luxon";
import { Listbox, Transition } from "@headlessui/react";
import { useLocation, useNavigate } from "react-router-dom";
import { useTopic } from "@topical/react";
import { IconChevronDown, IconPinned } from "@tabler/icons-react";
import reactStringReplace from "react-string-replace";

import * as models from "../models";
import Badge from "./Badge";
import { buildUrl, formatDiff, humanSize } from "../utils";
import Loading from "./Loading";
import Button from "./common/Button";
import RunLogs from "./RunLogs";
import StepLink from "./StepLink";

type AttemptSelectorOptionProps = {
  attemptNumber: number;
  attempt: models.Attempt;
};

function AttemptSelectorOption({
  attemptNumber,
  attempt,
}: AttemptSelectorOptionProps) {
  return (
    <div className="flex items-center gap-2">
      <span className="flex-1 text-sm">#{attemptNumber}</span>
      {attempt.isCached ? (
        <Badge intent="none" label="Cached" />
      ) : attempt.result?.type == "deferred" ? (
        <Badge intent="none" label="Deferred" />
      ) : !attempt.assignedAt ? (
        <Badge intent="info" label="Assigning" />
      ) : !attempt.result ? (
        <Badge intent="info" label="Running" />
      ) : ["value"].includes(attempt.result.type) ? (
        <Badge intent="success" label="Completed" />
      ) : attempt.result.type == "error" ? (
        <Badge intent="danger" label="Failed" />
      ) : attempt.result.type == "abandoned" ? (
        <Badge intent="warning" label="Abandoned" />
      ) : attempt.result.type == "cancelled" ? (
        <Badge intent="warning" label="Cancelled" />
      ) : null}
    </div>
  );
}

type AttemptSelectorProps = {
  selectedNumber: number;
  attempts: Record<number, models.Attempt>;
  onChange: (number: number) => void;
};

function AttemptSelector({
  selectedNumber,
  attempts,
  onChange,
}: AttemptSelectorProps) {
  const selectedAttempt = attempts[selectedNumber];
  return (
    <Listbox value={selectedNumber} onChange={onChange}>
      <div className="relative">
        <Listbox.Button className="flex items-center gap-1 relative p-1 pl-2 bg-white text-left text-slate-600 border border-slate-300 rounded-md shadow-sm font-bold">
          {selectedAttempt && (
            <AttemptSelectorOption
              attemptNumber={selectedNumber}
              attempt={selectedAttempt}
            />
          )}
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
                      <AttemptSelectorOption
                        attemptNumber={parseInt(attemptNumber, 10)}
                        attempt={attempt}
                      />
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

type HeaderProps = {
  projectId: string;
  environmentName: string;
  run: models.Run;
  stepId: string;
  step: models.Step;
  sequence: number;
  onRerunStep: (stepId: string, environmentName: string) => Promise<any>;
};

function Header({
  projectId,
  environmentName,
  run,
  stepId,
  step,
  sequence,
  onRerunStep,
}: HeaderProps) {
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
  return (
    <div className="p-4 pt-5 flex items-start border-b border-slate-200">
      <div className="flex-1">
        <h2>
          <span
            className={classNames(
              "font-mono text-xl",
              step.isInitial && "font-bold",
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
          />

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
      {step.isMemoised && (
        <span className="text-slate-500" title="Memoised">
          <IconPinned size={20} />
        </span>
      )}
    </div>
  );
}

type BlobLinkProps = {
  value: Extract<models.Value, { type: "blob" }>;
};

function BlobLink({ value }: BlobLinkProps) {
  const hints = [value.format];
  if (value.metadata.size) {
    hints.push(humanSize(value.metadata.size));
  }
  return (
    <span className="">
      <a
        href={`/blobs/${value.key}`}
        className="border border-slate-300 hover:border-slate-600 text-slate-600 text-sm rounded px-2 py-1 my-2 inline-block"
      >
        Blob
      </a>
      <span className="text-slate-500 text-xs ml-1">({hints.join("; ")})</span>
    </span>
  );
}

type ValueProps = {
  value: Extract<models.Value, { type: "raw" }>;
  className?: string;
};

function Value({ value, className }: ValueProps) {
  return (
    <span className={classNames("font-mono text-sm", className)}>
      {reactStringReplace(value.content, /"\{(\d+)\}"/g, (match, index) => {
        const referenceNumber = parseInt(match, 10);
        if (referenceNumber in value.references) {
          const [_, reference] = value.references[referenceNumber];
          return (
            <StepLink
              key={index}
              runId={reference.runId}
              stepId={reference.stepId}
              attemptNumber={reference.sequence}
              className="font-sans text-base px-1 bg-slate-200 ring-offset-1 text-slate-600 text-sm rounded"
              hoveredClassName="ring-2 ring-slate-300"
            >
              ...
            </StepLink>
          );
        } else {
          return `{${match}}`;
        }
      })}
    </span>
  );
}

type ArgumentProps = {
  argument: models.Value;
};

function Argument({ argument }: ArgumentProps) {
  switch (argument.type) {
    case "raw":
      return (
        <Value
          value={argument}
          className="bg-white px-0.5 border border-slate-300 rounded"
        />
      );
    case "blob":
      return <BlobLink value={argument} />;
    default:
      throw new Error(`Unhandled argument type (${argument})`);
  }
}

type ArgumentsSectionProps = {
  arguments_: models.Value[];
};

function ArgumentsSection({ arguments_ }: ArgumentsSectionProps) {
  return (
    <div>
      <h3 className="uppercase text-sm font-bold text-slate-400">Arguments</h3>
      <ol className="list-decimal list-inside ml-1 marker:text-slate-400 marker:text-xs">
        {arguments_.map((argument, index) => (
          <li key={index}>
            <Argument argument={argument} />
          </li>
        ))}
      </ol>
    </div>
  );
}

type ExecutionSectionProps = {
  attempt: models.Attempt;
};

function ExecutionSection({ attempt }: ExecutionSectionProps) {
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
  return (
    <div>
      <h3 className="uppercase text-sm font-bold text-slate-400">Execution</h3>
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
  );
}

type DependenciesSectionProps = {
  attempt: models.Attempt;
};

function DependenciesSection({ attempt }: DependenciesSectionProps) {
  return (
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
  );
}

type ChildrenSectionProps = {
  runId: string;
  run: models.Run;
  attempt: models.Attempt;
};

function ChildrenSection({ runId, run, attempt }: ChildrenSectionProps) {
  return (
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
                    <span className="text-slate-500">({step.repository})</span>
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
                    <span className="text-slate-500">({child.repository})</span>
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
  );
}

type DeferredSectionProps = {
  attempt: models.Attempt;
};

function DeferredSection({ attempt }: DeferredSectionProps) {
  const scheduledAt = DateTime.fromMillis(
    attempt.executeAfter || attempt.createdAt,
  );
  const completedAt =
    attempt.completedAt !== null
      ? DateTime.fromMillis(attempt.completedAt)
      : null;
  const result = attempt.result as Extract<models.Result, { type: "deferred" }>;
  return (
    <div>
      <h3 className="uppercase text-sm font-bold text-slate-400">Deferred</h3>
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
      {result.execution && (
        <p>
          To:{" "}
          <StepLink
            runId={result.execution.runId}
            stepId={result.execution.stepId}
            attemptNumber={result.execution.sequence}
            className="rounded text-sm ring-offset-1 px-1"
            hoveredClassName="ring-2 ring-slate-300"
          >
            <span className="font-mono">{result.execution.target}</span>{" "}
            <span className="text-slate-500">
              ({result.execution.repository})
            </span>
          </StepLink>
        </p>
      )}
    </div>
  );
}

type ResultProps = {
  result: models.Result;
};

function Result({ result }: ResultProps) {
  switch (result.type) {
    case "value":
      const value = result.value;
      switch (value.type) {
        case "raw":
          return (
            <div className="bg-white rounded block p-1 border border-slate-300 break-all whitespace-break-spaces">
              {" "}
              <Value value={value} />
            </div>
          );
        case "blob":
          return <BlobLink value={value} />;
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

type ResultSectionProps = {
  result: models.Result;
};

function ResultSection({ result }: ResultSectionProps) {
  return (
    <div>
      <h3 className="uppercase text-sm font-bold text-slate-400">Result</h3>
      <Result result={result} />
    </div>
  );
}

type LogsSectionProps = {
  projectId: string;
  environmentName: string;
  runId: string;
  attempt: models.Attempt;
};

function LogsSection({
  projectId,
  environmentName,
  runId,
  attempt,
}: LogsSectionProps) {
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
  const scheduledAt = DateTime.fromMillis(
    attempt.executeAfter || attempt.createdAt,
  );
  return (
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
  );
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
  const attempt = step.attempts[sequence];
  return (
    <div
      className={classNames("overflow-hidden flex flex-col", className)}
      style={style}
    >
      <Header
        projectId={projectId}
        environmentName={environmentName}
        run={run}
        stepId={stepId}
        step={step}
        sequence={sequence}
        onRerunStep={onRerunStep}
      />
      <div className="flex flex-col overflow-auto p-4 gap-5">
        {step.arguments?.length > 0 && (
          <ArgumentsSection arguments_={step.arguments} />
        )}
        {/* TODO: link to run if cached? */}
        <ExecutionSection attempt={attempt} />
        {attempt?.assignedAt && (
          <Fragment>
            <DependenciesSection attempt={attempt} />
            <ChildrenSection runId={runId} run={run} attempt={attempt} />
          </Fragment>
        )}
        {attempt?.result?.type == "deferred" && (
          <DeferredSection attempt={attempt} />
        )}
        {(attempt?.result?.type == "value" ||
          attempt?.result?.type == "error") && (
          <ResultSection result={attempt.result} />
        )}
        {attempt?.assignedAt && (
          <LogsSection
            projectId={projectId}
            environmentName={environmentName}
            runId={runId}
            attempt={attempt}
          />
        )}
      </div>
    </div>
  );
}

import { CSSProperties, Fragment, useCallback, useState } from "react";
import classNames from "classnames";
import { minBy, sortBy } from "lodash";
import { DateTime } from "luxon";
import { Listbox, Menu, Transition } from "@headlessui/react";
import { useLocation, useNavigate } from "react-router-dom";
import {
  IconChevronDown,
  IconFunction,
  IconPinned,
  IconReload,
} from "@tabler/icons-react";
import reactStringReplace from "react-string-replace";

import * as models from "../models";
import Badge from "./Badge";
import { buildUrl, formatDiff, humanSize, truncatePath } from "../utils";
import Loading from "./Loading";
import Button from "./common/Button";
import RunLogs from "./RunLogs";
import StepLink from "./StepLink";
import AssetLink from "./AssetLink";
import { getAssetMetadata } from "../assets";
import AssetIcon from "./AssetIcon";
import EnvironmentLabel from "./EnvironmentLabel";
import { useEnvironments, useLogs } from "../topics";

type AttemptSelectorOptionProps = {
  attempt: number;
  execution: models.Execution;
};

function AttemptSelectorOption({
  attempt,
  execution,
}: AttemptSelectorOptionProps) {
  return (
    <div className="flex items-center gap-2">
      <span className="flex-1 text-sm">#{attempt}</span>
      {execution.result?.type == "cached" ? (
        <Badge intent="none" label="Cached" />
      ) : execution.result?.type == "deferred" ? (
        <Badge intent="none" label="Deferred" />
      ) : execution.result?.type == "value" ? (
        <Badge intent="success" label="Completed" />
      ) : execution.result?.type == "error" ? (
        <Badge intent="danger" label="Failed" />
      ) : execution.result?.type == "abandoned" ? (
        <Badge intent="warning" label="Abandoned" />
      ) : execution.result?.type == "cancelled" ? (
        <Badge intent="warning" label="Cancelled" />
      ) : !execution.assignedAt ? (
        <Badge intent="info" label="Assigning" />
      ) : !execution.result ? (
        <Badge intent="info" label="Running" />
      ) : null}
    </div>
  );
}

type AttemptSelectorProps = {
  selected: number;
  executions: Record<number, models.Execution>;
  onChange: (number: number) => void;
};

function AttemptSelector({
  selected,
  executions,
  onChange,
}: AttemptSelectorProps) {
  const selectedExecution = executions[selected];
  return (
    <Listbox value={selected} onChange={onChange}>
      <div className="relative">
        <Listbox.Button className="flex items-center gap-1 relative p-1 pl-2 bg-white text-left text-slate-600 border border-slate-300 rounded-md shadow-sm font-bold">
          {selectedExecution && (
            <AttemptSelectorOption
              attempt={selected}
              execution={selectedExecution}
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
            {sortBy(Object.entries(executions), "attempt").map(
              ([attempt, execution]) => (
                <Listbox.Option key={attempt} value={attempt}>
                  {({ selected, active }) => (
                    <div
                      className={classNames(
                        "p-1 cursor-default rounded",
                        selected && "font-bold",
                        active && "bg-slate-100",
                      )}
                    >
                      <AttemptSelectorOption
                        attempt={parseInt(attempt, 10)}
                        execution={execution}
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

function getEnvironmentDescendantIds(
  environments: Record<string, models.Environment>,
  parentId: string | null,
): string[] {
  return Object.entries(environments)
    .filter(([_, e]) => e.baseId == parentId && e.status != 1)
    .flatMap(([environmentId]) => [
      environmentId,
      ...getEnvironmentDescendantIds(environments, environmentId),
    ]);
}

function getEnvironmentOptions(
  environments: Record<string, models.Environment>,
  parentId: string,
) {
  return [parentId, ...getEnvironmentDescendantIds(environments, parentId)];
}

function getBaseExecution(step: models.Step, run: models.Run) {
  if (step.parentId) {
    return Object.values(run.steps)
      .flatMap((s) => Object.values(s.executions))
      .find((e) => e.executionId == step.parentId)!;
  } else {
    const initialStep = Object.values(run.steps).find((s) => !s.parentId)!;
    const initialAttempt = minBy(Object.keys(initialStep.executions), Number)!;
    return initialStep.executions[initialAttempt];
  }
}

type HeaderProps = {
  projectId: string;
  activeEnvironmentId: string;
  runEnvironmentId: string;
  run: models.Run;
  stepId: string;
  step: models.Step;
  attempt: number;
  onRerunStep: (stepId: string, environmentName: string) => Promise<any>;
};

function Header({
  projectId,
  activeEnvironmentId,
  runEnvironmentId,
  run,
  stepId,
  step,
  attempt,
  onRerunStep,
}: HeaderProps) {
  const environments = useEnvironments(projectId);
  const activeEnvironmentName = environments?.[activeEnvironmentId].name;
  const [rerunning, setRerunning] = useState(false);
  const navigate = useNavigate();
  const location = useLocation();
  const changeAttempt = useCallback(
    (attempt: number, environmentName?: string) => {
      navigate(
        buildUrl(location.pathname, {
          environment: environmentName || activeEnvironmentName,
          step: stepId,
          attempt,
        }),
      );
    },
    [stepId, activeEnvironmentName, navigate, location],
  );
  const executionEnvironmentId = step.executions[attempt].environmentId;
  const baseEnvironmentId = getBaseExecution(step, run).environmentId;
  const childEnvironmentIds =
    environments && getEnvironmentOptions(environments, baseEnvironmentId);
  const handleRerunClick = useCallback(
    (environmentId: string) => {
      const environmentName = environments![environmentId].name;
      setRerunning(true);
      onRerunStep(stepId, environmentName)
        .then(({ attempt }) => {
          // TODO: wait for attempt to be synced to topic
          changeAttempt(attempt, environmentName);
        })
        .finally(() => {
          setRerunning(false);
        });
    },
    [environments, onRerunStep, stepId, changeAttempt],
  );
  return (
    <div className="p-4 pt-5 flex items-start border-b border-slate-200">
      <div className="flex-1 flex flex-col gap-2">
        <div className="flex justify-between items-center gap-2">
          <div className="flex items-center flex-wrap gap-x-2">
            <h2
              className={classNames("font-mono", !step.parentId && "font-bold")}
            >
              {step.target}
            </h2>
            <span className="text-slate-500 text-sm">({step.repository})</span>
            {step.isMemoised && (
              <span
                className="text-slate-500"
                title="This execution has been memoised"
              >
                <IconPinned size={16} />
              </span>
            )}
          </div>

          {executionEnvironmentId != runEnvironmentId && (
            <EnvironmentLabel
              projectId={projectId}
              environmentId={executionEnvironmentId}
              warning="This execution ran in a different environment"
            />
          )}
        </div>
        <div className="flex items-center gap-1">
          <AttemptSelector
            selected={attempt}
            executions={step.executions}
            onChange={changeAttempt}
          />
          <div className="flex shadow-sm relative">
            <Button
              disabled={rerunning}
              outline={true}
              size="sm"
              className="[&:not(:last-child)]:rounded-r-none"
              left={<IconReload size={14} />}
              onClick={() => handleRerunClick(executionEnvironmentId)}
            >
              Re-run
            </Button>
            {childEnvironmentIds?.length ? (
              <Menu>
                <Menu.Button
                  as={Button}
                  disabled={rerunning}
                  outline={true}
                  size="sm"
                  className="rounded-l-none -ml-px"
                >
                  <IconChevronDown size={16} />
                </Menu.Button>
                <Transition
                  as={Fragment}
                  leave="transition ease-in duration-100"
                  leaveFrom="opacity-100"
                  leaveTo="opacity-0"
                >
                  <Menu.Items className="absolute top-full left-0 z-10 overflow-y-scroll bg-white rounded shadow-lg max-h-60 flex flex-col p-1 mt-1 min-w-full">
                    {childEnvironmentIds
                      .filter((id) => id != executionEnvironmentId)
                      .map((environmentId) => (
                        <Menu.Item key={environmentId} as={Fragment}>
                          {({ active }) => (
                            <button
                              className={classNames(
                                "p-1 text-left text-sm rounded",
                                active && "bg-slate-100",
                              )}
                              onClick={() => handleRerunClick(environmentId)}
                            >
                              {environments?.[environmentId].name}
                            </button>
                          )}
                        </Menu.Item>
                      ))}
                  </Menu.Items>
                </Transition>
              </Menu>
            ) : null}
          </div>
        </div>
      </div>
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
        const placeholder = value.placeholders[parseInt(match, 10)];
        switch (placeholder?.type) {
          case "execution": {
            const execution = placeholder.execution;
            return (
              <StepLink
                key={index}
                runId={execution.runId}
                stepId={execution.stepId}
                attempt={execution.attempt}
                className="p-0.5 mx-0.5 bg-slate-100 hover:bg-slate-200 ring-offset-1 rounded"
                hoveredClassName="ring-2 ring-slate-300"
              >
                <IconFunction size={16} className="inline-block" />
              </StepLink>
            );
          }
          case "asset": {
            const asset = placeholder.asset;
            return (
              <AssetLink
                key={index}
                asset={asset}
                className="p-0.5 mx-0.5 bg-slate-100 hover:bg-slate-200 rounded"
              >
                <AssetIcon asset={asset} className="inline-block" />
              </AssetLink>
            );
          }
          default:
            return `"{${match}}"`;
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
          className="bg-white p-1 border border-slate-300 rounded"
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
          <li key={index} className="my-1">
            <Argument argument={argument} />
          </li>
        ))}
      </ol>
    </div>
  );
}

type ExecutionSectionProps = {
  execution: models.Execution;
};

function ExecutionSection({ execution }: ExecutionSectionProps) {
  const scheduledAt = DateTime.fromMillis(
    execution.executeAfter || execution.createdAt,
  );
  const assignedAt = execution.assignedAt
    ? DateTime.fromMillis(execution.assignedAt)
    : null;
  const completedAt =
    execution.completedAt !== null
      ? DateTime.fromMillis(execution.completedAt)
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
  execution: models.Execution;
};

function DependenciesSection({ execution }: DependenciesSectionProps) {
  return (
    <div>
      <h3 className="uppercase text-sm font-bold text-slate-400">
        Dependencies
      </h3>
      {Object.keys(execution.dependencies).length > 0 ? (
        <ul>
          {Object.entries(execution.dependencies).map(
            ([dependencyId, dependency]) => {
              return (
                <li key={`r-${dependencyId}`}>
                  <StepLink
                    runId={dependency.runId}
                    stepId={dependency.stepId}
                    attempt={dependency.attempt}
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
        <p className="italic">None</p>
      )}
    </div>
  );
}

type ChildrenSectionProps = {
  runId: string;
  run: models.Run;
  execution: models.Execution;
};

function ChildrenSection({ runId, run, execution }: ChildrenSectionProps) {
  return (
    <div>
      <h3 className="uppercase text-sm font-bold text-slate-400">Children</h3>
      {execution.children.length ? (
        <ul className="">
          {execution.children.map((child) => {
            if (typeof child == "string") {
              const step = run.steps[child];
              return (
                <li key={child}>
                  <StepLink
                    runId={runId}
                    stepId={child}
                    attempt={1}
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
                    attempt={1}
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
        <p className="italic">None</p>
      )}
    </div>
  );
}

type ResultSectionProps = {
  result: Extract<models.Result, { type: "value" }>;
};

function ResultSection({ result }: ResultSectionProps) {
  const value = result.value;
  return (
    <div>
      <h3 className="uppercase text-sm font-bold text-slate-400">Result</h3>
      {value.type == "raw" ? (
        <div className="bg-white rounded block p-1 border border-slate-300 break-all whitespace-break-spaces text-sm">
          {" "}
          <Value value={value} />
        </div>
      ) : value.type == "blob" ? (
        <BlobLink value={value} />
      ) : undefined}
    </div>
  );
}

type ErrorSectionProps = {
  result: Extract<models.Result, { type: "error" }>;
};

function ErrorSection({ result }: ErrorSectionProps) {
  const error = result.error;
  return (
    <div>
      <h3 className="uppercase text-sm font-bold text-slate-400">Result</h3>
      <div className="p-2 mt-2 rounded bg-red-50 border border-red-200 overflow-x-auto">
        <p className="mb-2">
          <span className="font-mono font-bold">{error.type}</span>:{" "}
          <span>{error.message}</span>
        </p>
        <ol>
          {error.frames.map((frame, index) => (
            <li key={index}>
              <p className="text-xs whitespace-nowrap">
                File "<span title={frame.file}>{truncatePath(frame.file)}</span>
                ", line {frame.line}, in{" "}
                <span className="font-mono">{frame.name}</span>
              </p>
              {frame.code && (
                <pre className="font-mono ml-2 text-sm">
                  <code>{frame.code}</code>
                </pre>
              )}
            </li>
          ))}
        </ol>
      </div>
    </div>
  );
}

type DeferredSectionProps = {
  execution: models.Execution;
};

function DeferredSection({ execution }: DeferredSectionProps) {
  const scheduledAt = DateTime.fromMillis(
    execution.executeAfter || execution.createdAt,
  );
  const completedAt =
    execution.completedAt !== null
      ? DateTime.fromMillis(execution.completedAt)
      : null;
  const result = execution.result as Extract<
    models.Result,
    { type: "deferred" }
  >;
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
            attempt={result.execution.attempt}
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

type CachedSectionProps = {
  result: Extract<models.Result, { type: "cached" }>;
};

function CachedSection({ result }: CachedSectionProps) {
  return (
    <div>
      <h3 className="uppercase text-sm font-bold text-slate-400">Cached</h3>
      <p>
        To:{" "}
        <StepLink
          runId={result.execution.runId}
          stepId={result.execution.stepId}
          attempt={result.execution.attempt}
          className="rounded text-sm ring-offset-1 px-1"
          hoveredClassName="ring-2 ring-slate-300"
        >
          <span className="font-mono">{result.execution.target}</span>{" "}
          <span className="text-slate-500">
            ({result.execution.repository})
          </span>
        </StepLink>
      </p>
    </div>
  );
}

type AssetItemProps = {
  asset: models.Asset;
};

function AssetItem({ asset }: AssetItemProps) {
  return (
    <li className="block my-1">
      <AssetLink
        asset={asset}
        className="flex items-start gap-1 rounded hover:bg-white/50 p-1"
      >
        <AssetIcon asset={asset} size={18} className="mt-1" />
        <span className="flex flex-col">
          <span className="">
            {truncatePath(asset.path) + (asset.type == 1 ? "/" : "")}
          </span>
          <span className="text-slate-500 text-xs">
            {getAssetMetadata(asset).join(", ")}
          </span>
        </span>
      </AssetLink>
    </li>
  );
}

type AssetsSectionProps = {
  execution: models.Execution;
};

function AssetsSection({ execution }: AssetsSectionProps) {
  return (
    <div>
      <h3 className="uppercase text-sm font-bold text-slate-400">Assets</h3>
      {Object.keys(execution.assets).length ? (
        <ul>
          {Object.entries(execution.assets).map(([assetId, asset]) => (
            <AssetItem key={assetId} asset={asset} />
          ))}
        </ul>
      ) : (
        <p className="italic">None</p>
      )}
    </div>
  );
}

type LogsSectionProps = {
  projectId: string;
  runId: string;
  execution: models.Execution;
  activeEnvironmentId: string;
};

function LogsSection({
  projectId,
  runId,
  execution,
  activeEnvironmentId,
}: LogsSectionProps) {
  const logs = useLogs(projectId, runId, activeEnvironmentId);
  const executionLogs =
    logs && logs.filter((l) => l[0] == execution.executionId);
  const scheduledAt = DateTime.fromMillis(
    execution.executeAfter || execution.createdAt,
  );
  return (
    <div>
      <h3 className="uppercase text-sm font-bold text-slate-400">Logs</h3>
      {executionLogs === undefined ? (
        <Loading />
      ) : (
        <div className="overflow-x-auto">
          <RunLogs
            startTime={scheduledAt}
            logs={executionLogs}
            darkerTimestampRule={true}
          />
        </div>
      )}
    </div>
  );
}

type Props = {
  runId: string;
  stepId: string;
  attempt: number;
  run: models.Run;
  projectId: string;
  activeEnvironmentId: string;
  runEnvironmentId: string;
  className?: string;
  style?: CSSProperties;
  onRerunStep: (stepId: string, environmentName: string) => Promise<any>;
};

export default function StepDetail({
  runId,
  stepId,
  attempt,
  run,
  projectId,
  activeEnvironmentId,
  runEnvironmentId,
  className,
  style,
  onRerunStep,
}: Props) {
  const step = run.steps[stepId];
  const execution = step.executions[attempt];
  return (
    <div
      className={classNames("overflow-hidden flex flex-col", className)}
      style={style}
    >
      <Header
        projectId={projectId}
        activeEnvironmentId={activeEnvironmentId}
        runEnvironmentId={runEnvironmentId}
        run={run}
        stepId={stepId}
        step={step}
        attempt={attempt}
        onRerunStep={onRerunStep}
      />
      <div className="flex flex-col overflow-auto p-4 gap-5">
        {step.arguments?.length > 0 && (
          <ArgumentsSection arguments_={step.arguments} />
        )}
        {execution && <ExecutionSection execution={execution} />}
        {execution?.assignedAt && (
          <Fragment>
            <DependenciesSection execution={execution} />
            <ChildrenSection runId={runId} run={run} execution={execution} />
          </Fragment>
        )}
        {execution?.result?.type == "value" ? (
          <ResultSection result={execution.result} />
        ) : execution?.result?.type == "error" ? (
          <ErrorSection result={execution.result} />
        ) : execution?.result?.type == "deferred" ? (
          <DeferredSection execution={execution} />
        ) : execution?.result?.type == "cached" ? (
          <CachedSection result={execution.result} />
        ) : undefined}
        {execution?.assignedAt && (
          <Fragment>
            <AssetsSection execution={execution} />
            <LogsSection
              projectId={projectId}
              runId={runId}
              execution={execution}
              activeEnvironmentId={activeEnvironmentId}
            />
          </Fragment>
        )}
      </div>
    </div>
  );
}

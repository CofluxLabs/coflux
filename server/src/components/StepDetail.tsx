import {
  CSSProperties,
  ComponentProps,
  Fragment,
  ReactNode,
  useCallback,
  useState,
} from "react";
import classNames from "classnames";
import { minBy, sortBy } from "lodash";
import { DateTime } from "luxon";
import {
  Menu,
  MenuButton,
  MenuItem,
  MenuItems,
  Popover,
  PopoverBackdrop,
  PopoverButton,
  PopoverPanel,
} from "@headlessui/react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import {
  IconChevronDown,
  IconChevronLeft,
  IconChevronRight,
  IconFunction,
  IconPinned,
  IconReload,
  IconWindowMaximize,
  IconWindowMinimize,
  IconX,
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
import Tabs, { Tab } from "./common/Tabs";
import Select from "./common/Select";

function getRunEnvironmentId(run: models.Run) {
  const initialStepId = minBy(
    Object.keys(run.steps).filter((id) => !run.steps[id].parentId),
    (stepId) => run.steps[stepId].createdAt,
  )!;
  return run.steps[initialStepId].executions[1].environmentId;
}

type ExecutionStatusProps = {
  execution: models.Execution;
};

function ExecutionStatus({ execution }: ExecutionStatusProps) {
  return execution.result?.type == "cached" ? (
    <Badge intent="none" label="Cached" />
  ) : execution.result?.type == "deferred" ? (
    <Badge intent="none" label="Deferred" />
  ) : execution.result?.type == "value" ? (
    <Badge intent="success" label="Completed" />
  ) : execution.result?.type == "error" ? (
    <Badge intent="danger" label="Failed" />
  ) : execution.result?.type == "abandoned" ? (
    <Badge intent="warning" label="Abandoned" />
  ) : execution.result?.type == "suspended" ? (
    <Badge intent="warning" label="Suspended" />
  ) : execution.result?.type == "cancelled" ? (
    <Badge intent="warning" label="Cancelled" />
  ) : !execution.assignedAt ? (
    <Badge intent="info" label="Assigning" />
  ) : !execution.result ? (
    <Badge intent="info" label="Running" />
  ) : null;
}

function getNextPrevious(
  attempts: number[],
  selected: number,
  direction: "next" | "previous",
) {
  const index = attempts.indexOf(selected);
  if (index >= 0) {
    if (direction == "next") {
      if (index < attempts.length - 1) {
        return attempts[index + 1];
      }
    } else {
      if (index > 0) {
        return attempts[index - 1];
      }
    }
  }

  return null;
}

type NextPreviousButtonProps = {
  direction: "next" | "previous";
  activeEnvironmentName: string | undefined;
  stepId: string;
  currentAttempt: number;
  executions: Record<number, models.Execution>;
  activeTab: number;
  maximised: boolean;
};

function NextPreviousButton({
  direction,
  activeEnvironmentName,
  stepId,
  currentAttempt,
  executions,
  activeTab,
  maximised,
}: NextPreviousButtonProps) {
  const location = useLocation();
  const attempts = Object.keys(executions)
    .map((a) => parseInt(a, 10))
    .sort((a, b) => a - b);
  const attempt = getNextPrevious(attempts, currentAttempt, direction);
  const Icon = direction == "next" ? IconChevronRight : IconChevronLeft;
  const className = classNames(
    "p-1 bg-white border border-slate-300 flex items-center",
    attempt ? "hover:bg-slate-100 text-slate-500" : "text-slate-200",
    direction == "next" ? "rounded-r-md -ml-px" : "rounded-l-md -mr-px",
  );
  if (attempt) {
    return (
      <Link
        to={buildUrl(location.pathname, {
          environment: activeEnvironmentName,
          step: stepId,
          attempt,
          tab: activeTab,
          maximised: maximised ? "true" : undefined,
        })}
        className={className}
      >
        <Icon size={16} />
      </Link>
    );
  } else {
    return (
      <span className={className}>
        <Icon size={16} />
      </span>
    );
  }
}

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
      <ExecutionStatus execution={execution} />
    </div>
  );
}

type AttemptSelectorProps = {
  selected: number;
  activeEnvironmentName: string | undefined;
  stepId: string;
  activeTab: number;
  maximised: boolean;
  executions: Record<number, models.Execution>;
};

function AttemptSelector({
  selected,
  activeEnvironmentName,
  stepId,
  activeTab,
  maximised,
  executions,
}: AttemptSelectorProps) {
  const selectedExecution = executions[selected];
  return (
    <div className="flex shadow-sm">
      <NextPreviousButton
        direction="previous"
        activeEnvironmentName={activeEnvironmentName}
        stepId={stepId}
        currentAttempt={selected}
        executions={executions}
        activeTab={activeTab}
        maximised={maximised}
      />
      <Menu>
        <MenuButton className="flex items-center gap-1 p-1 pl-2 bg-white text-left text-slate-600 border border-slate-300 ">
          {selectedExecution && (
            <AttemptSelectorOption
              attempt={selected}
              execution={selectedExecution}
            />
          )}
          <IconChevronDown size={16} className="opacity-40" />
        </MenuButton>
        <MenuItems
          transition
          className="p-1 overflow-auto bg-white rounded shadow-lg transition duration-100 ease-out data-[closed]:opacity-0"
          anchor={{ to: "bottom start", gap: 2, padding: 20 }}
        >
          {sortBy(Object.entries(executions), "attempt").map(
            ([attempt_, execution]) => {
              const attempt = parseInt(attempt_, 10);
              return (
                <MenuItem key={attempt}>
                  <Link
                    to={buildUrl(location.pathname, {
                      environment: activeEnvironmentName,
                      step: stepId,
                      attempt,
                      tab: activeTab,
                      maximised: maximised ? "true" : undefined,
                    })}
                    className={classNames(
                      "p-1 cursor-pointer rounded flex items-center gap-1 data-[active]:bg-slate-100",
                      attempt == selected && "font-bold",
                    )}
                  >
                    <AttemptSelectorOption
                      attempt={attempt}
                      execution={execution}
                    />
                  </Link>
                </MenuItem>
              );
            },
          )}
        </MenuItems>
      </Menu>
      <NextPreviousButton
        direction="next"
        activeEnvironmentName={activeEnvironmentName}
        stepId={stepId}
        currentAttempt={selected}
        executions={executions}
        activeTab={activeTab}
        maximised={maximised}
      />
    </div>
  );
}

function getEnvironmentDescendantIds(
  environments: Record<string, models.Environment>,
  parentId: string | null,
): string[] {
  return Object.entries(environments)
    .filter(([_, e]) => e.baseId == parentId && e.status != 2)
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

type RerunButtonProps = {
  run: models.Run;
  stepId: string;
  step: models.Step;
  executionEnvironmentId: string;
  environments: Record<string, models.Environment> | undefined;
  onRerunStep: (stepId: string, environmentName: string) => Promise<any>;
};

function RerunButton({
  run,
  stepId,
  step,
  executionEnvironmentId,
  environments,
  onRerunStep,
}: RerunButtonProps) {
  const [rerunning, setRerunning] = useState(false);
  const baseEnvironmentId = getBaseExecution(step, run).environmentId;
  const [environmentId, setEnvironmentId] = useState<string | null>(
    executionEnvironmentId,
  );
  const childEnvironmentIds =
    environments && getEnvironmentOptions(environments, baseEnvironmentId);
  const environmentOptions = (childEnvironmentIds || []).reduce(
    (acc, environmentId) => ({
      ...acc,
      [environmentId]: environments![environmentId].name,
    }),
    {},
  );
  const handleRerunClick = useCallback(
    (close: () => void) => {
      const environmentName =
        environments![environmentId || baseEnvironmentId].name;
      setRerunning(true);
      onRerunStep(stepId, environmentName).finally(() => {
        setRerunning(false);
        close();
      });
    },
    [environments, environmentId, onRerunStep, stepId],
  );
  return (
    <div className="flex shadow-sm relative">
      <Popover>
        <PopoverButton
          as={Button}
          disabled={rerunning}
          size="sm"
          className="whitespace-nowrap"
          left={<IconReload size={14} className="shrink-0" />}
          right={<IconChevronDown size={16} className="shrink-0" />}
        >
          Re-run
        </PopoverButton>
        <PopoverBackdrop className="fixed inset-0 bg-black/15" />
        <PopoverPanel
          transition
          anchor={{ to: "bottom end", gap: 10, offset: 20 }}
          className="bg-white shadow-xl rounded-lg p-2 !overflow-visible min-w-[300px]"
        >
          {({ close }) => (
            <>
              <div className="absolute border-b-[10px] border-b-white border-x-transparent border-x-[10px] top-[-10px] right-[30px] w-[20px] h-[10px]"></div>
              <div className="flex items-center gap-1">
                <Select
                  options={environmentOptions}
                  value={environmentId}
                  onChange={setEnvironmentId}
                  className="flex-1"
                />
                <Button
                  disabled={rerunning}
                  onClick={() => handleRerunClick(close)}
                >
                  Re-run
                </Button>
              </div>
            </>
          )}
        </PopoverPanel>
      </Popover>
    </div>
  );
}

type HeaderProps = {
  projectId: string;
  activeEnvironmentId: string;
  runEnvironmentId: string;
  run: models.Run;
  stepId: string;
  step: models.Step;
  attempt: number;
  environments: Record<string, models.Environment> | undefined;
  activeTab: number;
  maximised: boolean;
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
  environments,
  activeTab,
  maximised,
  onRerunStep,
}: HeaderProps) {
  const activeEnvironmentName = environments?.[activeEnvironmentId].name;
  const navigate = useNavigate();
  const location = useLocation();
  const changeAttempt = useCallback(
    (attempt: number, environmentName?: string) => {
      navigate(
        buildUrl(location.pathname, {
          environment: environmentName || activeEnvironmentName,
          step: stepId,
          attempt,
          tab: activeTab,
          maximised: maximised ? "true" : undefined,
        }),
      );
    },
    [stepId, activeEnvironmentName, navigate, location, activeTab, maximised],
  );
  const handleRerunStep = useCallback(
    (stepId: string, environmentName: string) => {
      return onRerunStep(stepId, environmentName).then(({ attempt }) => {
        // TODO: wait for attempt to be synced to topic
        changeAttempt(attempt, environmentName);
      });
    },
    [changeAttempt],
  );
  const executionEnvironmentId = step.executions[attempt]?.environmentId;
  const handleMaximiseClick = useCallback(() => {
    navigate(
      buildUrl(location.pathname, {
        environment: activeEnvironmentName,
        step: stepId,
        attempt,
        tab: activeTab,
        maximised: maximised ? undefined : "true",
      }),
    );
  }, [
    navigate,
    location,
    activeEnvironmentName,
    stepId,
    attempt,
    activeTab,
    maximised,
  ]);
  const handleCloseClick = useCallback(() => {
    navigate(
      buildUrl(location.pathname, {
        environment: activeEnvironmentName,
      }),
    );
  }, [navigate, location, activeEnvironmentName]);
  return (
    <div className="p-4 flex items-start">
      <div className="flex-1 flex flex-col gap-2">
        <div className="flex justify-between items-start gap-2">
          <div className="flex items-center gap-2">
            <div className="flex items-baseline flex-wrap gap-1 leading-tight">
              <div className="flex items-baseline gap-1">
                <span className="text-slate-400 text-sm">
                  {step.repository}
                </span>
                <span className="text-slate-400">/</span>
              </div>
              <span className="flex items-baseline gap-1">
                <h2
                  className={classNames(
                    "font-mono",
                    !step.parentId && "font-bold",
                  )}
                >
                  {step.target}
                </h2>
                {step.isMemoised && (
                  <span
                    className="text-slate-500 self-center"
                    title="This execution has been memoised"
                  >
                    <IconPinned size={16} />
                  </span>
                )}
              </span>
            </div>
          </div>
          <div className="flex items-center gap-1">
            <RerunButton
              run={run}
              stepId={stepId}
              step={step}
              executionEnvironmentId={executionEnvironmentId}
              environments={environments}
              onRerunStep={handleRerunStep}
            />
            <Button
              size="sm"
              outline={true}
              variant="secondary"
              title={maximised ? "Pop-in details" : "Pop-out details"}
              onClick={handleMaximiseClick}
            >
              {maximised ? (
                <IconWindowMinimize size={14} />
              ) : (
                <IconWindowMaximize size={14} />
              )}
            </Button>
            <Button
              size="sm"
              outline={true}
              variant="secondary"
              title="Hide details"
              onClick={handleCloseClick}
            >
              <IconX size={14} />
            </Button>
          </div>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <AttemptSelector
            selected={attempt}
            activeEnvironmentName={activeEnvironmentName}
            stepId={stepId}
            activeTab={activeTab}
            maximised={maximised}
            executions={step.executions}
          />
          {executionEnvironmentId != runEnvironmentId && (
            <EnvironmentLabel
              projectId={projectId}
              environmentId={executionEnvironmentId}
              warning="This execution ran in a different environment"
            />
          )}
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
        target="_blank"
      >
        Blob
      </a>
      <span className="text-slate-500 text-xs ml-1">({hints.join("; ")})</span>
    </span>
  );
}

type ValueProps = {
  value: Extract<models.Value, { type: "raw" }>;
  projectId: string;
  className?: string;
};

function Value({ value, projectId, className }: ValueProps) {
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
                projectId={projectId}
                assetId={placeholder.assetId}
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
  projectId: string;
};

function Argument({ argument, projectId }: ArgumentProps) {
  switch (argument.type) {
    case "raw":
      return (
        <Value
          value={argument}
          projectId={projectId}
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
  projectId: string;
};

function ArgumentsSection({ arguments_, projectId }: ArgumentsSectionProps) {
  return (
    <div>
      <h3 className="uppercase text-sm font-bold text-slate-400">Arguments</h3>
      <ol className="list-decimal list-inside ml-1 marker:text-slate-400 marker:text-xs space-y-1">
        {arguments_.map((argument, index) => (
          <li key={index}>
            <Argument argument={argument} projectId={projectId} />
          </li>
        ))}
      </ol>
    </div>
  );
}

function interpolate(
  items: ReactNode[],
  separator: (i: number) => ReactNode,
): ReactNode[] {
  return items.flatMap((item, i) => (i > 0 ? [separator(i), item] : [item]));
}

type RequiresSectionProps = {
  requires: Record<string, string[]>;
};

function RequiresSection({ requires }: RequiresSectionProps) {
  return (
    <div>
      <h3 className="uppercase text-sm font-bold text-slate-400">Requires</h3>
      <ul className="list-disc ml-5 marker:text-slate-600">
        {Object.entries(requires).map(([key, values]) => (
          <li key={key}>
            {interpolate(
              values.map((v) => (
                <span key={v} className="rounded bg-slate-300/50 px-1 text-sm">
                  <span className="text-slate-500">{key}</span>: {v}
                </span>
              )),
              (i) => (
                <span key={i} className="text-slate-500 text-sm">
                  {" / "}
                </span>
              ),
            )}
          </li>
        ))}
      </ul>
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
    <>
      <div>
        <h3 className="uppercase text-sm font-bold text-slate-400">
          Scheduled
        </h3>
        <p>{scheduledAt.toLocaleString(DateTime.DATETIME_FULL_WITH_SECONDS)}</p>
      </div>
      <div>
        {assignedAt && completedAt ? (
          <>
            <h3 className="uppercase text-sm font-bold text-slate-400">
              Duration
            </h3>
            <p>
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
          </>
        ) : assignedAt ? (
          <p>Executing...</p>
        ) : null}
      </div>
    </>
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

function findExecution(
  run: models.Run,
  executionId: string | null,
): [string, number] | undefined {
  if (executionId) {
    const stepId = Object.keys(run.steps).find((sId) =>
      Object.values(run.steps[sId].executions).some(
        (e) => e.executionId == executionId,
      ),
    );
    if (stepId) {
      const step = run.steps[stepId];
      const attempt = Object.keys(run.steps[stepId].executions).find(
        (a) => step.executions[a].executionId == executionId,
      );
      if (attempt) {
        return [stepId, parseInt(attempt, 10)];
      }
    }
  }
  return undefined;
}

type RelationsSectionProps = {
  runId: string;
  run: models.Run;
  step: models.Step;
  execution: models.Execution;
};

function RelationsSection({
  runId,
  run,
  step,
  execution,
}: RelationsSectionProps) {
  const parent = findExecution(run, step.parentId);
  return (
    <>
      <div>
        <h3 className="uppercase text-sm font-bold text-slate-400">Parent</h3>
        {parent ? (
          <StepLink
            runId={runId}
            stepId={parent[0]}
            attempt={parent[1]}
            className="rounded text-sm ring-offset-1 px-1"
            hoveredClassName="ring-2 ring-slate-300"
          >
            <span className="font-mono">{step.target}</span>{" "}
            <span className="text-slate-500">({step.repository})</span>
          </StepLink>
        ) : (
          <p className="italic">None</p>
        )}
      </div>
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
                      attempt={1}
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
          <p className="italic">None</p>
        )}
      </div>
    </>
  );
}

type ResultSectionProps = {
  result: Extract<models.Result, { type: "value" }>;
  projectId: string;
};

function ResultSection({ result, projectId }: ResultSectionProps) {
  const value = result.value;
  return (
    <div>
      <h3 className="uppercase text-sm font-bold text-slate-400">Result</h3>
      {value.type == "raw" ? (
        <div className="bg-white rounded block p-1 border border-slate-300 break-all whitespace-break-spaces text-sm">
          {" "}
          <Value value={value} projectId={projectId} />
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
  projectId: string;
  assetId: string;
};

function AssetItem({ asset, projectId, assetId }: AssetItemProps) {
  return (
    <li className="block my-1">
      <AssetLink
        projectId={projectId}
        assetId={assetId}
        asset={asset}
        className="flex items-start gap-1 rounded hover:bg-white/50 p-1"
      >
        <AssetIcon asset={asset} size={18} className="mt-1 shrink-0" />
        <span className="flex flex-col min-w-0">
          <span className="text-ellipsis overflow-hidden whitespace-nowrap">
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
  projectId: string;
};

function AssetsSection({ execution, projectId }: AssetsSectionProps) {
  return (
    <div>
      <h3 className="uppercase text-sm font-bold text-slate-400">Assets</h3>
      {Object.keys(execution.assets).length ? (
        <ul>
          {Object.entries(execution.assets).map(([assetId, asset]) => (
            <AssetItem
              key={assetId}
              asset={asset}
              projectId={projectId}
              assetId={assetId}
            />
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

function StepDetailTab({ className, ...props }: ComponentProps<typeof Tab>) {
  return (
    <Tab
      className={classNames(
        "flex-1 overflow-auto flex flex-col gap-4 p-4",
        className,
      )}
      {...props}
    />
  );
}

type Props = {
  runId: string;
  stepId: string;
  attempt: number;
  run: models.Run;
  projectId: string;
  activeEnvironmentId: string;
  className?: string;
  style?: CSSProperties;
  onRerunStep: (stepId: string, environmentName: string) => Promise<any>;
  activeTab: number;
  maximised: boolean;
};

export default function StepDetail({
  runId,
  stepId,
  attempt,
  run,
  projectId,
  activeEnvironmentId,
  className,
  style,
  onRerunStep,
  activeTab,
  maximised,
}: Props) {
  const step = run.steps[stepId];
  const execution: models.Execution | undefined = step.executions[attempt];
  const runEnvironmentId = getRunEnvironmentId(run);
  const navigate = useNavigate();
  const location = useLocation();
  const environments = useEnvironments(projectId);
  const activeEnvironmentName = environments?.[activeEnvironmentId].name;
  const handleTabChange = useCallback(
    (tab: number) => {
      navigate(
        buildUrl(location.pathname, {
          environment: activeEnvironmentName,
          step: stepId,
          attempt,
          tab,
          maximised: maximised ? "true" : undefined,
        }),
      );
    },
    [navigate, location, activeEnvironmentName, stepId, attempt],
  );
  return (
    <div className={classNames("flex flex-col", className)} style={style}>
      <Header
        projectId={projectId}
        activeEnvironmentId={activeEnvironmentId}
        runEnvironmentId={runEnvironmentId}
        run={run}
        stepId={stepId}
        step={step}
        attempt={attempt}
        environments={environments}
        onRerunStep={onRerunStep}
        activeTab={activeTab}
        maximised={maximised}
      />
      <Tabs
        className={"flex-1 flex flex-col min-h-0"}
        selectedIndex={activeTab}
        onChange={handleTabChange}
      >
        <StepDetailTab label="Overview">
          {step.arguments?.length > 0 && (
            <ArgumentsSection
              arguments_={step.arguments}
              projectId={projectId}
            />
          )}
          {Object.keys(step.requires).length > 0 && (
            <RequiresSection requires={step.requires} />
          )}
          {execution?.result?.type == "value" ? (
            <ResultSection result={execution.result} projectId={projectId} />
          ) : execution?.result?.type == "error" ? (
            <ErrorSection result={execution.result} />
          ) : execution?.result?.type == "deferred" ? (
            <DeferredSection execution={execution} />
          ) : execution?.result?.type == "cached" ? (
            <CachedSection result={execution.result} />
          ) : undefined}
          {/* TODO: 'suspended' section? */}
          {execution && Object.keys(execution.assets).length > 0 && (
            <AssetsSection execution={execution} projectId={projectId} />
          )}
        </StepDetailTab>
        <StepDetailTab label="Timing">
          {execution && <ExecutionSection execution={execution} />}
        </StepDetailTab>
        <StepDetailTab label="Connections" disabled={!execution?.assignedAt}>
          {execution?.assignedAt && (
            <Fragment>
              <RelationsSection
                runId={runId}
                run={run}
                step={step}
                execution={execution}
              />
              <DependenciesSection execution={execution} />
            </Fragment>
          )}
        </StepDetailTab>
        <StepDetailTab label="Logs" disabled={!execution?.assignedAt}>
          {execution?.assignedAt && (
            <LogsSection
              projectId={projectId}
              runId={runId}
              execution={execution}
              activeEnvironmentId={activeEnvironmentId}
            />
          )}
        </StepDetailTab>
      </Tabs>
    </div>
  );
}

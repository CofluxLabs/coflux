import { Fragment } from "react";
import { DateTime } from "luxon";
import classNames from "classnames";
import { maxBy, sortBy } from "lodash";

import * as models from "../models";
import useNow from "../hooks/useNow";
import StepLink from "./StepLink";

function loadExecutionTimes(run: models.Run): {
  [key: string]: [DateTime, DateTime | null, DateTime | null];
} {
  return Object.keys(run.steps).reduce((times, stepId) => {
    const step = run.steps[stepId];
    return Object.values(step.executions).reduce((times, attempt) => {
      return {
        ...times,
        [`${stepId}:${attempt.sequence}`]: [
          DateTime.fromMillis(attempt.createdAt),
          attempt.assignedAt ? DateTime.fromMillis(attempt.assignedAt) : null,
          attempt.completedAt ? DateTime.fromMillis(attempt.completedAt) : null,
        ],
      };
    }, times);
  }, {});
}

function loadStepTimes(run: models.Run): { [key: string]: DateTime } {
  return Object.keys(run.steps).reduce(
    (times, stepId) => ({
      ...times,
      [stepId]: DateTime.fromMillis(run.steps[stepId].createdAt),
    }),
    {}
  );
}

function percentage(value: number) {
  return `${(value * 100).toFixed(2)}%`;
}

type BarProps = {
  x0: DateTime;
  x1: DateTime;
  x2: DateTime;
  d: number;
  className: string;
};

function Bar({ x1, x2, x0, d, className }: BarProps) {
  const left = x1.diff(x0).toMillis() / d;
  const width = Math.max(0.001, x2.diff(x1).toMillis() / d);
  const style = { left: percentage(left), width: percentage(width) };
  return (
    <div
      className={classNames("absolute h-2 rounded", className)}
      style={style}
    ></div>
  );
}

function classNameForResult(result: models.Result | null) {
  if (!result) {
    return "bg-blue-300";
  } else if (["reference", "raw", "blob"].includes(result.type)) {
    return "bg-green-300";
  } else if (result.type == "error") {
    return "bg-red-300";
  } else {
    return "bg-yellow-300";
  }
}

function isRunning(run: models.Run) {
  return Object.values(run.steps).some((step) =>
    Object.values(step.executions).some((a) => !a.result)
  );
}

function formatElapsed(millis: number) {
  if (millis < 500) {
    return `${millis}ms`;
  } else {
    return `${(millis / 1000).toFixed(1)}s`;
  }
}

type Props = {
  runId: string;
  run: models.Run;
};

export default function RunTimeline({ runId, run }: Props) {
  const running = isRunning(run);
  const now = useNow(running ? 30 : 0);
  const stepTimes = loadStepTimes(run);
  const executionTimes = loadExecutionTimes(run);
  const times = [
    ...Object.values(stepTimes),
    ...Object.values(executionTimes)
      .flat()
      .filter((t): t is DateTime => t !== null),
  ];
  const earliestTime = DateTime.min(...times);
  const latestTime = running
    ? DateTime.fromJSDate(now)
    : DateTime.max(...times);
  const totalMillis = latestTime.diff(earliestTime).toMillis();
  const stepIds = sortBy(
    Object.keys(run.steps).filter((id) => !run.steps[id].cachedExecutionId),
    (id) => run.steps[id].createdAt
  );
  return (
    <div className="p-4">
      <div className="flex relative">
        <div className="w-40 truncate self-center mr-2"></div>
        <div className="flex-1 text-right text-slate-400">
          {formatElapsed(totalMillis)}
        </div>
      </div>
      {stepIds.map((stepId) => {
        const step = run.steps[stepId];
        const latestAttempt = maxBy(Object.values(step.executions), "sequence");
        const stepFinishedAt =
          (latestAttempt
            ? executionTimes[`${stepId}:${latestAttempt.sequence}`][2]
            : null) || latestTime;
        return (
          <div
            key={stepId}
            className="flex items-center border-r border-slate-200"
          >
            <div className="w-40 mr-2 border-r border-slate-200 py-1">
              <StepLink
                runId={runId}
                stepId={stepId}
                attemptNumber={latestAttempt?.sequence}
                className="block max-w-full rounded truncate leading-none text-sm ring-offset-1"
                activeClassName="ring-2 ring-cyan-400"
                hoveredClassName="ring-2 ring-slate-300"
              >
                <span className="font-mono">{step.target}</span>{" "}
                <span className="text-slate-500 text-sm">
                  ({step.repository})
                </span>
              </StepLink>
            </div>
            <div className="flex-1 relative">
              <StepLink
                runId={runId}
                stepId={stepId}
                attemptNumber={latestAttempt?.sequence}
                className="block h-2"
              >
                <Bar
                  x1={stepTimes[stepId]}
                  x2={stepFinishedAt}
                  x0={earliestTime}
                  d={totalMillis}
                  className="bg-slate-100"
                />
                {Object.values(step.executions).map((attempt) => {
                  const [createdAt, assignedAt, resultAt] =
                    executionTimes[`${stepId}:${attempt.sequence}`];
                  return (
                    <Fragment key={attempt.sequence}>
                      <Bar
                        x1={createdAt}
                        x2={stepFinishedAt}
                        x0={earliestTime}
                        d={totalMillis}
                        className="bg-slate-200"
                      />
                      {assignedAt && (
                        <Bar
                          x1={assignedAt}
                          x2={resultAt || latestTime}
                          x0={earliestTime}
                          d={totalMillis}
                          className={classNameForResult(attempt.result)}
                        />
                      )}
                    </Fragment>
                  );
                })}
              </StepLink>
            </div>
          </div>
        );
      })}
    </div>
  );
}

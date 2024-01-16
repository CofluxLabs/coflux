import { CSSProperties } from "react";
import { DateTime } from "luxon";
import classNames from "classnames";
import { maxBy, sortBy } from "lodash";

import * as models from "../models";
import useNow from "../hooks/useNow";
import StepLink from "./StepLink";
import { formatDiff } from "../utils";

function loadExecutionTimes(run: models.Run): {
  [key: string]: [DateTime, DateTime | null, DateTime | null];
} {
  return Object.keys(run.steps).reduce((times, stepId) => {
    const step = run.steps[stepId];
    return Object.values(step.executions).reduce((times, attempt) => {
      return {
        ...times,
        [`${stepId}:${attempt.sequence}`]: [
          DateTime.fromMillis(attempt.executeAfter || attempt.createdAt),
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
    {},
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
  className?: string;
  style?: CSSProperties;
};

function Bar({ x1, x2, x0, d, className, style }: BarProps) {
  const left = x1.diff(x0).toMillis() / d;
  const width = x2.diff(x1).toMillis() / d;
  return (
    <div
      className={classNames("absolute h-full rounded -ml-2", className)}
      style={{
        ...style,
        left: percentage(left),
        width: `calc(${percentage(width)} + 0.5rem)`,
      }}
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
    Object.values(step.executions).some((a) => !a.result),
  );
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
  const latestTime = running ? now : DateTime.max(...times);
  const elapsedDiff = latestTime.diff(earliestTime, [
    "days",
    "hours",
    "minutes",
    "seconds",
    "milliseconds",
  ]);
  const totalMillis = elapsedDiff.toMillis();
  const stepIds = sortBy(
    Object.keys(run.steps).filter((id) => !run.steps[id].cachedExecutionId),
    (id) => run.steps[id].createdAt,
  );
  return (
    <div className="px-4">
      <div className="flex text-slate-400 text-sm  sticky top-0 z-10">
        <div className="w-40"></div>
        <div className="flex-1 ml-2 flex border-x border-slate-200 px-1 py-2 bg-white/90">
          <div className="flex-1">
            {earliestTime.toLocaleString(DateTime.DATETIME_FULL_WITH_SECONDS)}
          </div>
          <div>
            <span
              title={latestTime.toLocaleString(
                DateTime.DATETIME_FULL_WITH_SECONDS,
              )}
            >
              +{formatDiff(elapsedDiff)}
            </span>
          </div>
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
          <div key={stepId} className="flex">
            <div className="w-40 py-0.5">
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
            <div className="flex-1 flex ml-2 pl-3 pr-1 border-x border-slate-200">
              <div className="flex-1 flex items-center">
                <div className="flex-1 relative h-2">
                  <Bar
                    x1={stepTimes[stepId]}
                    x2={stepFinishedAt}
                    x0={earliestTime}
                    d={totalMillis}
                    style={{ boxShadow: "inset 0 0 3px rgb(226, 232, 240)" }}
                  />
                  {Object.values(step.executions)
                    .reverse()
                    .map((attempt) => {
                      const [executeAt, assignedAt, resultAt] =
                        executionTimes[`${stepId}:${attempt.sequence}`];
                      return (
                        <StepLink
                          runId={runId}
                          stepId={stepId}
                          attemptNumber={attempt.sequence}
                          key={attempt.sequence}
                        >
                          <Bar
                            x1={executeAt}
                            x2={resultAt || latestTime}
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
                        </StepLink>
                      );
                    })}
                </div>
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

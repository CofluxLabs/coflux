import { Fragment, ReactNode } from "react";
import { sortBy } from "lodash";
import { DateTime, Duration, DurationObjectUnits } from "luxon";
import classNames from "classnames";
import {
  IconAlertHexagon,
  IconAlertTriangle,
  IconInfoCircle,
} from "@tabler/icons-react";

import * as models from "../models";
import { pluralise } from "../utils";

const DIFF_UNITS: Partial<Record<keyof DurationObjectUnits, string>> = {
  days: "day",
  hours: "hour",
  minutes: "minute",
  seconds: "second",
  milliseconds: "millisecond",
};

function formatDiff(diff: Duration) {
  const parts = diff.toObject();
  const units = (Object.keys(DIFF_UNITS) as (keyof DurationObjectUnits)[])
    .filter((unit) => unit != "milliseconds" && parts[unit])
    .slice(0, 2);
  if (units.length) {
    return units
      .map((unit) => pluralise(Math.floor(parts[unit]!), DIFF_UNITS[unit]!))
      .join(", ");
  } else {
    return pluralise(Math.floor(diff.toMillis()), "millisecond");
  }
}

function classForLevel(level: models.LogMessageLevel) {
  switch (level) {
    case 1:
      return "text-slate-600 font-mono text-sm";
    case 3:
      return "text-red-800 font-mono text-sm";
    default:
      return null;
  }
}

function iconForLevel(
  level: models.LogMessageLevel,
  className: string,
  size = 18
) {
  switch (level) {
    case 2:
      return (
        <IconInfoCircle
          size={size}
          className={classNames(className, "text-blue-400")}
        />
      );
    case 4:
      return (
        <IconAlertTriangle
          size={size}
          className={classNames(className, "text-yellow-600")}
        />
      );
    case 5:
      return (
        <IconAlertHexagon
          size={size}
          className={classNames(className, "text-red-600")}
        />
      );
    default:
      return null;
  }
}

type LogMessageProps = {
  level: models.LogMessageLevel;
  content: string;
  className?: string;
};

function LogMessage({ level, content, className }: LogMessageProps) {
  return (
    <div className={classNames(className, classForLevel(level))}>
      {iconForLevel(level, "inline-block mr-1 mt-[-2px]")}
      <span className="whitespace-pre-wrap">{content}</span>
    </div>
  );
}

type Props = {
  startTime: DateTime;
  logs: models.LogMessage[];
  darkerTimestampRule?: boolean;
  stepIdentifier?: (executionId: string) => ReactNode;
};

export default function RunLogs({
  startTime,
  logs,
  darkerTimestampRule,
  stepIdentifier,
}: Props) {
  let lastTimestamp = startTime;
  if (logs.length) {
    return (
      <table className="w-full">
        <tbody>
          {sortBy(logs, (l) => l[1]).map((message, index) => {
            const [executionId, timestamp, level, content] = message;
            const createdAt = DateTime.fromMillis(timestamp);
            const diff = createdAt.diff(
              lastTimestamp,
              Object.keys(DIFF_UNITS) as (keyof DurationObjectUnits)[]
            );
            const showTimestamp = index == 0 || diff.toMillis() > 1000;
            if (showTimestamp) {
              lastTimestamp = createdAt;
            }
            return (
              <Fragment key={index}>
                {showTimestamp && (
                  <tr>
                    <td
                      className="py-2 select-none"
                      colSpan={stepIdentifier ? 2 : 1}
                    >
                      <div className="flex items-center">
                        <span
                          className="text-slate-400/70 relative pr-2 text-sm"
                          title={createdAt.toLocaleString(
                            DateTime.DATETIME_SHORT_WITH_SECONDS
                          )}
                        >
                          +{formatDiff(diff)}
                        </span>
                        <span className="flex-1">
                          <span
                            className={classNames(
                              "border-b  mt-1 block",
                              darkerTimestampRule
                                ? "border-slate-200"
                                : "border-slate-100"
                            )}
                          />
                        </span>
                      </div>
                    </td>
                  </tr>
                )}
                <tr>
                  {stepIdentifier && (
                    <td className="w-0 align-top px-1 select-none">
                      {stepIdentifier(executionId)}
                    </td>
                  )}
                  <td className="align-top px-1">
                    <LogMessage level={level} content={content} />
                  </td>
                </tr>
              </Fragment>
            );
          })}
        </tbody>
      </table>
    );
  } else {
    return (
      <p>
        <em>None</em>
      </p>
    );
  }
}

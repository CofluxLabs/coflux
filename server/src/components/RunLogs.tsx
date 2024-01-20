import { Fragment, ReactNode } from "react";
import { sortBy } from "lodash";
import { DateTime } from "luxon";
import classNames from "classnames";
import {
  IconAlertHexagon,
  IconAlertTriangle,
  IconInfoCircle,
} from "@tabler/icons-react";

import * as models from "../models";
import { formatDiff } from "../utils";

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
  size = 16,
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

function substituteLabels(template: string, labels: Record<string, any>) {
  return Object.entries(labels).reduce(
    ([message, extra], [key, value]) => {
      const placeholder = `{${key}}`;
      if (message.includes(placeholder)) {
        return [message.replaceAll(placeholder, value), extra];
      } else {
        return [message, { ...extra, [key]: value }];
      }
    },
    [template, {}],
  );
}

type LogMessageProps = {
  level: models.LogMessageLevel;
  template: string;
  labels: Record<string, any>;
  className?: string;
};

function LogMessage({ level, template, labels, className }: LogMessageProps) {
  const [message, extra] = substituteLabels(template, labels);
  return (
    <div className={classNames(className, classForLevel(level))}>
      {iconForLevel(level, "inline-block mr-1 mt-[-2px]")}
      <span className="whitespace-pre-wrap">{message}</span>
      {Object.entries(extra).map(([key, value]) => (
        <Fragment key={key}>
          {" "}
          <span className="bg-slate-200/50 rounded text-slate-400 text-xs px-1 whitespace-nowrap">
            {key}:{" "}
            <span className="text-slate-500">{JSON.stringify(value)}</span>
          </span>
        </Fragment>
      ))}
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
            const [executionId, timestamp, level, template, labels] = message;
            const createdAt = DateTime.fromMillis(timestamp);
            const diff = createdAt.diff(lastTimestamp, [
              "days",
              "hours",
              "minutes",
              "seconds",
              "milliseconds",
            ]);
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
                            DateTime.DATETIME_SHORT_WITH_SECONDS,
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
                                : "border-slate-100",
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
                    <LogMessage
                      level={level}
                      template={template}
                      labels={labels}
                    />
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

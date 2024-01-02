import { sortBy } from "lodash";
import classNames from "classnames";
import { DateTime } from "luxon";
import { Link } from "react-router-dom";

import * as models from "../models";
import { buildUrl } from "../utils";
import LogMessage from "./LogMessage";

type Props = {
  run: models.Run;
  runId: string;
  logs: models.LogMessage[];
  projectId: string;
  environmentName: string | null | undefined;
  activeStepId: string | null;
  activeAttemptNumber: number | null;
};

export default function RunLogs({
  run,
  runId,
  logs,
  projectId,
  environmentName,
  activeStepId,
  activeAttemptNumber,
}: Props) {
  const startTime = DateTime.fromMillis(run.createdAt);
  return (
    <div className="p-4">
      {logs.length == 0 ? (
        <p>
          <em>None</em>
        </p>
      ) : (
        <table className="w-full">
          <tbody>
            {sortBy(logs, (l) => l[1]).map((message, index) => {
              const [executionId, timestamp, level, content] = message;
              const stepId = Object.keys(run.steps).find(
                (id) => executionId in run.steps[id].executions
              );
              const step = stepId && run.steps[stepId];
              const attempt =
                stepId && run.steps[stepId].executions[executionId];
              const isActive =
                stepId &&
                stepId == activeStepId &&
                attempt &&
                attempt.sequence == activeAttemptNumber;
              const createdAt = DateTime.fromMillis(timestamp);
              return (
                <tr key={index}>
                  <td className="text-sm w-0 align-top px-1">
                    <span
                      title={createdAt.toLocaleString(
                        DateTime.DATETIME_SHORT_WITH_SECONDS
                      )}
                    >
                      +{Math.floor(createdAt.diff(startTime).toMillis())}ms
                    </span>
                  </td>
                  <td className="w-0 align-top px-1">
                    {step && attempt && (
                      <Link
                        to={buildUrl(
                          `/projects/${projectId}/runs/${runId}/logs`,
                          {
                            environment: environmentName,
                            step: isActive ? undefined : stepId,
                            attempt: isActive ? undefined : attempt.sequence,
                          }
                        )}
                        className={classNames(
                          "inline-block truncate w-40 max-w-full rounded leading-none",
                          isActive && "ring-2 ring-offset-1 ring-cyan-400"
                        )}
                      >
                        <span className="font-mono">{step.target}</span>{" "}
                        <span className="text-slate-500 text-sm">
                          ({step.repository})
                        </span>
                      </Link>
                    )}
                  </td>
                  <td className="align-top px-1">
                    <LogMessage
                      level={level}
                      content={content}
                      className="mb-2"
                    />
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
    </div>
  );
}

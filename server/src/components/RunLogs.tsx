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
              const stepId = Object.keys(run.steps).find(
                (id) => message[0] in run.steps[id].executions
              );
              const step = stepId && run.steps[stepId];
              const attempt =
                stepId && run.steps[stepId].executions[message[0]];
              const isActive =
                stepId &&
                stepId == activeStepId &&
                attempt &&
                attempt.sequence == activeAttemptNumber;
              const createdAt = DateTime.fromMillis(message[1]);
              return (
                <tr key={index}>
                  <td className="text-sm w-0">
                    <span
                      title={createdAt.toLocaleString(
                        DateTime.DATETIME_SHORT_WITH_SECONDS
                      )}
                    >
                      +{Math.floor(createdAt.diff(startTime).toMillis())}ms
                    </span>
                  </td>
                  <td className="w-0">
                    <div className="w-40">
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
                            "inline-block whitespace-nowrap px-1 truncate max-w-full rounded",
                            isActive && "ring ring-offset-2"
                          )}
                        >
                          <span className="font-mono">{step.target}</span>{" "}
                          <span className="text-gray-500 text-sm">
                            ({step.repository})
                          </span>
                        </Link>
                      )}
                    </div>
                  </td>
                  <td>
                    <LogMessage message={message} />
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

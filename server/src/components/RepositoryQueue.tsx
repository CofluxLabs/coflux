import { Link } from "react-router-dom";
import { IconAlertCircle, IconInnerShadowTopLeft } from "@tabler/icons-react";
import { DateTime } from "luxon";

import * as models from "../models";
import useNow from "../hooks/useNow";
import { buildUrl, formatDiff } from "../utils";

type Props = {
  projectId: string;
  environmentName: string;
  executions: Record<string, models.QueuedExecution>;
};

export default function RepositoryQueue({
  projectId,
  environmentName,
  executions,
}: Props) {
  const now = useNow(500);
  return (
    <div className="py-2">
      {Object.keys(executions).length ? (
        <ul>
          {Object.entries(executions).map(([executionId, execution]) => {
            const executeAt = DateTime.fromMillis(
              execution.executeAfter || execution.createdAt,
            );
            const dueDiff = executeAt.diff(DateTime.fromJSDate(now), [
              "days",
              "hours",
              "minutes",
              "seconds",
            ]);
            return (
              <li key={executionId} className="flex items-center gap-1">
                {execution.assignedAt ? (
                  <IconInnerShadowTopLeft
                    size={16}
                    className="text-cyan-400 animate-spin"
                  />
                ) : dueDiff.toMillis() < -1000 ? (
                  <span
                    title={`Executions overdue (${formatDiff(dueDiff, true)})`}
                  >
                    <IconAlertCircle
                      size={16}
                      className={
                        dueDiff.toMillis() < -5000
                          ? "text-red-700"
                          : "text-yellow-600"
                      }
                    />
                  </span>
                ) : null}
                <Link
                  to={buildUrl(
                    `/projects/${projectId}/runs/${execution.runId}/graph`,
                    {
                      environment: environmentName,
                      step: execution.stepId,
                      attempt: execution.sequence,
                    },
                  )}
                >
                  <span className="font-mono">{execution.target}</span>
                </Link>
              </li>
            );
          })}
        </ul>
      ) : (
        <p className="italic text-slate-500">No executions running</p>
      )}
    </div>
  );
}

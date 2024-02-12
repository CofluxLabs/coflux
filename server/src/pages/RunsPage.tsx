import { Link, useParams, useSearchParams } from "react-router-dom";
import { DateTime } from "luxon";
import { sortBy } from "lodash";

import * as models from "../models";
import { useContext } from "../layouts/RunLayout";
import { buildUrl } from "../utils";

// TODO: better name for page
export default function RunsPage() {
  const { run } = useContext();
  const { project: projectId } = useParams();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get("environment") || undefined;
  const runs = Object.values(run.steps)
    .flatMap((s) => Object.values(s.executions))
    .flatMap((e) => e.children)
    .filter((c): c is models.Child => typeof c != "string")
    .reduce<Record<string, models.Child>>(
      (runs, child) => ({ ...runs, [child.runId]: child }),
      {},
    );
  return (
    <div className="p-4">
      <table className="w-full">
        <tbody>
          {sortBy(Object.keys(runs), (runId) => runs[runId].createdAt).map(
            (runId: string) => {
              const run = runs[runId];
              const createdAt = DateTime.fromMillis(run.createdAt);
              return (
                <tr key={runId}>
                  <td>
                    <span className="text-sm text-slate-400">
                      {createdAt.toLocaleString(
                        DateTime.DATETIME_SHORT_WITH_SECONDS,
                      )}
                    </span>
                  </td>
                  <td>
                    <Link
                      to={buildUrl(`/projects/${projectId}/runs/${runId}`, {
                        environment: environmentName,
                      })}
                    >
                      <span className="font-mono">{run.target}</span>{" "}
                      <span className="text-slate-500 text-sm">
                        ({run.repository})
                      </span>
                    </Link>
                  </td>
                </tr>
              );
            },
          )}
        </tbody>
      </table>
    </div>
  );
}

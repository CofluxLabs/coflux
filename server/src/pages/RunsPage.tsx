import { Link, useParams, useSearchParams } from "react-router-dom";

import { useContext } from "../layouts/RunLayout";
import { sortBy } from "lodash";
import { buildUrl } from "../utils";
import { DateTime } from "luxon";

// TODO: better name for page
export default function RunsPage() {
  const { run } = useContext();
  const { project: projectId, run: runId } = useParams();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get("environment") || undefined;
  const runs = Object.assign(
    {},
    ...Object.values(run.steps)
      .flatMap((s) => Object.values(s.executions))
      .map((e) => e.children)
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

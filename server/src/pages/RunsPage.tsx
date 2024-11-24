import { Fragment } from "react";
import { Link, useParams, useSearchParams } from "react-router-dom";
import { DateTime } from "luxon";

import * as models from "../models";
import { useContext } from "../layouts/RunLayout";
import { buildUrl } from "../utils";
import StepLink from "../components/StepLink";

// TODO: better name for page
export default function RunsPage() {
  const { run } = useContext();
  const { project: projectId, run: runId } = useParams();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get("environment") || undefined;
  const initialStepId = Object.keys(run.steps).find(
    (stepId) => !run.steps[stepId].parentId,
  )!;
  const executions = run.steps[initialStepId].executions;
  return (
    <div className="p-4">
      <table className="w-full">
        <tbody>
          {Object.keys(executions)
            .map((a) => parseInt(a, 10))
            .sort()
            .map((attempt) => {
              const children = executions[attempt].children.filter(
                (c): c is models.Child => typeof c != "string",
              );
              return (
                <Fragment key={attempt}>
                  {children.length ? (
                    <Fragment>
                      <tr>
                        <td colSpan={2}>
                          <h3 className="text-xs text-slate-400 uppercase font-semibold mt-3 mb-1">
                            <StepLink
                              runId={runId!}
                              stepId={initialStepId}
                              attempt={attempt}
                              className="rounded ring-offset-1 px-1"
                              activeClassName="ring-2 ring-cyan-400"
                              hoveredClassName="ring-2 ring-slate-300"
                            >
                              Iteration #{attempt}
                            </StepLink>
                          </h3>
                        </td>
                      </tr>
                      {children.map((child) => {
                        const createdAt = DateTime.fromMillis(run.createdAt);
                        return (
                          <tr key={child.runId}>
                            <td>
                              <span className="text-sm text-slate-400">
                                {createdAt.toLocaleString(
                                  DateTime.DATETIME_SHORT_WITH_SECONDS,
                                )}
                              </span>
                            </td>
                            <td>
                              <Link
                                to={buildUrl(
                                  `/projects/${projectId}/runs/${child.runId}`,
                                  {
                                    environment: environmentName,
                                  },
                                )}
                              >
                                <span className="font-mono">
                                  {child.target}
                                </span>{" "}
                                <span className="text-slate-500 text-sm">
                                  ({child.repository})
                                </span>
                              </Link>
                            </td>
                          </tr>
                        );
                      })}
                    </Fragment>
                  ) : null}
                </Fragment>
              );
            })}
        </tbody>
      </table>
    </div>
  );
}

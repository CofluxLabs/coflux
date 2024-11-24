import { Fragment } from "react";
import { useParams } from "react-router-dom";
import { DateTime } from "luxon";

import * as models from "../models";
import { useContext } from "../layouts/RunLayout";
import StepLink from "../components/StepLink";

export default function ChildrenPage() {
  const { run } = useContext();
  const { run: runId } = useParams();
  const initialStepId = Object.keys(run.steps).find(
    (stepId) => !run.steps[stepId].parentId,
  )!;
  const executions = run.steps[initialStepId].executions;
  const hasChildren = Object.values(executions).some((e) =>
    e.children.some((c) => typeof c != "string"),
  );
  return (
    <div className="p-4">
      {hasChildren ? (
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
                                <StepLink
                                  runId={child.runId}
                                  stepId={child.stepId}
                                  attempt={1}
                                  className="rounded text-sm ring-offset-1 px-1"
                                  hoveredClassName="ring-2 ring-slate-300"
                                >
                                  <span className="font-mono">
                                    {child.target}
                                  </span>{" "}
                                  <span className="text-slate-500 text-xs">
                                    ({child.repository})
                                  </span>
                                </StepLink>
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
      ) : (
        <p className="italic">None</p>
      )}
    </div>
  );
}

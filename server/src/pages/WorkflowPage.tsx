import { findKey, maxBy } from "lodash";
import { Fragment } from "react";
import { Navigate, useParams, useSearchParams } from "react-router-dom";

import { useSetActive } from "../layouts/ProjectLayout";
import { buildUrl } from "../utils";
import Loading from "../components/Loading";
import { useEnvironments, useWorkflow } from "../topics";
import { useTitlePart } from "../components/TitleContext";
import WorkflowHeader from "../components/WorkflowHeader";

export default function WorkflowPage() {
  const { project: projectId, repository, target: targetName } = useParams();
  const [searchParams] = useSearchParams();
  const activeEnvironmentName = searchParams.get("environment") || undefined;
  const environments = useEnvironments(projectId);
  const activeEnvironmentId = findKey(
    environments,
    (e) => e.name == activeEnvironmentName && e.state != "archived",
  );
  const workflow = useWorkflow(
    projectId,
    repository,
    targetName,
    activeEnvironmentId,
  );
  useTitlePart(`${targetName} (${repository})`);
  useSetActive(
    repository && targetName ? ["target", repository, targetName] : undefined,
  );
  if (!workflow) {
    return <Loading />;
  } else {
    const latestRunId = maxBy(
      Object.keys(workflow.runs),
      (runId) => workflow.runs[runId].createdAt,
    );
    if (latestRunId) {
      return (
        <Navigate
          replace
          to={buildUrl(`/projects/${projectId}/runs/${latestRunId}`, {
            environment: activeEnvironmentName,
          })}
        />
      );
    } else {
      return (
        <Fragment>
          <WorkflowHeader
            repository={repository}
            target={targetName}
            projectId={projectId!}
            activeEnvironmentId={activeEnvironmentId}
            activeEnvironmentName={activeEnvironmentName}
          />
          <div className="p-4 flex-1 flex flex-col gap-2 items-center justify-center text-center text-slate-300">
            <h1 className="text-2xl">This workflow hasn't been run yet</h1>
            <p className="text-sm">
              Click the 'run' button above to start a run of this workflow
            </p>
          </div>
        </Fragment>
      );
    }
  }
}

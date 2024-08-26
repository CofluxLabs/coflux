import { findKey, maxBy } from "lodash";
import { Fragment } from "react";
import { Navigate, useParams, useSearchParams } from "react-router-dom";

import { useSetActiveTarget } from "../layouts/ProjectLayout";
import { buildUrl } from "../utils";
import Loading from "../components/Loading";
import { useEnvironments, useTarget } from "../topics";
import TargetHeader from "../components/TargetHeader";
import { useTitlePart } from "../components/TitleContext";

export default function TargetPage() {
  const { project: projectId, repository, target: targetName } = useParams();
  const [searchParams] = useSearchParams();
  const activeEnvironmentName = searchParams.get("environment") || undefined;
  const environments = useEnvironments(projectId);
  const activeEnvironmentId = findKey(
    environments,
    (e) => e.name == activeEnvironmentName && e.status != 1,
  );
  const target = useTarget(
    projectId,
    repository,
    targetName,
    activeEnvironmentId,
  );
  useTitlePart(`${targetName} (${repository})`);
  useSetActiveTarget(target);
  if (!target) {
    return <Loading />;
  } else {
    const latestRunId = maxBy(
      Object.keys(target.runs),
      (runId) => target.runs[runId].createdAt,
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
          <TargetHeader
            target={target}
            projectId={projectId!}
            activeEnvironmentId={activeEnvironmentId}
            activeEnvironmentName={activeEnvironmentName}
            isRunning={false}
          />
          <div className="p-4 flex-1">
            <h1 className="text-slate-400 text-xl text-center">
              This target hasn't been run yet
            </h1>
          </div>
        </Fragment>
      );
    }
  }
}

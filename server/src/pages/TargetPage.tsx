import { maxBy } from "lodash";
import { Fragment } from "react";
import { Navigate, useParams, useSearchParams } from "react-router-dom";

import { useSetActiveTarget } from "../layouts/ProjectLayout";
import { buildUrl } from "../utils";
import Loading from "../components/Loading";
import { useTargetTopic } from "../topics";
import TargetHeader from "../components/TargetHeader";
import { useTitlePart } from "../components/TitleContext";

export default function TargetPage() {
  const { project: projectId, repository, target: targetName } = useParams();
  const [searchParams] = useSearchParams();
  const activeEnvironment = searchParams.get("environment") || undefined;
  const target = useTargetTopic(
    projectId,
    repository,
    targetName,
    activeEnvironment,
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
            environment: activeEnvironment,
          })}
        />
      );
    } else {
      return (
        <Fragment>
          <TargetHeader
            target={target}
            projectId={projectId!}
            activeEnvironment={activeEnvironment}
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

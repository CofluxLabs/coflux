import { maxBy } from "lodash";
import { Fragment, useCallback } from "react";
import {
  Navigate,
  useNavigate,
  useParams,
  useSearchParams,
} from "react-router-dom";

import { useSetActiveTarget } from "../layouts/ProjectLayout";
import { buildUrl } from "../utils";
import Loading from "../components/Loading";
import { useTargetTopic } from "../topics";
import TargetHeader from "../components/TargetHeader";

export default function TargetPage() {
  const { project: projectId, repository, target: targetName } = useParams();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get("environment") || undefined;
  const [target, startRun] = useTargetTopic(
    projectId,
    environmentName,
    repository,
    targetName
  );
  // TODO: remove duplication (RunLayout)
  const navigate = useNavigate();
  const handleRun = useCallback(
    (parameters: ["json", string][]) => {
      return startRun(parameters).then((runId) => {
        navigate(
          buildUrl(`/projects/${projectId}/runs/${runId}`, {
            environment: environmentName,
          })
        );
      });
    },
    [startRun]
  );
  useSetActiveTarget(target);
  if (!target) {
    return <Loading />;
  } else {
    const latestRunId = maxBy(
      Object.keys(target.runs),
      (runId) => target.runs[runId].createdAt
    );
    if (latestRunId) {
      return (
        <Navigate
          replace
          to={buildUrl(`/projects/${projectId}/runs/${latestRunId}`, {
            environment: environmentName,
          })}
        />
      );
    } else {
      return (
        <Fragment>
          <TargetHeader
            target={target}
            projectId={projectId!}
            environmentName={environmentName}
            onRun={handleRun}
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

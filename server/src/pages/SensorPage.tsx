import { findKey, maxBy } from "lodash";
import { Fragment } from "react";
import { Navigate, useParams, useSearchParams } from "react-router-dom";

import { useSetActiveTarget } from "../layouts/ProjectLayout";
import { buildUrl } from "../utils";
import Loading from "../components/Loading";
import { useEnvironments, useSensor } from "../topics";
import { useTitlePart } from "../components/TitleContext";
import SensorHeader from "../components/SensorHeader";

export default function SensorPage() {
  const { project: projectId, repository, target: targetName } = useParams();
  const [searchParams] = useSearchParams();
  const activeEnvironmentName = searchParams.get("environment") || undefined;
  const environments = useEnvironments(projectId);
  const activeEnvironmentId = findKey(
    environments,
    (e) => e.name == activeEnvironmentName && e.status != 1,
  );
  const sensor = useSensor(
    projectId,
    repository,
    targetName,
    activeEnvironmentId,
  );
  useTitlePart(`${targetName} (${repository})`);
  useSetActiveTarget(repository, targetName);
  if (!sensor) {
    return <Loading />;
  } else {
    const latestRunId = maxBy(
      Object.keys(sensor.runs),
      (runId) => sensor.runs[runId].createdAt,
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
          <SensorHeader
            repository={repository}
            target={targetName}
            projectId={projectId!}
            activeEnvironmentId={activeEnvironmentId}
            activeEnvironmentName={activeEnvironmentName}
          />
          <div className="p-4 flex-1">
            <h1 className="text-slate-400 text-xl text-center">
              This sensor hasn't been run yet
            </h1>
          </div>
        </Fragment>
      );
    }
  }
}

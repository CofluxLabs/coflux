import { findKey, maxBy } from "lodash";
import { Fragment, useCallback, useState } from "react";
import {
  Navigate,
  useNavigate,
  useParams,
  useSearchParams,
} from "react-router-dom";

import * as api from "../api";
import { useSetActiveTarget } from "../layouts/ProjectLayout";
import { buildUrl } from "../utils";
import Loading from "../components/Loading";
import { useEnvironments, useSensor } from "../topics";
import { useTitlePart } from "../components/TitleContext";
import { IconCpu, IconPlayerPlay } from "@tabler/icons-react";
import Button from "../components/common/Button";
import RunDialog from "../components/RunDialog";
import SensorHeader from "../components/SensorHeader";

export default function SensorPage() {
  const navigate = useNavigate();
  const { project: projectId, repository, target: targetName } = useParams();
  const [runDialogOpen, setRunDialogOpen] = useState(false);
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
  const handleStartClick = useCallback(() => {
    setRunDialogOpen(true);
  }, []);
  const handleRunDialogClose = useCallback(() => setRunDialogOpen(false), []);

  const handleRunSubmit = useCallback(
    (arguments_: ["json", string][]) => {
      return api
        .schedule(
          projectId!,
          repository!,
          targetName!,
          "sensor",
          activeEnvironmentName!,
          arguments_,
        )
        .then(({ runId }) => {
          setRunDialogOpen(false);
          navigate(
            buildUrl(`/projects/${projectId}/runs/${runId}`, {
              environment: activeEnvironmentName,
            }),
          );
        });
    },
    [navigate, projectId, repository, targetName, activeEnvironmentName],
  );
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
          <div className="p-4 flex justify-between gap-2 items-start">
            <div className="flex flex-col gap-2">
              <div className="flex items-start gap-1">
                <IconCpu
                  size={24}
                  strokeWidth={1.5}
                  className="text-slate-400 shrink-0 mt-px"
                />
                <div className="flex items-center flex-wrap gap-x-2">
                  <h1 className="text-lg font-bold font-mono">{targetName}</h1>
                  <span className="text-slate-500">({repository})</span>
                </div>
              </div>
            </div>
            <div className="flex items-center gap-2">
              <Button
                onClick={handleStartClick}
                left={<IconPlayerPlay size={16} />}
                disabled={!activeEnvironmentId || !sensor.parameters}
              >
                Start...
              </Button>
              {activeEnvironmentId && sensor.parameters && (
                <RunDialog
                  projectId={projectId!}
                  repository={repository}
                  target={targetName}
                  parameters={sensor.parameters}
                  activeEnvironmentId={activeEnvironmentId}
                  open={runDialogOpen}
                  onRun={handleRunSubmit}
                  onClose={handleRunDialogClose}
                />
              )}
            </div>
          </div>
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

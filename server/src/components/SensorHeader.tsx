import { useCallback, useState } from "react";
import { IconCpu, IconPlayerPlay } from "@tabler/icons-react";
import { useNavigate } from "react-router-dom";

import * as api from "../api";
import RunSelector from "./RunSelector";
import Button from "./common/Button";
import { buildUrl } from "../utils";
import RunDialog from "./RunDialog";
import { useRun, useSensor } from "../topics";

type StopResumeButtonProps = {
  isRunning?: boolean;
  onStop: () => void;
  onResume: () => void;
};

function StopResumeButton({
  isRunning,
  onStop,
  onResume,
}: StopResumeButtonProps) {
  const handleStopClick = useCallback(() => {
    if (confirm("Are you sure you want to stop this sensor?")) {
      onStop();
    }
  }, [onStop]);
  return isRunning ? (
    <Button
      onClick={handleStopClick}
      outline={true}
      variant="warning"
      size="sm"
    >
      Stop
    </Button>
  ) : (
    <Button onClick={onResume} outline={true} size="sm">
      Resume
    </Button>
  );
}

type Props = {
  repository: string | undefined;
  target: string | undefined;
  projectId: string;
  runId?: string;
  activeEnvironmentId: string | undefined;
  activeEnvironmentName: string | undefined;
};

export default function SensorHeader({
  repository,
  target,
  projectId,
  runId,
  activeEnvironmentId,
  activeEnvironmentName,
}: Props) {
  const navigate = useNavigate();
  const [runDialogOpen, setRunDialogOpen] = useState(false);
  const sensor = useSensor(projectId, repository, target, activeEnvironmentId);
  const run = useRun(projectId, runId, activeEnvironmentId);
  const handleRunSubmit = useCallback(
    (arguments_: ["json", string][]) => {
      const configuration = sensor!.configuration!;
      return api
        .startSensor(
          projectId,
          repository!,
          target!,
          activeEnvironmentName!,
          arguments_,
          {
            requires: configuration.requires,
          },
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
    [navigate, projectId, repository, target, activeEnvironmentName, sensor],
  );
  const handleStop = useCallback(() => {
    return api.cancelRun(projectId, runId!);
  }, [projectId, runId]);
  const initialStepId =
    run && Object.keys(run.steps).find((stepId) => !run.steps[stepId].parentId);
  const handleResume = useCallback(() => {
    api.rerunStep(projectId, initialStepId!, activeEnvironmentName!);
  }, [projectId, initialStepId, activeEnvironmentName]);
  const handleStartClick = useCallback(() => {
    setRunDialogOpen(true);
  }, []);
  const handleRunDialogClose = useCallback(() => setRunDialogOpen(false), []);
  const isRunning =
    run &&
    Object.values(run.steps).some((s) =>
      Object.values(s.executions).some((e) => !e.result),
    );
  return (
    <div className="p-4 flex justify-between gap-2 items-start">
      <div className="flex flex-col gap-2">
        <div className="flex items-baseline gap-1">
          <span className="text-slate-400">{repository}</span>
          <span className="text-slate-400">/</span>
          <IconCpu
            size={26}
            strokeWidth={1.5}
            className="text-slate-500 shrink-0 self-start"
          />
          <h1 className="text-lg font-bold font-mono">{target}</h1>
        </div>

        {runId && (
          <div className="flex items-center gap-2">
            {sensor && (
              <RunSelector
                runs={sensor.runs}
                projectId={projectId}
                runId={runId}
                activeEnvironmentName={activeEnvironmentName}
              />
            )}
            <StopResumeButton
              isRunning={isRunning}
              onStop={handleStop}
              onResume={handleResume}
            />
          </div>
        )}
      </div>
      <div className="flex items-center gap-2">
        {sensor && (
          <>
            <Button
              onClick={handleStartClick}
              left={<IconPlayerPlay size={16} />}
              disabled={!activeEnvironmentId || !sensor.parameters}
            >
              Start...
            </Button>
            {activeEnvironmentId && sensor.parameters && (
              <RunDialog
                projectId={projectId}
                repository={repository}
                target={target}
                parameters={sensor.parameters}
                activeEnvironmentId={activeEnvironmentId}
                open={runDialogOpen}
                onRun={handleRunSubmit}
                onClose={handleRunDialogClose}
              />
            )}
          </>
        )}
      </div>
    </div>
  );
}

import { useCallback, useState } from "react";
import { IconBolt, IconCpu, IconSubtask } from "@tabler/icons-react";
import { useNavigate } from "react-router-dom";

import * as models from "../models";
import * as api from "../api";
import RunSelector from "./RunSelector";
import Button from "./common/Button";
import { buildUrl } from "../utils";
import RunDialog from "./RunDialog";
import EnvironmentLabel from "./EnvironmentLabel";

type CancelButtonProps = {
  onCancel: () => void;
};

function CancelButton({ onCancel }: CancelButtonProps) {
  const handleCancelClick = useCallback(() => {
    if (confirm("Are you sure you want to cancel this run?")) {
      onCancel();
    }
  }, [onCancel]);
  return (
    <Button
      onClick={handleCancelClick}
      outline={true}
      variant="warning"
      size="sm"
    >
      Cancel
    </Button>
  );
}

function iconForTarget(target: models.Target) {
  switch (target.type) {
    case "workflow":
      return IconSubtask;
    case "sensor":
      return IconCpu;
    default:
      return null;
  }
}

type Props = {
  target: models.Target;
  projectId: string;
  runId?: string;
  activeEnvironment: string | undefined;
  runEnvironment?: string;
  isRunning: boolean;
};

export default function TargetHeader({
  target,
  projectId,
  runId,
  activeEnvironment,
  runEnvironment,
  isRunning,
}: Props) {
  const navigate = useNavigate();
  const [runDialogOpen, setRunDialogOpen] = useState(false);
  const handleRunSubmit = useCallback(
    (environmentName: string, arguments_: ["json", string][]) => {
      return api
        .schedule(
          projectId,
          target.repository,
          target.target,
          environmentName,
          arguments_,
        )
        .then(({ runId }) => {
          setRunDialogOpen(false);
          // TODO: keep 'active' environment?
          navigate(
            buildUrl(`/projects/${projectId}/runs/${runId}`, {
              environment: environmentName,
            }),
          );
        });
    },
    [projectId, target],
  );
  const handleCancel = useCallback(() => {
    return api.cancelRun(projectId, runId!);
  }, [projectId, runId]);
  const handleRunClick = useCallback(() => {
    setRunDialogOpen(true);
  }, []);
  const handleRunDialogClose = useCallback(() => setRunDialogOpen(false), []);
  const Icon = iconForTarget(target);
  const runnable = target.type == "workflow" || target.type == "sensor";

  return (
    <div className="p-4 flex justify-between gap-2 items-start">
      <div className="flex flex-col gap-2">
        <div className="flex items-center gap-2">
          <h1 className="flex items-center">
            {Icon && (
              <Icon
                size={24}
                strokeWidth={1.5}
                className="text-slate-400 mr-1"
              />
            )}
            <span className="text-lg font-bold font-mono">{target.target}</span>
            <span className="ml-2 text-slate-500">({target.repository})</span>
          </h1>
        </div>

        {runId && (
          <div className="flex items-center gap-2">
            <RunSelector
              runs={target.runs}
              projectId={projectId}
              runId={runId}
              activeEnvironment={activeEnvironment}
            />

            {runEnvironment && runEnvironment != activeEnvironment && (
              <EnvironmentLabel name={runEnvironment} interactive={true} />
            )}
            {isRunning && <CancelButton onCancel={handleCancel} />}
          </div>
        )}
      </div>
      <div className="flex items-center gap-2">
        <Button
          onClick={handleRunClick}
          left={<IconBolt size={16} />}
          disabled={!runnable}
        >
          Run...
        </Button>
        {runnable && (
          <RunDialog
            target={target}
            activeEnvironmentName={activeEnvironment}
            open={runDialogOpen}
            onRun={handleRunSubmit}
            onClose={handleRunDialogClose}
          />
        )}
      </div>
    </div>
  );
}

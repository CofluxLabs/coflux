import { useCallback, useState } from "react";
import {
  IconBolt,
  IconCpu,
  IconPlayerPlay,
  IconSubtask,
} from "@tabler/icons-react";
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
    (arguments_: ["json", string][]) => {
      if (target.type !== "workflow" && target.type !== "sensor") {
        throw new Error("unexpected target type");
      }
      return api
        .schedule(
          projectId,
          target.repository,
          target.target,
          target.type,
          activeEnvironment!,
          arguments_,
        )
        .then(({ runId }) => {
          setRunDialogOpen(false);
          navigate(
            buildUrl(`/projects/${projectId}/runs/${runId}`, {
              environment: activeEnvironment,
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
  return (
    <div className="p-4 flex justify-between gap-2 items-start">
      <div className="flex flex-col gap-2">
        <div className="flex items-start gap-1">
          {Icon && (
            <Icon
              size={24}
              strokeWidth={1.5}
              className="text-slate-400 shrink-0 mt-px"
            />
          )}
          <div className="flex items-center flex-wrap gap-x-2">
            <h1 className="text-lg font-bold font-mono">{target.target}</h1>
            <span className="text-slate-500">({target.repository})</span>
          </div>
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
              <EnvironmentLabel
                name={runEnvironment}
                warning="This run is from a different environment"
              />
            )}
            {isRunning && <CancelButton onCancel={handleCancel} />}
          </div>
        )}
      </div>
      <div className="flex items-center gap-2">
        {(target.type == "workflow" || target.type == "sensor") && (
          <Button
            onClick={handleRunClick}
            left={
              target.type == "sensor" ? (
                <IconPlayerPlay size={16} />
              ) : (
                <IconBolt size={16} />
              )
            }
            disabled={!activeEnvironment || !target.parameters}
          >
            {target.type == "sensor" ? "Start..." : "Run..."}
          </Button>
        )}
        {activeEnvironment && target.parameters && (
          <RunDialog
            target={target}
            parameters={target.parameters}
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

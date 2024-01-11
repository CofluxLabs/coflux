import { Fragment, useCallback, useState } from "react";
import { IconCpu, IconSubtask } from "@tabler/icons-react";
import { useNavigate } from "react-router-dom";

import * as models from "../models";
import * as api from "../api";
import RunSelector from "./RunSelector";
import Button from "./common/Button";
import { buildUrl } from "../utils";
import RunDialog from "./RunDialog";

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
    case "task":
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
  environmentName: string | undefined;
  isRunning: boolean;
};

export default function TargetHeader({
  target,
  projectId,
  runId,
  environmentName,
  isRunning,
}: Props) {
  const navigate = useNavigate();
  const [runDialogOpen, setRunDialogOpen] = useState(false);
  const handleRunSubmit = useCallback(
    (arguments_: ["json", string][]) => {
      return api
        .schedule(
          projectId,
          environmentName!,
          target.repository,
          target.target,
          arguments_,
        )
        .then(({ runId }) => {
          setRunDialogOpen(false);
          navigate(
            buildUrl(`/projects/${projectId}/runs/${runId}`, {
              environment: environmentName,
            }),
          );
        });
    },
    [projectId, environmentName, target],
  );
  const handleCancel = useCallback(() => {
    return api.cancelRun(projectId, environmentName!, runId!);
  }, [projectId, environmentName, runId]);
  const handleRunClick = useCallback(() => {
    setRunDialogOpen(true);
  }, []);
  const handleRunDialogClose = useCallback(() => setRunDialogOpen(false), []);
  const Icon = iconForTarget(target);
  return (
    <div className="p-4 flex">
      <h1 className="flex items-center">
        {Icon && (
          <Icon size={24} strokeWidth={1.5} className="text-slate-400 mr-1" />
        )}
        <span className="text-xl font-bold font-mono">{target.target}</span>
        <span className="ml-2 text-slate-500">({target.repository})</span>
      </h1>
      <div className="flex-1 flex items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          {runId && (
            <RunSelector
              className="ml-3"
              runs={target.runs}
              projectId={projectId}
              runId={runId}
              environmentName={environmentName}
            />
          )}
          {isRunning && <CancelButton onCancel={handleCancel} />}
        </div>
        {environmentName && (
          <Fragment>
            <Button onClick={handleRunClick}>Run...</Button>
            <RunDialog
              target={target}
              open={runDialogOpen}
              onRun={handleRunSubmit}
              onClose={handleRunDialogClose}
            />
          </Fragment>
        )}
      </div>
    </div>
  );
}

import { useCallback } from "react";
import { IconCpu, IconSubtask } from "@tabler/icons-react";

import * as models from "../models";
import RunButton from "./RunButton";
import RunSelector from "./RunSelector";
import Button from "./common/Button";

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
  onRun: (parameters: ["json", string][]) => Promise<void>;
  onCancel?: () => void;
};

export default function TargetHeader({
  target,
  projectId,
  runId,
  environmentName,
  onRun,
  onCancel,
}: Props) {
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
          {onCancel && <CancelButton onCancel={onCancel} />}
        </div>
        {environmentName && <RunButton target={target} onRun={onRun} />}
      </div>
    </div>
  );
}

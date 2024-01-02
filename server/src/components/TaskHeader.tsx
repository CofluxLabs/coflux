import { useCallback } from "react";

import * as models from "../models";
import RunButton from "./RunButton";
import RunSelector from "./RunSelector";
import TargetHeader from "./TargetHeader";
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

type Props = {
  task: models.Task;
  projectId: string;
  runId?: string;
  environmentName: string | undefined;
  onRun: (parameters: ["json", string][]) => Promise<void>;
  onCancel?: () => void;
};

export default function TaskHeader({
  task,
  projectId,
  runId,
  environmentName,
  onRun,
  onCancel,
}: Props) {
  return (
    <TargetHeader target={task.target} repository={task.repository}>
      <div className="flex-1 flex items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          {runId && (
            <RunSelector
              className="ml-3"
              runs={task.runs}
              projectId={projectId}
              runId={runId}
              environmentName={environmentName}
            />
          )}
          {onCancel && <CancelButton onCancel={onCancel} />}
        </div>
        {environmentName && <RunButton task={task} onRun={onRun} />}
      </div>
    </TargetHeader>
  );
}

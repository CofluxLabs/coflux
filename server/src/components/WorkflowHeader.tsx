import { useCallback, useState } from "react";
import { IconBolt, IconSubtask } from "@tabler/icons-react";
import { useNavigate } from "react-router-dom";

import * as models from "../models";
import * as api from "../api";
import RunSelector from "./RunSelector";
import Button from "./common/Button";
import { buildUrl } from "../utils";
import RunDialog from "./RunDialog";
import EnvironmentLabel from "./EnvironmentLabel";
import { useRun, useWorkflow } from "../topics";
import { minBy } from "lodash";

function getRunEnvironmentId(run: models.Run) {
  const initialStepId = minBy(
    Object.keys(run.steps).filter((id) => !run.steps[id].parentId),
    (stepId) => run.steps[stepId].createdAt,
  )!;
  return run.steps[initialStepId].executions[1].environmentId;
}

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
  repository: string | undefined;
  target: string | undefined;
  projectId: string;
  runId?: string;
  activeEnvironmentId: string | undefined;
  activeEnvironmentName: string | undefined;
};

export default function WorkflowHeader({
  repository,
  target,
  projectId,
  runId,
  activeEnvironmentId,
  activeEnvironmentName,
}: Props) {
  const navigate = useNavigate();
  const [runDialogOpen, setRunDialogOpen] = useState(false);
  const workflow = useWorkflow(
    projectId,
    repository,
    target,
    activeEnvironmentId,
  );
  const run = useRun(projectId, runId, activeEnvironmentId);
  const handleRunSubmit = useCallback(
    (arguments_: ["json", string][]) => {
      return api
        .schedule(
          projectId,
          repository!,
          target!,
          "workflow",
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
    [navigate, projectId, runId, repository, target, activeEnvironmentName],
  );
  const handleCancel = useCallback(() => {
    return api.cancelRun(projectId, runId!);
  }, [projectId, runId]);
  const handleRunClick = useCallback(() => {
    setRunDialogOpen(true);
  }, []);
  const handleRunDialogClose = useCallback(() => setRunDialogOpen(false), []);
  const runEnvironmentId = run && getRunEnvironmentId(run);
  const isRunning =
    run &&
    Object.values(run.steps).some((s) =>
      Object.values(s.executions).some((e) => !e.result),
    );
  return (
    <div className="p-4 flex justify-between gap-2 items-start">
      <div className="flex flex-col gap-2">
        <div className="flex items-start gap-1">
          <IconSubtask
            size={24}
            strokeWidth={1.5}
            className="text-slate-400 shrink-0 mt-px"
          />
          <div className="flex items-center flex-wrap gap-x-2">
            <h1 className="text-lg font-bold font-mono">{target}</h1>
            <span className="text-slate-500">({repository})</span>
          </div>
        </div>

        {runId && (
          <div className="flex items-center gap-2">
            {workflow && (
              <RunSelector
                runs={workflow.runs}
                projectId={projectId}
                runId={runId}
                activeEnvironmentName={activeEnvironmentName}
              />
            )}

            {runEnvironmentId && runEnvironmentId != activeEnvironmentId && (
              <EnvironmentLabel
                projectId={projectId}
                environmentId={runEnvironmentId}
                warning="This run is from a different environment"
              />
            )}
            {isRunning && <CancelButton onCancel={handleCancel} />}
          </div>
        )}
      </div>
      <div className="flex items-center gap-2">
        {workflow && (
          <>
            <Button
              onClick={handleRunClick}
              left={<IconBolt size={16} />}
              disabled={!activeEnvironmentId || !workflow.parameters}
            >
              Run...
            </Button>
            {activeEnvironmentId && workflow.parameters && (
              <RunDialog
                projectId={projectId}
                repository={repository}
                target={target}
                parameters={workflow.parameters}
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

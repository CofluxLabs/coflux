import { Link, useParams, useSearchParams } from "react-router-dom";
import { useTopic } from "@topical/react";
import classNames from "classnames";

import * as models from "../models";
import { useContext } from "../layouts/RunLayout";
import RunLogs from "../components/RunLogs";
import { buildUrl } from "../utils";
import { DateTime } from "luxon";

type StepIdentifierProps = {
  run: models.Run;
  runId: string;
  projectId: string;
  environmentName: string | null | undefined;
  activeStepId: string | null;
  activeAttemptNumber: number | null;
  executionId: string;
};

function StepIdentifier({
  run,
  runId,
  projectId,
  environmentName,
  activeStepId,
  activeAttemptNumber,
  executionId,
}: StepIdentifierProps) {
  const stepId = Object.keys(run.steps).find(
    (id) => executionId in run.steps[id].executions
  );
  const step = stepId && run.steps[stepId];
  const attempt = stepId && run.steps[stepId].executions[executionId];
  const isActive =
    stepId &&
    stepId == activeStepId &&
    attempt &&
    attempt.sequence == activeAttemptNumber;
  if (step && attempt) {
    return (
      <Link
        to={buildUrl(`/projects/${projectId}/runs/${runId}/logs`, {
          environment: environmentName,
          step: isActive ? undefined : stepId,
          attempt: isActive ? undefined : attempt.sequence,
        })}
        className={classNames(
          "block truncate w-40 max-w-full rounded text-sm",
          isActive && "ring-2 ring-offset-1 ring-cyan-400"
        )}
      >
        <span className="font-mono">{step.target}</span>{" "}
        <span className="text-slate-500 text-sm">({step.repository})</span>
      </Link>
    );
  } else {
    return null;
  }
}

export default function LogsPage() {
  const { run } = useContext();
  const { project: projectId, run: runId } = useParams();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get("environment") || undefined;
  const [logs, _] = useTopic<models.LogMessage[]>(
    "projects",
    projectId,
    "environments",
    environmentName,
    "runs",
    runId,
    "logs"
  );
  const activeStepId = searchParams.get("step");
  const activeAttemptNumber = searchParams.has("attempt")
    ? parseInt(searchParams.get("attempt")!)
    : null;
  if (runId && logs) {
    return (
      <div className="p-4">
        <RunLogs
          startTime={DateTime.fromMillis(run.createdAt)}
          logs={logs}
          stepIdentifier={(executionId: string) => (
            <StepIdentifier
              run={run}
              runId={runId}
              projectId={projectId!}
              environmentName={environmentName}
              activeStepId={activeStepId}
              activeAttemptNumber={activeAttemptNumber}
              executionId={executionId}
            />
          )}
        />
      </div>
    );
  } else {
    return null;
  }
}

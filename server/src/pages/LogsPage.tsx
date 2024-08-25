import { useParams, useSearchParams } from "react-router-dom";
import { useTopic } from "@topical/react";
import { DateTime } from "luxon";

import * as models from "../models";
import { useContext } from "../layouts/RunLayout";
import RunLogs from "../components/RunLogs";
import StepLink from "../components/StepLink";

type StepIdentifierProps = {
  runId: string;
  run: models.Run;
  executionId: string;
};

function StepIdentifier({ runId, run, executionId }: StepIdentifierProps) {
  const stepId = Object.keys(run.steps).find((id) =>
    Object.values(run.steps[id].executions).some(
      (e) => e.executionId == executionId,
    ),
  );
  const step = stepId && run.steps[stepId];
  const attempt =
    step &&
    Object.keys(step.executions).find(
      (n) => step.executions[n].executionId == executionId,
    );
  if (step && attempt) {
    return (
      <StepLink
        runId={runId}
        stepId={stepId}
        attempt={parseInt(attempt, 10)}
        className="block truncate w-40 max-w-full rounded text-sm ring-offset-1"
        activeClassName="ring-2 ring-cyan-400"
        hoveredClassName="ring-2 ring-slate-300"
      >
        <span className="font-mono">{step.target}</span>{" "}
        <span className="text-slate-500 text-sm">({step.repository})</span>
      </StepLink>
    );
  } else {
    return null;
  }
}

export default function LogsPage() {
  const { run } = useContext();
  const { project: projectId, run: runId } = useParams();
  const [searchParams] = useSearchParams();
  const activeEnvironment = searchParams.get("environment") || undefined;
  const [logs, _] = useTopic<models.LogMessage[]>(
    "projects",
    projectId,
    "runs",
    runId,
    "logs",
    activeEnvironment,
  );
  if (runId && logs) {
    return (
      <div className="p-4">
        <RunLogs
          startTime={DateTime.fromMillis(run.createdAt)}
          logs={logs}
          stepIdentifier={(executionId: string) => (
            <StepIdentifier runId={runId} run={run} executionId={executionId} />
          )}
        />
      </div>
    );
  } else {
    return null;
  }
}

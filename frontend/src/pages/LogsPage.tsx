import { useParams, useSearchParams } from "react-router-dom";
import { useTopic } from "@topical/react";

import * as models from "../models";
import { useContext } from "../layouts/RunLayout";
import RunLogs from "../components/RunLogs";

export default function LogsPage() {
  const { run } = useContext();
  const { project: projectId, run: runId } = useParams();
  // const [logs, _] = useTopic<Record<string, models.LogMessage>>(
  //   "projects",
  //   projectId,
  //   "runs",
  //   runId,
  //   "logs"
  // );
  const logs = {};
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get("environment");
  const activeStepId = searchParams.get("step");
  const activeAttemptNumber = searchParams.has("attempt")
    ? parseInt(searchParams.get("attempt")!)
    : null;
  if (runId && logs) {
    return (
      <RunLogs
        run={run}
        runId={runId}
        logs={logs}
        projectId={projectId!}
        environmentName={environmentName}
        activeStepId={activeStepId}
        activeAttemptNumber={activeAttemptNumber}
      />
    );
  } else {
    return null;
  }
}

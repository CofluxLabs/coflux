import { useParams, useSearchParams } from "react-router-dom";
import { useTopic } from "@topical/react";

import * as models from "../models";
import { useRun } from "../layouts/RunLayout";
import RunLogs from "../components/RunLogs";

export default function LogsPage() {
  const run = useRun();
  const { project: projectId } = useParams();
  const [logs, _] = useTopic<Record<string, models.LogMessage>>(
    "projects",
    projectId,
    "runs",
    run.id,
    "logs"
  );
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get("environment");
  const activeStepId = searchParams.get("step");
  const activeAttemptNumber = searchParams.has("attempt")
    ? parseInt(searchParams.get("attempt")!)
    : null;
  return (
    <div>
      {logs && (
        <RunLogs
          run={run}
          logs={logs}
          projectId={projectId!}
          environmentName={environmentName}
          activeStepId={activeStepId}
          activeAttemptNumber={activeAttemptNumber}
        />
      )}
    </div>
  );
}

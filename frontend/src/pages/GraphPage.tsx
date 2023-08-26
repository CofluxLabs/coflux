import { useParams, useSearchParams } from "react-router-dom";

import RunGraph from "../components/RunGraph";
import { useContext } from "../layouts/RunLayout";

export default function GraphPage() {
  const { run, width, height } = useContext();
  const { project: projectId, run: runId } = useParams();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get("environment") || undefined;
  const activeStepId = searchParams.get("step") || undefined;
  const activeAttemptNumber = searchParams.has("attempt")
    ? parseInt(searchParams.get("attempt")!)
    : undefined;
  return (
    <RunGraph
      run={run}
      width={width}
      height={height}
      runId={runId!}
      projectId={projectId!}
      environmentName={environmentName}
      activeStepId={activeStepId}
      activeAttemptNumber={activeAttemptNumber}
    />
  );
}

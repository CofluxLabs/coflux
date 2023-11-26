import { useParams, useSearchParams } from "react-router-dom";

import RunTimeline from "../components/RunTimeline";
import { useContext } from "../layouts/RunLayout";

export default function TimelinePage() {
  const { run } = useContext();
  const { project: projectId, run: runId } = useParams();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get("environment");
  const activeStepId = searchParams.get("step");
  return (
    <RunTimeline
      run={run}
      runId={runId!}
      projectId={projectId!}
      environmentName={environmentName}
      activeStepId={activeStepId}
    />
  );
}
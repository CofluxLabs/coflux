import { useParams, useSearchParams } from "react-router-dom";
import * as models from "../models";
import { minBy } from "lodash";

import RunGraph from "../components/RunGraph";
import { useContext } from "../layouts/RunLayout";

function getRunEnvironment(run: models.Run) {
  const initialStepId = minBy(
    Object.keys(run.steps).filter((id) => !run.steps[id].parentId),
    (stepId) => run.steps[stepId].createdAt,
  )!;
  return run.steps[initialStepId].executions[1].environment;
}

export default function GraphPage() {
  const { run, width, height } = useContext();
  const { run: runId } = useParams();
  const [searchParams] = useSearchParams();
  const activeStepId = searchParams.get("step") || undefined;
  const activeAttempt = searchParams.has("attempt")
    ? parseInt(searchParams.get("attempt")!)
    : undefined;
  if (Object.keys(run.steps).length < 1000) {
    return (
      <RunGraph
        run={run}
        width={width}
        height={height}
        runId={runId!}
        activeStepId={activeStepId}
        activeAttempt={activeAttempt}
        runEnvironment={getRunEnvironment(run)}
      />
    );
  } else {
    return (
      <div className="p-4">
        <p className="italic text-slate-500">Run graph is too big to render.</p>
      </div>
    );
  }
}

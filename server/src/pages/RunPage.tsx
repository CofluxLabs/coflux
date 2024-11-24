import { useNavigate, useParams, useSearchParams } from "react-router-dom";
import { useEffect } from "react";
import { buildUrl } from "../utils";
import { useEnvironments, useRun } from "../topics";
import { findKey } from "lodash";

export default function RunPage() {
  const navigate = useNavigate();
  const { project: projectId, run: runId } = useParams();
  const [searchParams] = useSearchParams();
  const environments = useEnvironments(projectId);
  const activeEnvironmentName = searchParams.get("environment") || undefined;
  const activeEnvironmentId = findKey(
    environments,
    (e) => e.name == activeEnvironmentName && e.status != "archived",
  );
  const run = useRun(projectId, runId, activeEnvironmentId);
  useEffect(() => {
    if (run) {
      const page = run.recurrent ? "children" : "graph";
      navigate(
        buildUrl(
          `/projects/${projectId}/runs/${runId}/${page}`,
          Object.fromEntries(searchParams),
        ),
        { replace: true },
      );
    }
  }, [run, navigate]);
  return <div></div>;
}

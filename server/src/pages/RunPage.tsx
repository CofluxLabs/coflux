import { useNavigate, useParams, useSearchParams } from "react-router-dom";
import { useContext } from "../layouts/RunLayout";
import { useEffect } from "react";
import { buildUrl } from "../utils";

export default function RunPage() {
  const navigate = useNavigate();
  const { run } = useContext();
  const { project: projectId, run: runId } = useParams();
  const [searchParams] = useSearchParams();
  useEffect(() => {
    const page = run.recurrent ? "runs" : "graph";
    navigate(
      buildUrl(
        `/projects/${projectId}/runs/${runId}/${page}`,
        Object.fromEntries(searchParams),
      ),
      { replace: true },
    );
  }, [run, navigate]);
  return <div></div>;
}

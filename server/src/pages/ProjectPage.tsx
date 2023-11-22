import { useNavigate, useParams, useSearchParams } from "react-router-dom";
import { useTopic } from "@topical/react";

import * as models from "../models";

export default function ProjectPage() {
  const { project: projectId } = useParams();
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const environmentName = searchParams.get("environment") || undefined;
  const [projects] = useTopic<Record<string, models.Project>>("projects");
  if (projectId && projects && !environmentName) {
    const environment = projects[projectId].environments[0];
    if (environment) {
      navigate(`/projects/${projectId}?environment=${environment}`);
    }
  }
  return <div></div>;
}

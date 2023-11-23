import { useNavigate, useParams, useSearchParams } from "react-router-dom";
import { useTopic } from "@topical/react";

import * as models from "../models";
import { useEffect } from "react";

export default function ProjectPage() {
  const { project: projectId } = useParams();
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const currentEnvironment = searchParams.get("environment") || undefined;
  const [projects] = useTopic<Record<string, models.Project>>("projects");
  const defaultEnvironment =
    projectId && projects && projects[projectId]?.environments[0];
  useEffect(() => {
    if (projectId && !currentEnvironment && defaultEnvironment) {
      navigate(`/projects/${projectId}?environment=${defaultEnvironment}`, {
        replace: true,
      });
    }
  }, [navigate, projectId, currentEnvironment, defaultEnvironment]);
  return <div></div>;
}

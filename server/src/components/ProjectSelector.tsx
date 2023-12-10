import { ChangeEvent, useCallback } from "react";
import { useNavigate, useParams } from "react-router-dom";

import * as models from "../models";

type Props = {
  projects: Record<string, models.Project>;
};

export default function ProjectSelector({ projects }: Props) {
  const { project: activeProjectId } = useParams();
  const navigate = useNavigate();
  const handleChange = useCallback(
    (ev: ChangeEvent<HTMLSelectElement>) =>
      navigate(`/projects/${ev.target.value}`),
    [navigate]
  );
  return (
    <div>
      <select
        value={activeProjectId || ""}
        onChange={handleChange}
        className="bg-transparent border-none text-white"
      >
        <option value="">Select...</option>
        {Object.entries(projects).map(([projectId, project]) => (
          <option value={projectId} key={projectId}>
            {project.name}
          </option>
        ))}
      </select>
    </div>
  );
}

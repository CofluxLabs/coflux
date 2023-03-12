import { useCallback } from 'react';
import { useNavigate, useParams } from 'react-router-dom';

type Props = {
  projectIds: string[];
}

export default function ProjectSelector({ projectIds }: Props) {
  const { project: activeProjectId } = useParams();
  const navigate = useNavigate();
  const handleChange = useCallback((ev) => navigate(`/projects/${ev.target.value}`), [navigate]);
  return (
    <div>
      <select
        value={activeProjectId || ''}
        onChange={handleChange}
        className="text-slate-300 bg-slate-700 rounded p-2 w-full"
      >
        <option value="">Select...</option>
        {projectIds.map((projectId) => (
          <option value={projectId} key={projectId}>
            {projectId}
          </option>
        ))}
      </select>
    </div>
  );
}
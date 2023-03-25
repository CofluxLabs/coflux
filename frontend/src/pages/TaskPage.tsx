import { maxBy } from 'lodash';
import { Fragment, useCallback } from 'react';
import { Navigate, useNavigate, useParams, useSearchParams } from 'react-router-dom';

import { useSetActiveTarget } from '../layouts/ProjectLayout';
import { buildUrl } from '../utils';
import Loading from '../components/Loading';
import TaskHeader from '../components/TaskHeader';
import { useTaskTopic } from '../topics';

export default function TaskPage() {
  const { project: projectId, repository, target } = useParams();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get('environment') || undefined;
  const [task, startRun] = useTaskTopic(projectId, environmentName, repository, target);
  // TODO: remove duplication (RunLayout)
  const navigate = useNavigate();
  const handleRun = useCallback((parameters: ['json', string][]) => {
    return startRun(parameters).then((runId) => {
      navigate(buildUrl(`/projects/${projectId}/runs/${runId}`, { environment: environmentName }));
    });
  }, [startRun]);
  useSetActiveTarget(task);
  if (!task) {
    return <Loading />;
  } else {
    const latestRun = maxBy(Object.values(task.runs), 'createdAt');
    if (latestRun) {
      return <Navigate replace to={buildUrl(`/projects/${projectId}/runs/${latestRun.id}`, { environment: environmentName })} />;
    } else {
      return (
        <Fragment>
          <TaskHeader task={task} projectId={projectId!} environmentName={environmentName} onRun={handleRun} />
          <div className="p-4 flex-1">
            <h1 className="text-gray-400 text-xl text-center">This task hasn't been run yet</h1>
          </div>
        </Fragment>
      );
    }
  }
}

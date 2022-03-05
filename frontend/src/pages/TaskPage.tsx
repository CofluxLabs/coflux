import { maxBy } from 'lodash';
import { Fragment } from 'react';
import { Navigate, useParams, useSearchParams } from 'react-router-dom';
import TaskHeader from '../components/TaskHeader';

import * as models from '../models';
import useSubscription from '../hooks/useSubscription';
import { useSetActiveTask } from '../layouts/ProjectLayout';
import { buildUrl } from '../utils';

export default function TaskPage() {
  const { project: projectId, repository, target } = useParams();
  const [searchParams] = useSearchParams();
  const environmentName = searchParams.get('environment') || undefined;
  const task = useSubscription<models.Task>('task', repository, target, environmentName);
  useSetActiveTask(task);
  if (!task) {
    return (<p>Loading...</p>);
  } else {
    const latestRun = maxBy(Object.values(task.runs), 'createdAt');
    if (latestRun) {
      return <Navigate replace to={buildUrl(`/projects/${projectId}/runs/${latestRun.id}`, { environment: environmentName })} />;
    } else {
      return (
        <Fragment>
          <TaskHeader task={task} projectId={projectId} environmentName={environmentName} />
          <div className="p-4 flex-1">
            <h1 className="text-gray-400 text-xl text-center">This task hasn't been run yet</h1>
          </div>
        </Fragment>
      );
    }
  }
}

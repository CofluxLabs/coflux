import React, { Fragment } from 'react';
import Head from 'next/head';
import { useRouter } from 'next/router';

import useTask from '../../../../../hooks/useTask';
import ProjectLayout from '../../../../../components/ProjectLayout';
import Heading from '../../../../../components/Heading';
import TaskRunsList from '../../../../../components/TaskRunsList';

export default function TaskPage() {
  const router = useRouter();
  const projectId = router.query['projectId'] as string || null;
  const taskId = router.query['taskId'] as string || null;
  const { task, error } = useTask(projectId, taskId);
  return (
    <Fragment>
      <Head>
        <title>Coflux</title>
      </Head>
      <ProjectLayout projectId="project_1">
        {error ? (
          <p>Error</p>
        ) : !task ? (
          <p>Loading...</p>
        ) : (
          <Fragment>
            <Heading><span className="font-mono">{task.target}</span> <span className="text-gray-500">({task.repository})</span></Heading>
            <TaskRunsList projectId={projectId} taskId={taskId} />
          </Fragment>
        )}
      </ProjectLayout>
    </Fragment>
  );
}

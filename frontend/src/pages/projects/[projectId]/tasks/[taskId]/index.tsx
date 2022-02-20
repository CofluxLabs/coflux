import React, { Fragment, useCallback } from 'react';
import Head from 'next/head';
import Router, { useRouter } from 'next/router';

import ProjectLayout from '../../../../../components/ProjectLayout';
import TaskDetail from '../../../../../components/TaskDetail';

export default function TaskPage() {
  const router = useRouter();
  const projectId = router.query['projectId'] as string || null;
  const environmentName = router.query['environment'] as string || null;
  const taskId = router.query['taskId'] as string || null;
  const handleEnvironmentChange = useCallback((environmentName) => {
    Router.push(`/projects/${projectId}/tasks/${taskId}?environment=${environmentName}`);
  }, [projectId, taskId]);
  return (
    <Fragment>
      <Head>
        <title>Coflux</title>
      </Head>
      <ProjectLayout projectId={projectId} environmentName={environmentName} taskId={taskId} onEnvironmentChange={handleEnvironmentChange}>
        {projectId && environmentName && taskId && (
          <TaskDetail projectId={projectId} taskId={taskId} environmentName={environmentName} />
        )}
      </ProjectLayout>
    </Fragment>
  );
}

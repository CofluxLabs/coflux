import React, { Fragment } from 'react';
import Head from 'next/head';
import { useRouter } from 'next/router';

import ProjectLayout from '../../../../../components/ProjectLayout';
import TaskDetail from '../../../../../components/TaskDetail';

export default function TaskPage() {
  const router = useRouter();
  const projectId = router.query['projectId'] as string || null;
  const taskId = router.query['taskId'] as string || null;
  return (
    <Fragment>
      <Head>
        <title>Coflux</title>
      </Head>
      <ProjectLayout projectId={projectId} taskId={taskId}>
        <TaskDetail projectId={projectId} taskId={taskId} />
      </ProjectLayout>
    </Fragment>
  );
}

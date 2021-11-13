import React, { Fragment } from 'react';
import Head from 'next/head';
import { useRouter } from 'next/router';

import ProjectLayout from '../../../../../../../components/ProjectLayout';
import RunDetail from '../../../../../../../components/RunDetail';
import RunGraph from '../../../../../../../components/RunGraph';

export default function RunPage() {
  const router = useRouter();
  const projectId = router.query['projectId'] as string || null;
  const taskId = router.query['taskId'] as string || null;
  const runId = router.query['runId'] as string || null;
  return (
    <Fragment>
      <Head>
        <title>Coflux</title>
      </Head>
      <ProjectLayout projectId="project_1">
        <RunDetail projectId={projectId} taskId={taskId} runId={runId} activeTab="overview">
          {(run) => (
            <RunGraph run={run} />
          )}
        </RunDetail>
      </ProjectLayout>
    </Fragment>
  );
}

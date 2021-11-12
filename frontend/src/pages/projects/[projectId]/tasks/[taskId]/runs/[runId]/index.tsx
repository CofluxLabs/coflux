import React, { Fragment } from 'react';
import Head from 'next/head';
import Link from 'next/link';
import { useRouter } from 'next/router';

import useTask from '../../../../../../../hooks/useTask';
import ProjectLayout from '../../../../../../../components/ProjectLayout';
import Heading from '../../../../../../../components/Heading';
import RunDetail from '../../../../../../../components/RunDetail';

export default function RunPage() {
  const router = useRouter();
  const projectId = router.query['projectId'] as string || null;
  const taskId = router.query['taskId'] as string || null;
  const runId = router.query['runId'] as string || null;
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
            <Heading>
              <Link href={`/projects/${projectId}/tasks/${taskId}`}><a><span className="font-mono">{task.target}</span> <span className="text-gray-500">({task.repository})</span></a></Link>
              <span className="mx-3">&rarr;</span>
              <span className="font-mono">{runId}</span>
            </Heading>
            <RunDetail projectId={projectId} runId={runId} />
          </Fragment>
        )}
      </ProjectLayout>
    </Fragment>
  );
}

import React, { Fragment, useCallback } from 'react';
import Head from 'next/head';
import Router, { useRouter } from 'next/router';

import ProjectLayout from '../../../components/ProjectLayout';

export default function ProjectPage() {
  const router = useRouter();
  const projectId = router.query['projectId'] as string || null;
  const environmentName = router.query['environment'] as string || null;
  const handleEnvironmentChange = useCallback((environmentName) => {
    Router.push(`/projects/${projectId}?environment=${environmentName}`);
  }, [projectId]);
  return (
    <Fragment>
      <Head>
        <title>Coflux</title>
      </Head>
      <ProjectLayout projectId={projectId} environmentName={environmentName} taskId={null} onEnvironmentChange={handleEnvironmentChange}>
        project page
      </ProjectLayout>
    </Fragment>
  );
}

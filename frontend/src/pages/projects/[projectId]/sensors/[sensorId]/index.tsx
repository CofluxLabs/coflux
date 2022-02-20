import React, { Fragment, useCallback } from 'react';
import Head from 'next/head';
import Router, { useRouter } from 'next/router';

import ProjectLayout from '../../../../../components/ProjectLayout';
import SensorDetail from '../../../../../components/SensorDetail';

export default function SensorPage() {
  const router = useRouter();
  const projectId = router.query['projectId'] as string || null;
  const environmentName = router.query['environment'] as string || null;
  const sensorId = router.query['sensorId'] as string || null;
  const handleEnvironmentChange = useCallback((environmentName) => {
    Router.push(`/projects/${projectId}/sensors/${sensorId}?environment=${environmentName}`);
  }, [projectId, sensorId]);
  return (
    <Fragment>
      <Head>
        <title>Coflux</title>
      </Head>
      <ProjectLayout projectId={projectId} environmentName={environmentName} sensorId={sensorId} onEnvironmentChange={handleEnvironmentChange}>
        <SensorDetail projectId={projectId} sensorId={sensorId} />
      </ProjectLayout>
    </Fragment>
  );
}

import React, { Fragment } from 'react';
import Head from 'next/head';
import { useRouter } from 'next/router';

import ProjectLayout from '../../../../../components/ProjectLayout';
import SensorDetail from '../../../../../components/SensorDetail';

export default function SensorPage() {
  const router = useRouter();
  const projectId = router.query['projectId'] as string || null;
  const sensorId = router.query['sensorId'] as string || null;
  return (
    <Fragment>
      <Head>
        <title>Coflux</title>
      </Head>
      <ProjectLayout projectId={projectId} sensorId={sensorId}>
        <SensorDetail projectId={projectId} sensorId={sensorId} />
      </ProjectLayout>
    </Fragment>
  );
}

import React, { Fragment } from 'react';
import Head from 'next/head';
import { useRouter } from 'next/router';

import ProjectLayout from '../../../components/ProjectLayout';

export default function ProjectPage() {
  const router = useRouter();
  const projectId = router.query['projectId'] as string || null;
  return (
    <Fragment>
      <Head>
        <title>Coflux</title>
      </Head>
      <ProjectLayout projectId={projectId}>
        project page
      </ProjectLayout>
    </Fragment>
  );
}
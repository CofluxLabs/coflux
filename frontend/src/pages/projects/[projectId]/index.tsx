import React, { Fragment } from 'react';
import Head from 'next/head';
import { useRouter } from 'next/router';

import Project from '../../../components/Project';

export default function ProjectPage() {
  const router = useRouter();
  const projectId = router.query['projectId'] as string || null;
  return (
    <Fragment>
      <Head>
        <title>Coflux</title>
      </Head>
      <Project projectId={projectId}>
        project page
      </Project>
    </Fragment>
  );
}

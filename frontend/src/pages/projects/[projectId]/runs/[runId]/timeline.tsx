import React, { Fragment } from 'react';
import Head from 'next/head';
import { useRouter } from 'next/router';

import RunDetail from '../../../../../components/RunDetail';
import RunTimeline from '../../../../../components/RunTimeline';

export default function RunPage() {
  const router = useRouter();
  const projectId = router.query['projectId'] as string || null;
  const runId = router.query['runId'] as string || null;
  return (
    <Fragment>
      <Head>
        <title>Coflux</title>
      </Head>
      <RunDetail projectId={projectId} runId={runId} activeTab="timeline">
        {(run) => (
          <RunTimeline run={run} />
        )}
      </RunDetail>
    </Fragment>
  );
}

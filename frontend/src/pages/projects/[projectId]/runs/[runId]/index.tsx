import React, { Fragment } from 'react';
import Head from 'next/head';
import { useRouter } from 'next/router';

import RunDetail from '../../../../../components/RunDetail';
import RunGraph from '../../../../../components/RunGraph';
import useWindowHash from '../../../../../hooks/useWindowHash';

export default function RunPage() {
  const router = useRouter();
  const hash = useWindowHash();
  const projectId = router.query['projectId'] as string || null;
  const runId = router.query['runId'] as string || null;
  return (
    <Fragment>
      <Head>
        <title>Coflux</title>
      </Head>
      <RunDetail projectId={projectId} runId={runId} activeTab="overview">
        {(run) => (
          <RunGraph run={run} activeStepId={hash || null} />
        )}
      </RunDetail>
    </Fragment>
  );
}

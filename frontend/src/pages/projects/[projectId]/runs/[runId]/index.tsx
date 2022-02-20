import React, { Fragment, useCallback } from 'react';
import Head from 'next/head';
import Router, { useRouter } from 'next/router';

import RunDetail from '../../../../../components/RunDetail';
import RunGraph from '../../../../../components/RunGraph';
import useWindowHash from '../../../../../hooks/useWindowHash';
import { parseHash } from '../../../../../utils';

export default function RunPage() {
  const router = useRouter();
  const hash = useWindowHash();
  const projectId = router.query['projectId'] as string || null;
  const runId = router.query['runId'] as string || null;
  const environmentName = router.query['environment'] as string || null;
  const [activeStepId, activeAttemptNumber] = parseHash(hash);
  const handleEnvironmentChange = useCallback((environmentName) => {
    Router.push(`/projects/${projectId}/runs/${runId}${environmentName ? `?environment=${environmentName}` : ''}${hash ? `#${hash}` : ''}`);
  }, [projectId, runId, hash]);
  return (
    <Fragment>
      <Head>
        <title>Coflux</title>
      </Head>
      <RunDetail
        projectId={projectId}
        runId={runId}
        environmentName={environmentName}
        activeTab="overview"
        activeStepId={activeStepId}
        activeAttemptNumber={activeAttemptNumber}
        onEnvironmentChange={handleEnvironmentChange}
      >
        {(run) => (
          <RunGraph
            run={run}
            environmentName={environmentName}
            activeStepId={activeStepId}
            activeAttemptNumber={activeAttemptNumber}
          />
        )}
      </RunDetail>
    </Fragment>
  );
}

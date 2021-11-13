import React, { Fragment } from 'react';
import Head from 'next/head';
import { useRouter } from 'next/router';

import useAgents from '../../../../hooks/useAgents';
import ProjectLayout from '../../../../components/ProjectLayout';
import Heading from '../../../../components/Heading';

export default function AgentPage() {
  const router = useRouter();
  const projectId = router.query['projectId'] as string || null;
  const agentId = router.query['agentId'] as string || null;
  const { agents, error } = useAgents(projectId);
  const agent = agents && agents.find((a) => a.id == agentId);
  return (
    <Fragment>
      <Head>
        <title>Coflux</title>
      </Head>
      <ProjectLayout projectId={projectId} agentId={agentId}>
        {error ? (
          <p>Error</p>
        ) : !agents ? (
          <p>Loading...</p>
        ) : !agent ? (
          <p>Not found</p>
        ) : (
          <Fragment>
            <Heading>Agent {agent.id}</Heading>
            <ul>
              {agent.targets.map((target, index) => (
                <li key={index} className="my-1">
                  <span className="font-mono">{target.target}</span> <span className="text-gray-500">({target.repository}@{target.version})</span>
                </li>
              ))}
            </ul>
          </Fragment>
        )}
      </ProjectLayout>
    </Fragment>
  );
}

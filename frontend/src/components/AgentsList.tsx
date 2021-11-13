import React from 'react';
import Link from 'next/link';
import classNames from 'classnames';

import useAgents from '../hooks/useAgents';

type Props = {
  projectId: string | null;
  agentId?: string | null;
}

export default function AgentsList({ projectId, agentId }: Props) {
  const { agents, error } = useAgents(projectId);
  if (error) {
    return <div>Error</div>
  } else if (!agents) {
    return <div>Loading...</div>;
  } else {
    return (
      <div>
        {agents.length ? (
          <ul>
            {agents.map((agent) => (
              <li key={agent.id} className="">
                <Link href={`/projects/${projectId}/agents/${agent.id}`}>
                  <a className={classNames('block hover:bg-gray-300 px-4 py-2', {'bg-gray-300 font-bold': agent.id == agentId})}>
                    {agent.id}
                  </a>
                </Link>
              </li>
            ))}
          </ul>
        ) : (
          <p>No agents</p>
        )}
      </div>
    );
  }
}

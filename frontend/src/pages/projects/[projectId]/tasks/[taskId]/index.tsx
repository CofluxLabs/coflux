import React, { Fragment, useCallback } from 'react';
import Head from 'next/head';
import { useRouter } from 'next/router';

import useTask from '../../../../../hooks/useTask';
import ProjectLayout from '../../../../../components/ProjectLayout';
import Heading from '../../../../../components/Heading';
import TaskRunsList from '../../../../../components/TaskRunsList';

export default function TaskPage() {
  const router = useRouter();
  const projectId = router.query['projectId'] as string || null;
  const taskId = router.query['taskId'] as string || null;
  const { task, error } = useTask(projectId, taskId);
  const handleRunClick = useCallback(() => {
    // TODO: get base URL from config?
    fetch(`http://localhost:7070/projects/${projectId}/tasks/${taskId}/runs`, { method: 'POST' })
      .then((response) => response.json())
      .then((result) => {
        router.push(`/projects/${projectId}/tasks/${taskId}/runs/${result.id}`);
      });
  }, [router, projectId, taskId]);
  return (
    <Fragment>
      <Head>
        <title>Coflux</title>
      </Head>
      <ProjectLayout projectId={projectId} taskId={taskId}>
        {error ? (
          <p>Error</p>
        ) : !task ? (
          <p>Loading...</p>
        ) : (
          <Fragment>
            <div className="flex">
              <Heading className="flex-1"><span className="font-mono">{task.target}</span> <span className="text-gray-500">({task.repository})</span></Heading>
              <button
                className="px-4 py-2 my-3 bg-blue-600 hover:bg-blue-700 rounded text-white font-bold"
                onClick={handleRunClick}
              >
                Run
              </button>
            </div>
            <TaskRunsList projectId={projectId} taskId={taskId} />
          </Fragment>
        )}
      </ProjectLayout>
    </Fragment>
  );
}

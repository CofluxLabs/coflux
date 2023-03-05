import classNames from 'classnames';
import { Fragment, ReactNode, useCallback } from 'react';
import { NavLink, Outlet, useNavigate, useOutletContext, useParams, useSearchParams } from 'react-router-dom';

import * as models from '../models';
import TaskHeader from '../components/TaskHeader';
import { useSetActiveTarget } from './ProjectLayout';
import { Transition } from '@headlessui/react';
import StepDetail from '../components/StepDetail';
import usePrevious from '../hooks/usePrevious';
import { buildUrl } from '../utils';
import Loading from '../components/Loading';
import { useRunTopic, useTaskTopic } from '../topics';

type TabProps = {
  page: string | null;
  children: ReactNode;
}

function Tab({ page, children }: TabProps) {
  const { project: projectId, run: runId } = useParams();
  const [searchParams] = useSearchParams();
  // TODO: tidy
  const params = { step: searchParams.get('step'), attempt: searchParams.get('attempt'), environment: searchParams.get('environment') };
  return (
    <NavLink
      to={buildUrl(`/projects/${projectId}/runs/${runId}${page ? '/' + page : ''}`, params)}
      end={true}
      className={({ isActive }) => classNames('px-2 py-1', isActive && 'inline-block border-b-4 border-slate-500')}
    >
      {children}
    </NavLink>
  );
}

type DetailPanelProps = {
  stepId: string | undefined;
  attemptNumber: number | undefined;
  run: models.Run;
  projectId: string;
  onRerunStep: (stepId: string, environmentName: string) => Promise<number>;
}

function DetailPanel({ stepId, attemptNumber, run, projectId, onRerunStep }: DetailPanelProps) {
  const step = stepId && run.steps[stepId];
  const previousStep = usePrevious(step);
  const stepOrPrevious = step || previousStep;
  return (
    <Transition
      as={Fragment}
      show={!!step}
      enter="transform transition ease-in-out duration-150"
      enterFrom="translate-x-full"
      enterTo="translate-x-0"
      leave="transform transition ease-in-out duration-300"
      leaveFrom="translate-x-0"
      leaveTo="translate-x-full"
    >
      <div className="fixed bottom-0 right-0 top-14 w-1/3 bg-slate-100 border-l border-slate-200 h-screen flex shadow-lg">
        {stepOrPrevious && (
          <StepDetail
            step={stepOrPrevious}
            attemptNumber={attemptNumber || 1}
            run={run}
            projectId={projectId}
            environmentName={run.environment.name}
            className="flex-1"
            onRerunStep={onRerunStep}
          />
        )}
      </div>
    </Transition>
  );
}

type OutletContext = {
  run: models.Run;
}

export default function RunLayout() {
  const { project: projectId, run: runId } = useParams();
  const [searchParams] = useSearchParams()
  const activeStepId = searchParams.get('step') || undefined;
  const activeAttemptNumber = searchParams.has('attempt') ? parseInt(searchParams.get('attempt')!, 10) : undefined;
  const environmentName = searchParams.get('environment') || undefined;
  const [run, rerunStep] = useRunTopic(projectId, runId);
  const initialStep = run && Object.values(run.steps).find((s) => !s.parent);
  const [task, startRun] = useTaskTopic(projectId, environmentName, initialStep?.repository, initialStep?.target);
  const navigate = useNavigate();
  // TODO: remove duplication (TaskPage)
  const handleRun = useCallback((parameters) => {
    return startRun(parameters).then((runId) => {
      navigate(buildUrl(`/projects/${projectId}/runs/${runId}`, { environment: environmentName }));
    });
  }, [startRun]);
  const handleRerunStep = useCallback((stepId, environmentName) => {
    return rerunStep(stepId, environmentName);
  }, [rerunStep]);
  useSetActiveTarget(task);
  if (!run || !task) {
    return <Loading />;
  } else {
    return (
      <Fragment>
        <TaskHeader task={task} projectId={projectId!} runId={run.id} environmentName={environmentName} onRun={handleRun} />
        <div className="border-b px-4">
          <Tab page={null}>Graph</Tab>
          <Tab page="timeline">Timeline</Tab>
          <Tab page="logs">Logs</Tab>
        </div>
        <div className="p-4 flex-1 overflow-auto">
          <Outlet context={{ run }} />
        </div>
        <DetailPanel
          stepId={activeStepId}
          attemptNumber={activeAttemptNumber}
          run={run}
          projectId={projectId!}
          onRerunStep={handleRerunStep}
        />
      </Fragment>
    );
  }
}

export function useRun() {
  return useOutletContext<OutletContext>().run;
}

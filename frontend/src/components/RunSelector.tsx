import React, { Fragment } from 'react';
import { Menu, Transition } from '@headlessui/react';
import { sortBy } from 'lodash';
import NextLink from 'next/link';
import classNames from 'classnames';

import * as models from '../models';
import { useSubscription } from '../hooks/useSocket';

type OptionsState = models.Task & {
  runs: Record<string, models.BaseRun>
};

type OptionsProps = {
  projectId: string | null;
  repository: string;
  target: string;
  environmentName: string;
  selectedRunId: string;
}

type LinkProps = React.DetailedHTMLProps<React.AnchorHTMLAttributes<HTMLAnchorElement>, HTMLAnchorElement> & { href: string };

function Link({ href, children, ...rest }: LinkProps) {
  return (
    <NextLink href={href}>
      <a {...rest}>{children}</a>
    </NextLink>
  )
}

function Options({ projectId, repository, target, environmentName, selectedRunId }: OptionsProps) {
  const task = useSubscription<OptionsState>('task', repository, target, environmentName);
  if (!task) {
    return <p>Loading...</p>;
  } else if (!Object.keys(task.runs).length) {
    return <p>No runs for {environmentName}</p>;
  } else {
    return (
      <Fragment>
        {sortBy(Object.values(task.runs), 'createdAt').map((run) => (
          <Menu.Item key={run.id}>
            {({ active }) => (
              <Link
                href={`/projects/${projectId}/runs/${run.id}`}
                className={classNames('block p-2 font-mono', run.id == selectedRunId && 'font-bold', active && 'bg-slate-100')}
              >
                {run.id}
              </Link>
            )}
          </Menu.Item>
        ))}
      </Fragment>
    );
  }
}

type Props = {
  projectId: string | null;
  repository: string;
  target: string;
  runId: string;
  environmentName: string;
}

export default function RunSelector({ projectId, repository, target, runId, environmentName }: Props) {
  return (
    <Menu>
      {({ open }) => (
        <div className="relative">
          <Menu.Button className="relative w-full p-1 pl-2 bg-white border border-gray-300 hover:border-gray-600 rounded">
            <span className="font-mono">{runId}</span>
            <span className="text-slate-400 text-xs mx-2">▼</span>
          </Menu.Button>
          <Transition
            as={Fragment}
            leave="transition ease-in duration-100"
            leaveFrom="opacity-100"
            leaveTo="opacity-0"
          >
            <Menu.Items className="absolute z-10 py-1 mt-1 overflow-y-scroll text-base bg-white rounded shadow-lg max-h-60" static={true}>
              {open && (
                <Options projectId={projectId} repository={repository} target={target} environmentName={environmentName} selectedRunId={runId} />
              )}
            </Menu.Items>
          </Transition>
        </div>
      )}
    </Menu>
  );
}

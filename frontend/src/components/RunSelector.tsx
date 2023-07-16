import { Fragment } from 'react';
import { Menu, Transition } from '@headlessui/react';
import { sortBy } from 'lodash';
import classNames from 'classnames';
import { Link } from 'react-router-dom';
import { DateTime } from 'luxon';

import * as models from '../models';
import { buildUrl } from '../utils';

type OptionsProps = {
  runs: Record<string, Pick<models.Run, "createdAt">>;
  projectId: string | null;
  environmentName: string | undefined;
  selectedRunId: string;
}

function Options({ runs, projectId, environmentName, selectedRunId }: OptionsProps) {
  if (!Object.keys(runs).length) {
    return <p>No runs for {environmentName}</p>;
  } else {
    return (
      <Fragment>
        {sortBy(Object.keys(runs), (runId) => runs[runId].createdAt).reverse().map((runId) => {
          const createdAt = DateTime.fromMillis(runs[runId].createdAt);
          return (
            <Menu.Item key={runId}>
              {({ active }) => (
                <Link
                  to={buildUrl(`/projects/${projectId}/runs/${runId}`, { environment: environmentName })}
                  className={classNames('block p-2', active && 'bg-slate-100')}
                >
                  <h3 className={classNames('font-mono', runId == selectedRunId && 'font-bold')}>{runId}</h3>
                  <p
                    className="text-xs text-gray-500"
                    title={createdAt.toLocaleString(DateTime.DATETIME_SHORT_WITH_SECONDS)}
                  >
                    {createdAt.toRelative()} ago
                  </p>
                </Link>
              )}
            </Menu.Item>
          );
        })}
      </Fragment>
    );
  }
}

type Props = {
  runs: Record<string, Pick<models.Run, "createdAt">>;
  projectId: string | null;
  runId: string;
  environmentName: string | undefined;
  className?: string;
}

export default function RunSelector({ runs, projectId, runId, environmentName, className }: Props) {
  return (
    <Menu>
      {({ open }) => (
        <div className={classNames(className, 'relative')}>
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
                <Options runs={runs} projectId={projectId} environmentName={environmentName} selectedRunId={runId} />
              )}
            </Menu.Items>
          </Transition>
        </div>
      )}
    </Menu>
  );
}

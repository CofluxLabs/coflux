import { Fragment, useCallback, useState } from 'react';
import { Dialog, Transition } from '@headlessui/react';
import classNames from 'classnames';

import * as models from '../models';

type ParameterProps = {
  parameter: models.Parameter;
  value: string | undefined;
  onChange: (name: string, value: string) => void;
}

function Parameter({ parameter, value, onChange }: ParameterProps) {
  const handleChange = useCallback((ev) => onChange(parameter.name, ev.target.value), [parameter, onChange]);
  return (
    <div className="py-1">
      <label className="w-32">
        <span className="font-mono font-bold">{parameter.name}</span>
        {parameter.annotation && (
          <span className="text-gray-500 ml-1 text-sm">
            ({parameter.annotation})
          </span>
        )}
      </label>
      <input
        type="text"
        className="border border-gray-400 rounded px-2 py-1 w-full" placeholder={parameter.default}
        value={value == undefined ? '' : value}
        onChange={handleChange}
      />
    </div>
  );
}

type Props = {
  parameters: models.Parameter[];
  open: boolean;
  starting: boolean;
  onRun: (parameters: [string, string][]) => void;
  onClose: () => void;
}

export default function RunDialog({ parameters, open, starting, onRun, onClose }: Props) {
  const [values, setValues] = useState<Record<string, string>>({});
  const handleValueChange = useCallback((name, value) => setValues(vs => ({ ...vs, [name]: value })), []);
  const handleRunClick = useCallback(() => {
    onRun(parameters.map((p) => ['json', values[p.name] || p.default]));
  }, [parameters, values, onRun]);
  return (
    <Transition appear show={open} as={Fragment}>
      <Dialog className="fixed inset-0 z-10 overflow-y-auto" onClose={onClose}>
        <div className="min-h-screen px-4 text-center">
          <Transition.Child
            enter="ease-out duration-300"
            enterFrom="opacity-0"
            enterTo="opacity-100"
            leave="ease-in duration-200"
            leaveFrom="opacity-100"
            leaveTo="opacity-0"
          >
            <Dialog.Overlay className="fixed inset-0 bg-black opacity-30" />
          </Transition.Child>
          <span className="inline-block h-screen align-middle" aria-hidden="true">&#8203;</span>
          <Transition.Child
            as={Fragment}
            enter="ease-out duration-300"
            enterFrom="opacity-0 scale-95"
            enterTo="opacity-100 scale-100"
            leave="ease-in duration-200"
            leaveFrom="opacity-100 scale-100"
            leaveTo="opacity-0 scale-95"
          >
            <div className="inline-block w-full max-w-md p-6 my-8 overflow-hidden text-left align-middle transition-all transform bg-white shadow-xl rounded-lg">
              <Dialog.Title className="text-xl font-medium leading-6 text-gray-900">
                Run task
              </Dialog.Title>
              {parameters.length > 0 && (
                <div className="mt-4">
                  <h3 className="font-bold uppercase text-gray-400 text-sm">Arguments</h3>
                  {parameters.map((parameter) => (
                    <Parameter
                      key={parameter.name}
                      parameter={parameter}
                      value={values[parameter.name]}
                      onChange={handleValueChange}
                    />
                  ))}
                </div>
              )}
              <div className="mt-4">
                <button
                  type="button"
                  className={classNames("px-4 py-2 rounded text-white font-bold  mr-2", starting ? 'bg-slate-200' : 'bg-slate-400 hover:bg-slate-500')}
                  disabled={starting}
                  onClick={handleRunClick}
                >
                  Run
                </button>
                <button
                  type="button"
                  className="px-4 py-2 border border-slate-400 rounded text-slate-400 font-bold hover:bg-slate-100"
                  onClick={onClose}
                >
                  Cancel
                </button>
              </div>
            </div>
          </Transition.Child>
        </div>
      </Dialog>
    </Transition>
  );
}

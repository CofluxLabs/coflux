import React, { Fragment, useCallback, useState } from 'react';
import { Dialog, Transition } from '@headlessui/react';
import classNames from 'classnames';

type FieldProps = {
  label: string;
  value: string;
  className?: string;
  placeholder?: string;
  onChange: (value: string) => void;
}

function Field({ label, value, className, placeholder, onChange }: FieldProps) {
  const handleChange = useCallback((ev) => onChange(ev.target.value), [onChange]);
  return (
    <div className={classNames("py-1", className)}>
      <label>
        {label}
      </label>
      <input
        type="text"
        className="border border-gray-400 rounded px-2 py-1 w-full" placeholder={placeholder}
        value={value}
        onChange={handleChange}
      />
    </div>
  );
}

type Props = {
  open: boolean;
  activating: boolean;
  onActivate: (repository: string, target: string) => void;
  onClose: () => void;
}

export default function ActivateSensorDialog({ open, activating, onActivate, onClose }: Props) {
  const [repository, setRepository] = useState('');
  const [target, setTarget] = useState('');
  const handleActivateClick = useCallback(() => {
    onActivate(repository, target);
  }, [repository, target, onActivate]);
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
                Activate sensor
              </Dialog.Title>
              <Field label="Repository" value={repository} onChange={setRepository} />
              <Field label="Target" value={target} onChange={setTarget} />
              <div className="mt-4">
                <button
                  type="button"
                  className={classNames("px-4 py-2 rounded text-white font-bold  mr-2", activating ? 'bg-blue-200' : 'bg-blue-400 hover:bg-blue-500')}
                  disabled={activating}
                  onClick={handleActivateClick}
                >
                  Activate
                </button>
                <button
                  type="button"
                  className="px-4 py-2 border border-blue-400 rounded text-blue-400 font-bold hover:bg-blue-100"
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

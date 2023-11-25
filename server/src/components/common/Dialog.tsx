import { Fragment, ReactNode } from "react";
import { Dialog as HeadlessDialog, Transition } from "@headlessui/react";

type Props = {
  open: boolean;
  title?: ReactNode;
  children: ReactNode;
  onClose: () => void;
};

export default function Dialog({ title, open, children, onClose }: Props) {
  return (
    <Transition appear={true} show={open} as={Fragment}>
      <HeadlessDialog
        className="fixed inset-0 z-10 overflow-y-auto"
        onClose={onClose}
      >
        <div className="min-h-screen px-4 text-center">
          <Transition.Child
            as={Fragment}
            enter="ease-out duration-300"
            enterFrom="opacity-0"
            enterTo="opacity-100"
            leave="ease-in duration-200"
            leaveFrom="opacity-100"
            leaveTo="opacity-0"
          >
            <HeadlessDialog.Overlay className="fixed inset-0 bg-black opacity-30" />
          </Transition.Child>
          <span
            className="inline-block h-screen align-middle"
            aria-hidden="true"
          >
            &#8203;
          </span>
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
              {title && (
                <HeadlessDialog.Title className="text-xl font-medium leading-6 text-gray-900">
                  {title}
                </HeadlessDialog.Title>
              )}
              {children}
            </div>
          </Transition.Child>
        </div>
      </HeadlessDialog>
    </Transition>
  );
}

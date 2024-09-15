import { Fragment, ReactNode } from "react";
import { Dialog as HeadlessDialog, Transition } from "@headlessui/react";
import classNames from "classnames";

type Props = {
  open: boolean;
  title?: ReactNode;
  className?: string;
  onClose: () => void;
  children: ReactNode;
};

export default function Dialog({
  title,
  open,
  className = "p-6",
  onClose,
  children,
}: Props) {
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
            <HeadlessDialog.Overlay className="fixed inset-0 bg-black opacity-50" />
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
            <div
              className={classNames(
                "inline-block w-full my-8 text-left align-middle transition-all transform bg-white shadow-xl rounded-lg",
                className,
              )}
            >
              {title && (
                <HeadlessDialog.Title className="text-2xl font-bold text-slate-900 mb-4">
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

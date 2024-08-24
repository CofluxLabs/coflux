import { Fragment, useCallback, useState } from "react";
import { Link, useLocation, useSearchParams } from "react-router-dom";
import classNames from "classnames";
import { Menu, Transition } from "@headlessui/react";
import { IconCheck, IconChevronDown } from "@tabler/icons-react";

import { buildUrl } from "../utils";
import AddEnvironmentDialog from "./AddEnvironmentDialog";
import * as models from "../models";
import EnvironmentLabel from "./EnvironmentLabel";

type Props = {
  environments: Record<string, models.Environment>;
};

export default function EnvironmentSelector({ environments }: Props) {
  const location = useLocation();
  const [searchParams] = useSearchParams();
  const activeEnvironment = searchParams.get("environment");
  const [addEnvironmentDialogOpen, setAddEnvironmentDialogOpen] = useState(
    Object.keys(environments).length == 0,
  );
  const handleAddEnvironmentClick = useCallback(() => {
    setAddEnvironmentDialogOpen(true);
  }, []);
  const handleAddEnvironmentDialogClose = useCallback(() => {
    setAddEnvironmentDialogOpen(false);
  }, []);
  return (
    <Fragment>
      <Menu as="div" className="relative">
        <Menu.Button className="flex items-center gap-1">
          {activeEnvironment ? (
            <EnvironmentLabel
              name={activeEnvironment}
              interactive={true}
              right={
                <IconChevronDown size={14} className="opacity-40 mt-0.5" />
              }
            />
          ) : (
            <span>Select environment...</span>
          )}
        </Menu.Button>
        <Transition
          as={Fragment}
          enter="transition ease-in duration-100"
          enterFrom="opacity-0 scale-95"
          enterTo="opacity-100 scale-100"
          leave="transition ease-in duration-100"
          leaveFrom="opacity-100 scale-100"
          leaveTo="opacity-0 scale-95"
        >
          <Menu.Items
            className="absolute z-10 overflow-y-scroll text-base bg-white rounded-md shadow-lg divide-y divide-slate-100 origin-top mt-1"
            static={true}
          >
            {Object.keys(environments).length > 0 && (
              <div className="p-1">
                {Object.keys(environments).map((environmentName) => (
                  <Menu.Item key={environmentName}>
                    {({ active }) => (
                      <Link
                        to={buildUrl(location.pathname, {
                          ...Object.fromEntries(searchParams),
                          environment: environmentName,
                        })}
                        className={classNames(
                          "flex items-center gap-1 pl-2 pr-3 py-1 rounded whitespace-nowrap text-sm",
                          active && "bg-slate-100",
                        )}
                      >
                        {environmentName == activeEnvironment ? (
                          <IconCheck size={16} className="mt-0.5" />
                        ) : (
                          <span className="w-[16px]" />
                        )}
                        {environmentName}
                      </Link>
                    )}
                  </Menu.Item>
                ))}
              </div>
            )}
            <div className="p-1">
              <Menu.Item>
                {({ active }) => (
                  <button
                    className={classNames(
                      "w-full flex px-2 py-1 rounded whitespace-nowrap text-sm",
                      active && "bg-slate-100",
                    )}
                    onClick={handleAddEnvironmentClick}
                  >
                    Add environment...
                  </button>
                )}
              </Menu.Item>
            </div>
          </Menu.Items>
        </Transition>
      </Menu>
      <AddEnvironmentDialog
        environments={Object.keys(environments)}
        open={addEnvironmentDialogOpen}
        onClose={handleAddEnvironmentDialogClose}
      />
    </Fragment>
  );
}

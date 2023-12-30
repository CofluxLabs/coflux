import { Fragment } from "react";
import { Link, useParams, useSearchParams } from "react-router-dom";
import classNames from "classnames";
import { Menu, Transition } from "@headlessui/react";
import { IconChevronDown } from "@tabler/icons-react";

import { buildUrl } from "../utils";

function classNameForEnvironment(name: string) {
  if (name.startsWith("stag")) {
    return "bg-yellow-400/80 text-slate-700";
  } else if (name.startsWith("prod")) {
    return "bg-purple-500/80 text-slate-100";
  } else {
    return "bg-slate-300/80 text-slate-600";
  }
}

type EnvironmentTagProps = {
  name: string;
};

function EnvironmentTag({ name }: EnvironmentTagProps) {
  return (
    <span
      className={classNames(
        "rounded px-1 text-sm",
        classNameForEnvironment(name)
      )}
    >
      {name}
    </span>
  );
}

type Props = {
  environments: string[];
};

export default function EnvironmentSelector({ environments }: Props) {
  const { project: activeProjectId } = useParams();
  const [searchParams] = useSearchParams();
  const activeEnvironment = searchParams.get("environment");
  return (
    <Menu as="div" className="relative">
      <Menu.Button className="flex items-center gap-0.5 p-1 text-white rounded hover:bg-white/10">
        {activeEnvironment ? (
          <EnvironmentTag name={activeEnvironment} />
        ) : (
          <span>Select environment...</span>
        )}
        <IconChevronDown size={20} className="text-white/50" />
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
          <div className="p-1">
            {environments.map((environmentName) => (
              <Menu.Item key={`${activeProjectId}/${environmentName}`}>
                {({ active }) => (
                  <Link
                    to={buildUrl(`/projects/${activeProjectId}`, {
                      environment: environmentName,
                    })}
                    className={classNames(
                      "flex px-2 py-1 rounded whitespace-nowrap",
                      active && "bg-slate-100"
                    )}
                  >
                    <EnvironmentTag name={environmentName} />
                  </Link>
                )}
              </Menu.Item>
            ))}
          </div>
        </Menu.Items>
      </Transition>
    </Menu>
  );
}

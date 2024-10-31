import { Fragment, useCallback, useState } from "react";
import { Link, useLocation, useSearchParams } from "react-router-dom";
import {
  Menu,
  MenuButton,
  MenuItem,
  MenuItems,
  MenuSeparator,
} from "@headlessui/react";
import {
  IconCheck,
  IconChevronDown,
  IconCornerDownRight,
} from "@tabler/icons-react";

import { buildUrl } from "../utils";
import * as models from "../models";
import EnvironmentLabel from "./EnvironmentLabel";
import AddEnvironmentDialog from "./AddEnvironmentDialog";
import { times } from "lodash";

function traverseEnvironments(
  environments: Record<string, models.Environment>,
  parentId: string | null = null,
  depth: number = 0,
): [string, models.Environment, number][] {
  return Object.entries(environments)
    .filter(([_, e]) => e.baseId == parentId && e.status != "archived")
    .flatMap(([environmentId, environment]) => [
      [environmentId, environment, depth],
      ...traverseEnvironments(environments, environmentId, depth + 1),
    ]);
}

type Props = {
  projectId: string;
  environments: Record<string, models.Environment>;
  activeEnvironmentId: string | undefined;
};

export default function EnvironmentSelector({
  projectId,
  environments,
  activeEnvironmentId,
}: Props) {
  const location = useLocation();
  const [searchParams] = useSearchParams();
  const activeEnvironment = searchParams.get("environment");
  const [addEnvironmentDialogOpen, setAddEnvironmentDialogOpen] =
    useState(false);
  const handleAddEnvironmentClick = useCallback(() => {
    setAddEnvironmentDialogOpen(true);
  }, []);
  const handleAddEnvironmentDialogClose = useCallback(() => {
    setAddEnvironmentDialogOpen(false);
  }, []);
  const noEnvironments =
    Object.values(environments).filter((e) => e.status != "archived").length ==
    0;
  return (
    <Fragment>
      <Menu as="div" className="relative">
        <MenuButton className="flex items-center gap-1">
          {activeEnvironmentId ? (
            <EnvironmentLabel
              projectId={projectId}
              environmentId={activeEnvironmentId}
              interactive={true}
              accessory={
                <IconChevronDown size={14} className="opacity-40 mt-0.5" />
              }
            />
          ) : (
            <span className="flex items-center gap-1 rounded px-2 py-0.5 text-slate-100 hover:bg-white/10 text-sm">
              Select environment...
              <IconChevronDown size={14} className="opacity-40 mt-0.5" />
            </span>
          )}
        </MenuButton>
        <MenuItems
          transition
          anchor={{ to: "bottom start", gap: 4, padding: 20 }}
          className="bg-white flex flex-col overflow-y-scroll shadow-xl rounded-md origin-top transition duration-200 ease-out data-[closed]:scale-95 data-[closed]:opacity-0"
        >
          {Object.keys(environments).length > 0 &&
            traverseEnvironments(environments).map(
              ([environmentId, environment, depth]) => (
                <MenuItem key={environmentId}>
                  <Link
                    to={buildUrl(location.pathname, {
                      environment: environment.name,
                    })}
                    className="flex items-center gap-1 m-1 pl-2 pr-3 py-1 rounded whitespace-nowrap text-sm data-[active]:bg-slate-100"
                  >
                    {environment.name == activeEnvironment ? (
                      <IconCheck size={16} className="mt-0.5" />
                    ) : (
                      <span className="w-[16px]" />
                    )}
                    {times(depth).map((i) =>
                      i == depth - 1 ? (
                        <IconCornerDownRight
                          key={i}
                          size={16}
                          className="text-slate-300"
                        />
                      ) : (
                        <span key={i} className="w-2" />
                      ),
                    )}
                    {environment.name}
                  </Link>
                </MenuItem>
              ),
            )}
          <MenuSeparator className="my-1 h-px bg-slate-100" />
          <MenuItem>
            <button
              className="flex m-1 px-2 py-1 rounded whitespace-nowrap text-sm data-[active]:bg-slate-100"
              onClick={handleAddEnvironmentClick}
            >
              Add environment...
            </button>
          </MenuItem>
        </MenuItems>
      </Menu>
      <AddEnvironmentDialog
        environments={environments}
        open={noEnvironments || addEnvironmentDialogOpen}
        hideCancel={true}
        onClose={handleAddEnvironmentDialogClose}
      />
    </Fragment>
  );
}

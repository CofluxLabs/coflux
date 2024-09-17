import {
  TabGroup,
  TabList,
  Tab as HeadlessTab,
  TabPanels,
  TabPanel,
} from "@headlessui/react";
import classNames from "classnames";
import { ComponentProps, Fragment, ReactElement, ReactNode } from "react";

type TabProps = {
  label: ReactNode;
  disabled?: boolean;
  className?: string;
  children: ReactNode;
};

export function Tab({ className, children }: TabProps) {
  return <TabPanel className={classNames(className)}>{children}</TabPanel>;
}

type Props = ComponentProps<typeof TabGroup> & {
  children: ReactElement<TabProps>[];
};

export default function Tabs({ children, ...props }: Props) {
  return (
    <TabGroup {...props}>
      <TabList className="border-b border-slate-200 px-4">
        {children.map((c, i) => (
          <HeadlessTab
            key={i}
            disabled={c.props.disabled}
            className="text-sm px-2 py-1 border-cyan-500 data-[selected]:border-b-2 data-[selected]:font-semibold outline-none disabled:opacity-30"
          >
            {c.props.label}
          </HeadlessTab>
        ))}
      </TabList>
      <TabPanels as={Fragment}>{children}</TabPanels>
    </TabGroup>
  );
}

import { ReactNode } from "react";
import classNames from "classnames";
import { IconExclamationCircle } from "@tabler/icons-react";

function classNameForEnvironment(
  name: string,
  interactive: boolean | undefined,
) {
  if (name.startsWith("stag")) {
    return classNames(
      "bg-yellow-300/70 text-yellow-900",
      interactive && "hover:bg-yellow-300/60",
    );
  } else if (name.startsWith("prod")) {
    return classNames(
      "bg-fuchsia-300/70 text-fuchsia-900",
      interactive && "hover:bg-fuchsia-300/60",
    );
  } else {
    return classNames(
      "bg-slate-300/70 text-slate-700",
      interactive && "hover:bg-slate-300/60",
    );
  }
}

type Props = {
  name: string;
  size?: "sm" | "md";
  interactive?: boolean;
  warning?: string;
  accessory?: ReactNode;
};

export default function EnvironmentLabel({
  name,
  size,
  interactive,
  warning,
  accessory,
}: Props) {
  return (
    <span
      className={classNames(
        "flex items-center rounded-full",
        size == "sm" ? "px-1 py-px gap-0.5" : "px-2 py-0.5 gap-1",
        classNameForEnvironment(name, interactive),
      )}
      title={warning}
    >
      {warning && <IconExclamationCircle size={size == "sm" ? 12 : 14} />}
      <span
        className={classNames(
          size == "sm" ? "px-px text-xs" : "px-0.5 text-sm",
        )}
      >
        {name}
      </span>
      {accessory}
    </span>
  );
}

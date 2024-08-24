import { ReactNode } from "react";
import classNames from "classnames";

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
      "bg-slate-300/70 text-slate-900",
      interactive && "hover:bg-slate-300/60",
    );
  }
}

type Props = {
  name: string;
  size?: "sm" | "md";
  interactive?: boolean;
  right?: ReactNode;
};

export default function EnvironmentLabel({
  name,
  size,
  interactive,
  right,
}: Props) {
  return (
    <span
      className={classNames(
        "flex items-center gap-1 rounded-full px-2 py-0.5",
        classNameForEnvironment(name, interactive),
      )}
    >
      <span
        className={classNames("px-0.5", size == "sm" ? "text-xs" : "text-sm")}
      >
        {name}
      </span>
      {right}
    </span>
  );
}

import { ReactNode } from "react";
import classNames from "classnames";
import { IconExclamationCircle } from "@tabler/icons-react";
import { useEnvironments } from "../topics";

function classNameForEnvironment(
  name: string | undefined,
  interactive: boolean | undefined,
) {
  if (name?.startsWith("stag")) {
    return classNames(
      "bg-yellow-300/70 text-yellow-900",
      interactive && "hover:bg-yellow-300/60",
    );
  } else if (name?.startsWith("prod")) {
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
  projectId: string;
  environmentId: string;
  size?: "sm" | "md";
  interactive?: boolean;
  warning?: string;
  accessory?: ReactNode;
};

export default function EnvironmentLabel({
  projectId,
  environmentId,
  size,
  interactive,
  warning,
  accessory,
}: Props) {
  const environments = useEnvironments(projectId);
  const environment = environments?.[environmentId];
  return (
    <span
      className={classNames(
        "flex items-center gap-0.5 overflow-hidden",
        size == "sm" ? "px-1 py-px rounded-md" : "px-1.5 py-0.5 rounded-lg",
        classNameForEnvironment(environment?.name, interactive),
      )}
      title={warning}
    >
      {warning && (
        <IconExclamationCircle
          size={size == "sm" ? 12 : 14}
          className="shrink-0"
        />
      )}
      <span
        className={classNames(
          "whitespace-nowrap overflow-hidden text-ellipsis",
          size == "sm" ? "px-px text-xs" : "px-0.5 text-sm",
          environment?.status == 1 && "line-through opacity-50",
        )}
      >
        {environment?.name}
      </span>
      {accessory}
    </span>
  );
}

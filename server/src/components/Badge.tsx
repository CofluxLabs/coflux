import classNames from "classnames";

type Intent = "success" | "danger" | "warning" | "info" | "none";

function classNameForIntent(intent: Intent) {
  switch (intent) {
    case "success":
      return "bg-green-100 text-green-500";
    case "danger":
      return "bg-red-100 text-red-500";
    case "warning":
      return "bg-yellow-100 text-yellow-500";
    case "info":
      return "bg-blue-100 text-blue-500";
    case "none":
      return "bg-slate-100 text-slate-500";
  }
}

type Props = {
  label: string;
  intent: Intent;
};

export default function Badge({ label, intent }: Props) {
  return (
    <span
      className={classNames(
        "rounded-md px-1.5 py-0.5 text-xs uppercase font-bold",
        classNameForIntent(intent)
      )}
    >
      {label}
    </span>
  );
}

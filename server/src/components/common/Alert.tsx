import { ReactNode } from "react";
import { Variant } from "./types";
import classNames from "classnames";

const variantStyles: Record<Variant, string> = {
  primary: "bg-cyan-50 text-cyan-700 border-cyan-600/10",
  secondary: "bg-slate-50 text-slate-700 border-slate-600/10",
  success: "bg-green-50 text-green-700 border-green-600/10",
  warning: "bg-yellow-50 text-yellow-700 border-yellow-600/10",
  danger: "bg-red-50 text-red-700 border-red-600/10",
};

type Props = {
  children: ReactNode;
  variant: Variant;
};

export default function Alert({ variant, children }: Props) {
  return (
    <div
      className={classNames(
        "border p-2 rounded text-sm",
        variantStyles[variant],
      )}
    >
      {children}
    </div>
  );
}

import classNames from "classnames";
import { ButtonHTMLAttributes } from "react";

type Variant = "primary" | "secondary" | "success" | "warning" | "danger";
type Size = "sm" | "md" | "lg";

const variantStyles = {
  primary: "focus:ring-cyan-200",
  secondary: "border-slate-500 focus:ring-slate-200",
  success: "border-green-500 focus:ring-green-200",
  warning: "border-yellow-500 focus:ring-yellow-200",
  danger: "border-red-500 focus:ring-red-200",
};

const outlineStyles = {
  true: "bg-white",
  false: "text-white",
};

const variantOutlineStyles = {
  primary: {
    true: "border-cyan-500/50 text-cyan-500 hover:text-cyan-600 hover:text-cyan-600 hover:border-cyan-500 shadow-cyan-500/30",
    false:
      "border-cyan-500 bg-cyan-500 hover:bg-cyan-600 hover:border-cyan-600 shadow-cyan-800/50",
  },
  secondary: {
    true: "border-slate-500/50 text-slate-500 hover:text-slate-600 hover:text-slate-600 hover:border-slate-500 shadow-slate-500/30",
    false:
      "border-slate-500 bg-slate-500 hover:bg-slate-600 hover:border-slate-600 shadow-slate-800/50",
  },
  success: {
    true: "border-green-500/50 text-green-500 hover:text-green-600 hover:text-green-600 hover:border-green-500 shadow-green-500/30",
    false:
      "border-green-500 bg-green-500 hover:bg-green-600 hover:border-green-600 shadow-green-800/50",
  },
  warning: {
    true: "border-yellow-500/50 text-yellow-500 hover:text-yellow-600 hover:text-yellow-600 hover:border-yellow-500 shadow-yellow-500/30",
    false:
      "border-yellow-500 bg-yellow-500 hover:bg-yellow-600 hover:border-yellow-600 shadow-yellow-800/50",
  },
  danger: {
    true: "border-red-500/50 text-red-500 hover:text-red-600 hover:text-red-600 hover:border-red-500 shadow-red-500/30",
    false:
      "border-red-500 bg-red-500 hover:bg-red-600 hover:border-red-600 shadow-red-800/50",
  },
};

const sizeStyles = {
  sm: "rounded px-2 py-0.5 text-sm",
  md: "rounded-md px-3 py-1",
  lg: "rounded-lg px-4 py-1.5 text-lg",
};

type Props = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: Variant;
  outline?: boolean;
  size?: Size;
};

export default function Button({
  variant = "primary",
  outline = false,
  size = "md",
  className,
  children,
  ...props
}: Props) {
  return (
    <button
      className={classNames(
        "border focus:ring focus:outline-none focus:ring-opacity-50 font-medium text-center shadow-sm",
        variantStyles[variant],
        outlineStyles[outline ? "true" : "false"],
        variantOutlineStyles[variant][outline ? "true" : "false"],
        sizeStyles[size],
        className
      )}
      {...props}
    >
      {children}
    </button>
  );
}

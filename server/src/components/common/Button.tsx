import classNames from "classnames";
import { ButtonHTMLAttributes } from "react";

type Props = ButtonHTMLAttributes<HTMLButtonElement> & {
  outline?: boolean;
  variant?: "primary" | "secondary" | "success" | "warning" | "danger";
  size?: "sm" | "md" | "lg";
};

export default function Button({
  outline = false,
  variant = "primary",
  size = "md",
  className,
  children,
  ...props
}: Props) {
  return (
    <button
      className={classNames(
        "border focus:ring focus:outline-none focus:ring-opacity-50 font-medium text-center shadow-sm",
        {
          "border-cyan-500 focus:ring-cyan-200": variant == "primary",
          "text-cyan-500 hover:text-cyan-600 bg-white hover:bg-cyan-50":
            variant == "primary" && outline,
          "bg-cyan-500 hover:bg-cyan-600 hover:border-cyan-600 text-white":
            variant == "primary" && !outline,
          "border-slate-500 focus:ring-slate-200": variant == "secondary",
          "text-slate-500 hover:text-slate-600 bg-white hover:bg-slate-50":
            variant == "secondary" && outline,
          "bg-slate-500 hover:bg-slate-600 hover:border-slate-600 text-white":
            variant == "secondary" && !outline,
          "border-green-500 focus:ring-green-200": variant == "success",
          "text-green-500 hover:text-green-600 bg-white hover:bg-green-50":
            variant == "success" && outline,
          "bg-green-500 hover:bg-green-600 hover:border-green-600 text-white":
            variant == "success" && !outline,
          "border-yellow-500 focus:ring-yellow-200": variant == "warning",
          "text-yellow-500 hover:text-yellow-600 bg-white hover:bg-yellow-50":
            variant == "warning" && outline,
          "bg-yellow-500 hover:bg-yellow-600 hover:border-yellow-600 text-white":
            variant == "warning" && !outline,
          "border-red-500 focus:ring-red-200": variant == "danger",
          "text-red-500 hover:text-red-600 bg-white hover:bg-red-50":
            variant == "danger" && outline,
          "bg-red-500 hover:bg-red-600 hover:border-red-600 text-white":
            variant == "danger" && !outline,
          "rounded px-2 py-0.5 text-sm": size == "sm",
          "rounded-md px-3 py-1": size == "md",
          "rounded-lg px-4 py-1.5 text-lg": size == "lg",
        },
        className
      )}
      {...props}
    >
      {children}
    </button>
  );
}

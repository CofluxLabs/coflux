import classNames from "classnames";
import { ButtonHTMLAttributes } from "react";

type Props = ButtonHTMLAttributes<HTMLButtonElement> & {
  outline?: boolean;
};

export default function Button({
  outline,
  className,
  children,
  ...props
}: Props) {
  return (
    <button
      className={classNames(
        "border border-cyan-500 focus:ring focus:outline-none focus:ring-cyan-200 focus:ring-opacity-50 rounded-lg font-medium px-3 py-1.5 text-center",
        outline
          ? "text-cyan-500 hover:text-cyan-600 bg-white hover:bg-slate-50"
          : "bg-cyan-500 hover:bg-cyan-600 hover:border-cyan-600 text-white shadow-sm ",
        className
      )}
      {...props}
    >
      {children}
    </button>
  );
}

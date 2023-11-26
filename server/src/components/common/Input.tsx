import classNames from "classnames";
import { ChangeEvent, InputHTMLAttributes, useCallback } from "react";
import { useFieldId } from "./Field";

type Props = Omit<InputHTMLAttributes<HTMLInputElement>, "onChange"> & {
  onChange: (value: string) => void;
};

export default function Input({ onChange, className, ...props }: Props) {
  const id = useFieldId();
  const handleChange = useCallback(
    (ev: ChangeEvent<HTMLInputElement>) => onChange(ev.target.value),
    [onChange]
  );
  return (
    <input
      className={classNames(
        "px-2 py-1 rounded-md text-slate-900 bg-slate-50 shadow-sm border-slate-300 focus:border-cyan-300 focus:ring focus:ring-cyan-200 focus:ring-opacity-50",
        className
      )}
      id={id}
      onChange={handleChange}
      {...props}
    />
  );
}

import { ChangeEvent, FormEvent, useCallback, useState } from "react";
import classNames from "classnames";

import Dialog from "./common/Dialog";
import * as models from "../models";

type ParameterProps = {
  parameter: models.Parameter;
  value: string | undefined;
  onChange: (name: string, value: string) => void;
};

function Parameter({ parameter, value, onChange }: ParameterProps) {
  const handleChange = useCallback(
    (ev: ChangeEvent<HTMLInputElement>) =>
      onChange(parameter.name, ev.target.value),
    [parameter, onChange]
  );
  return (
    <div className="py-1">
      <label className="w-32">
        <span className="font-mono font-bold">{parameter.name}</span>
        {parameter.annotation && (
          <span className="text-gray-500 ml-1 text-sm">
            ({parameter.annotation})
          </span>
        )}
      </label>
      <input
        type="text"
        className="border border-gray-400 rounded px-2 py-1 w-full"
        placeholder={parameter.default}
        value={value == undefined ? "" : value}
        onChange={handleChange}
      />
    </div>
  );
}

type Props = {
  parameters: models.Parameter[];
  open: boolean;
  starting: boolean;
  onRun: (parameters: ["json", string][]) => void;
  onClose: () => void;
};

export default function RunDialog({
  parameters,
  open,
  starting,
  onRun,
  onClose,
}: Props) {
  const [values, setValues] = useState<Record<string, string>>({});
  const handleValueChange = useCallback(
    (name: string, value: string) =>
      setValues((vs) => ({ ...vs, [name]: value })),
    []
  );
  const handleSubmit = useCallback(
    (ev: FormEvent) => {
      ev.preventDefault();
      onRun(parameters.map((p) => ["json", values[p.name] || p.default]));
    },
    [parameters, values, onRun]
  );
  return (
    <Dialog title="Run task" open={open} onClose={onClose}>
      <form onSubmit={handleSubmit}>
        {parameters.length > 0 && (
          <div className="mt-4">
            <h3 className="font-bold uppercase text-gray-400 text-sm">
              Arguments
            </h3>
            {parameters.map((parameter) => (
              <Parameter
                key={parameter.name}
                parameter={parameter}
                value={values[parameter.name]}
                onChange={handleValueChange}
              />
            ))}
          </div>
        )}
        <div className="mt-4">
          <button
            type="submit"
            className={classNames(
              "px-4 py-2 rounded text-white font-bold  mr-2",
              starting ? "bg-slate-200" : "bg-slate-400 hover:bg-slate-500"
            )}
            disabled={starting}
          >
            Run
          </button>
          <button
            type="button"
            className="px-4 py-2 border border-slate-300 rounded text-slate-400 font-bold hover:bg-slate-100"
            onClick={onClose}
          >
            Cancel
          </button>
        </div>
      </form>
    </Dialog>
  );
}

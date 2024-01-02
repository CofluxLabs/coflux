import { FormEvent, useCallback, useState } from "react";
import classNames from "classnames";

import Dialog from "./common/Dialog";
import * as models from "../models";
import Field from "./common/Field";
import Input from "./common/Input";
import Button from "./common/Button";

type ParameterProps = {
  parameter: models.Parameter;
  value: string | undefined;
  onChange: (name: string, value: string) => void;
};

function Parameter({ parameter, value, onChange }: ParameterProps) {
  const handleChange = useCallback(
    (value: string) => onChange(parameter.name, value),
    [parameter, onChange]
  );
  return (
    <Field
      label={<span className="font-mono font-bold">{parameter.name}</span>}
      hint={parameter.annotation}
    >
      <Input
        value={value ?? ""}
        placeholder={parameter.default}
        onChange={handleChange}
        className="w-full"
      />
    </Field>
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
            <h3 className="font-bold uppercase text-slate-400 text-sm">
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
        <div className="mt-4 flex gap-2">
          <Button type="submit" disabled={starting}>
            Run
          </Button>
          <Button type="button" outline={true} onClick={onClose}>
            Cancel
          </Button>
        </div>
      </form>
    </Dialog>
  );
}

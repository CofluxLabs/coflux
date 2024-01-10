import { FormEvent, useCallback, useState } from "react";
import { IconAlertTriangle } from "@tabler/icons-react";

import Dialog from "./common/Dialog";
import * as models from "../models";
import Field from "./common/Field";
import Input from "./common/Input";
import Button from "./common/Button";

type ParameterProps = {
  parameter: models.Parameter;
  value: string | undefined;
  valid: boolean;
  onChange: (name: string, value: string) => void;
};

function Parameter({ parameter, value, valid, onChange }: ParameterProps) {
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
        className="w-full"
        right={
          !valid && (
            <span className="text-yellow-500" title="Must be valid JSON">
              <IconAlertTriangle size={20} stroke={1.5} />
            </span>
          )
        }
        onChange={handleChange}
      />
    </Field>
  );
}

function isValidJson(value: string) {
  try {
    JSON.parse(value);
    return true;
  } catch {
    return false;
  }
}

function validateValues(
  values: Record<string, string>,
  parameters: models.Parameter[]
) {
  return parameters.reduce<Record<string, boolean>>((result, parameter) => {
    const value = values[parameter.name];
    const valid = !value ? !!parameter.default : isValidJson(value);
    return { ...result, [parameter.name]: valid };
  }, {});
}

type Props = {
  target: models.Target;
  open: boolean;
  starting: boolean;
  onRun: (parameters: ["json", string][]) => void;
  onClose: () => void;
};

export default function RunDialog({
  target,
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
      onRun(
        target.parameters.map((p) => ["json", values[p.name] || p.default])
      );
    },
    [target, values, onRun]
  );
  const valuesValid = validateValues(values, target.parameters);
  const invalid = Object.values(valuesValid).some((v) => !v);
  return (
    <Dialog
      title={
        <span className="font-normal">
          <span className="font-mono">{target.target}</span>{" "}
          <span className="text-slate-500 text-sm">({target.repository})</span>
        </span>
      }
      open={open}
      onClose={onClose}
    >
      <form onSubmit={handleSubmit}>
        {target.parameters.length > 0 && (
          <div>
            {target.parameters.map((parameter) => (
              <Parameter
                key={parameter.name}
                parameter={parameter}
                value={values[parameter.name]}
                valid={valuesValid[parameter.name]}
                onChange={handleValueChange}
              />
            ))}
          </div>
        )}
        <div className="mt-4 flex gap-2">
          <Button type="submit" disabled={invalid || starting}>
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

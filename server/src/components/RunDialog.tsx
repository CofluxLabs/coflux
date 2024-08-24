import { FormEvent, useCallback, useState } from "react";

import Dialog from "./common/Dialog";
import * as models from "../models";
import Field from "./common/Field";
import Input from "./common/Input";
import Button from "./common/Button";
import { RequestError } from "../api";
import Alert from "./common/Alert";

function translateArgumentError(error: string | undefined) {
  switch (error) {
    case "not_json":
      return "Not valid JSON";
    default:
      return error;
  }
}
type ArgumentProps = {
  parameter: models.Parameter;
  value: string | undefined;
  error?: string;
  onChange: (name: string, value: string) => void;
};

function Argument({ parameter, value, error, onChange }: ArgumentProps) {
  const handleChange = useCallback(
    (value: string) => onChange(parameter.name, value),
    [parameter, onChange],
  );
  return (
    <Field
      label={<span className="font-mono font-bold">{parameter.name}</span>}
      hint={parameter.annotation}
      error={translateArgumentError(error)}
    >
      <Input
        value={value ?? ""}
        placeholder={parameter.default}
        onChange={handleChange}
      />
    </Field>
  );
}

type Props = {
  target: models.Target;
  activeEnvironmentName: string | undefined;
  open: boolean;
  onRun: (
    environmentName: string,
    arguments_: ["json", string][],
  ) => Promise<void>;
  onClose: () => void;
};

export default function RunDialog({
  target,
  activeEnvironmentName,
  open,
  onRun,
  onClose,
}: Props) {
  const [starting, setStarting] = useState(false);
  const [errors, setErrors] = useState<Record<string, string>>();
  const [values, setValues] = useState<Record<string, string>>({});
  const [environmentName, setEnvironmentName] = useState(
    activeEnvironmentName || "",
  );
  const handleValueChange = useCallback(
    (name: string, value: string) =>
      setValues((vs) => ({ ...vs, [name]: value })),
    [],
  );
  const handleSubmit = useCallback(
    (ev: FormEvent) => {
      ev.preventDefault();
      setStarting(true);
      onRun(
        environmentName,
        target.parameters.map((p) => ["json", values[p.name] || p.default]),
      )
        .then(() => {
          setErrors(undefined);
          setStarting(false);
        })
        .catch((error) => {
          if (error instanceof RequestError) {
            setErrors(error.details);
          } else {
            // TODO
            setErrors({});
          }
        })
        .finally(() => {
          setStarting(false);
        });
    },
    [target, values, environmentName, onRun],
  );
  return (
    <Dialog
      title={
        <span className="font-normal">
          <span className="font-mono font-bold">{target.target}</span>{" "}
          <span className="text-slate-500 text-sm">({target.repository})</span>
        </span>
      }
      open={open}
      onClose={onClose}
    >
      <form onSubmit={handleSubmit}>
        {errors && (
          <Alert variant="warning">
            <p>Failed to start run. Please check errors below.</p>
          </Alert>
        )}
        {/* TODO: handle error? */}
        <Field label="Environment">
          <Input value={environmentName} onChange={setEnvironmentName} />
        </Field>
        {target.parameters.length > 0 && (
          <div>
            {target.parameters.map((parameter, index) => (
              <Argument
                key={parameter.name}
                parameter={parameter}
                value={values[parameter.name]}
                error={errors?.[`arguments.${index}`]}
                onChange={handleValueChange}
              />
            ))}
          </div>
        )}
        <div className="mt-4 flex gap-2">
          <Button type="submit" disabled={starting}>
            Run
          </Button>
          <Button
            type="button"
            outline={true}
            variant="secondary"
            onClick={onClose}
          >
            Cancel
          </Button>
        </div>
      </form>
    </Dialog>
  );
}

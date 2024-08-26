import { FormEvent, useCallback, useState } from "react";

import Dialog from "./common/Dialog";
import * as models from "../models";
import Field from "./common/Field";
import Input from "./common/Input";
import Button from "./common/Button";
import { RequestError } from "../api";
import Alert from "./common/Alert";
import EnvironmentLabel from "./EnvironmentLabel";

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
  projectId: string;
  target: models.Target;
  parameters: models.Parameter[];
  activeEnvironmentId: string;
  open: boolean;
  onRun: (arguments_: ["json", string][]) => Promise<void>;
  onClose: () => void;
};

export default function RunDialog({
  projectId,
  target,
  parameters,
  activeEnvironmentId,
  open,
  onRun,
  onClose,
}: Props) {
  const [starting, setStarting] = useState(false);
  const [errors, setErrors] = useState<Record<string, string>>();
  const [values, setValues] = useState<Record<string, string>>({});
  const handleValueChange = useCallback(
    (name: string, value: string) =>
      setValues((vs) => ({ ...vs, [name]: value })),
    [],
  );
  const handleSubmit = useCallback(
    (ev: FormEvent) => {
      ev.preventDefault();
      setStarting(true);
      onRun(parameters.map((p) => ["json", values[p.name] || p.default]))
        .then(() => {
          setErrors(undefined);
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
    [parameters, values, onRun],
  );
  return (
    <Dialog
      title={
        <div className="flex justify-between items-start font-normal text-base">
          <div className="flex flex-col">
            <span className="font-mono font-bold text-xl leading-tight">
              {target.target}
            </span>
            <span className="text-slate-500 text-sm">
              ({target.repository})
            </span>
          </div>
          <EnvironmentLabel
            projectId={projectId}
            environmentId={activeEnvironmentId}
          />
        </div>
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
        {parameters.length > 0 && (
          <div>
            {parameters.map((parameter, index) => (
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

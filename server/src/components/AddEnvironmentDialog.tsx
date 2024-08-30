import { FormEvent, useCallback, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useTopic } from "@topical/react";

import Dialog from "./common/Dialog";
import Input from "./common/Input";
import Field from "./common/Field";
import Button from "./common/Button";
import * as models from "../models";
import * as api from "../api";
import { RequestError } from "../api";
import Alert from "./common/Alert";
import Select from "./common/Select";
import { randomName } from "../utils";

function translateError(error: string | undefined) {
  switch (error) {
    case "invalid":
      return "Invalid environment name";
    case "exists":
      return "Environment already exists";
    default:
      return error;
  }
}

type Props = {
  environments: Record<string, models.Environment>;
  open: boolean;
  hideCancel?: boolean;
  onClose: () => void;
};

export default function AddEnvironmentDialog({
  environments,
  open,
  hideCancel,
  onClose,
}: Props) {
  const { project: activeProjectId } = useParams();
  const [_projects, { execute }] =
    useTopic<Record<string, models.Project>>("projects");
  const [name, setName] = useState(() => randomName());
  const [baseId, setBaseId] = useState<string | null>(null);
  const [errors, setErrors] = useState<Record<string, string>>();
  const [adding, setAdding] = useState(false);
  const navigate = useNavigate();
  const handleSubmit = useCallback(
    (ev: FormEvent) => {
      ev.preventDefault();
      setAdding(true);
      setErrors(undefined);
      api
        .createEnvironment(activeProjectId!, name, baseId)
        .then(() => {
          navigate(`/projects/${activeProjectId}?environment=${name}`);
          setName(randomName());
          setBaseId(null);
          onClose();
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
          setAdding(false);
        });
    },
    [execute, navigate, name, baseId],
  );
  const environmentNames = Object.entries(environments)
    .filter(([_, e]) => e.status != 1)
    .reduce((acc, [id, e]) => ({ ...acc, [id]: e.name }), {});
  return (
    <Dialog title="Add environment" open={open} onClose={onClose}>
      {errors && (
        <Alert variant="warning">
          <p>Failed to create environment. Please check errors below.</p>
        </Alert>
      )}
      <form onSubmit={handleSubmit}>
        <Field
          label="Environment name"
          error={translateError(errors?.environment)}
        >
          <Input
            type="text"
            value={name}
            className="w-full"
            onChange={setName}
          />
        </Field>
        <Field label="Base environment" error={translateError(errors?.base)}>
          <Select
            options={environmentNames}
            empty="(None)"
            size="md"
            value={baseId}
            onChange={setBaseId}
          />
        </Field>
        <div className="mt-4 flex gap-2">
          <Button type="submit" disabled={adding}>
            Create
          </Button>
          {!hideCancel && (
            <Button
              type="button"
              outline={true}
              variant="secondary"
              onClick={onClose}
            >
              Cancel
            </Button>
          )}
        </div>
      </form>
    </Dialog>
  );
}

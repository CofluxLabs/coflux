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
  open: boolean;
  onClose: () => void;
};

export default function AddEnvironmentDialog({ open, onClose }: Props) {
  const { project: activeProjectId } = useParams();
  const [_projects, { execute }] =
    useTopic<Record<string, models.Project>>("projects");
  const [environmentName, setEnvironmentName] = useState("");
  const [errors, setErrors] = useState<Record<string, string>>();
  const [adding, setAdding] = useState(false);
  const navigate = useNavigate();
  const handleSubmit = useCallback(
    (ev: FormEvent) => {
      ev.preventDefault();
      setAdding(true);
      setErrors(undefined);
      api
        .addEnvironment(activeProjectId!, environmentName)
        .then(() => {
          navigate(
            `/projects/${activeProjectId}?environment=${environmentName}`,
          );
          setEnvironmentName("");
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
    [execute, navigate, environmentName],
  );
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
            value={environmentName}
            className="w-full"
            onChange={setEnvironmentName}
          />
        </Field>
        <div className="mt-4 flex gap-2">
          <Button type="submit" disabled={adding}>
            Create
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

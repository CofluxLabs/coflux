import { FormEvent, useCallback, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useTopic } from "@topical/react";

import Dialog from "./common/Dialog";
import Input from "./common/Input";
import Field from "./common/Field";
import Button from "./common/Button";
import * as models from "../models";
import ErrorsList from "./ErrorsList";

function translateError(error: string) {
  switch (error) {
    case "invalid_environment_name":
      return "Invalid environment name";
    case "environment_already_exists":
      return "Environment already exists";
    default:
      return "Unexpected error";
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
  const [errors, setErrors] = useState<string[]>();
  const [adding, setAdding] = useState(false);
  const navigate = useNavigate();
  const handleSubmit = useCallback(
    (ev: FormEvent) => {
      ev.preventDefault();
      setAdding(true);
      setErrors(undefined);
      execute("add_environment", activeProjectId, environmentName)
        .then(([success, result]: [true, string] | [false, string[]]) => {
          if (success) {
            navigate(
              `/projects/${activeProjectId}?environment=${environmentName}`
            );
            setEnvironmentName("");
            onClose();
          } else {
            setErrors(result);
          }
        })
        .catch(() => {
          setErrors(["exception"]);
        })
        .finally(() => {
          setAdding(false);
        });
    },
    [execute, navigate, environmentName]
  );
  return (
    <Dialog title="Add environment" open={open} onClose={onClose}>
      <ErrorsList
        message="Failed to create environment:"
        errors={errors}
        translate={translateError}
      />
      <form onSubmit={handleSubmit}>
        <Field label="Environment name">
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
          <Button type="button" outline={true} onClick={onClose}>
            Cancel
          </Button>
        </div>
      </form>
    </Dialog>
  );
}

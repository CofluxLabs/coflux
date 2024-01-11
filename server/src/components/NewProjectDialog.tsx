import { FormEvent, useCallback, useState } from "react";
import { useNavigate } from "react-router-dom";

import Dialog from "./common/Dialog";
import Input from "./common/Input";
import Field from "./common/Field";
import Button from "./common/Button";
import * as api from "../api";
import { choose } from "../utils";
import { RequestError } from "../api";
import Alert from "./common/Alert";

const adjectives = [
  "bewitching",
  "captivating",
  "charming",
  "clever",
  "enchanting",
  "funny",
  "goofy",
  "happy",
  "jolly",
  "lucky",
  "majestic",
  "mysterious",
  "mystical",
  "playful",
  "quirky",
  "silly",
  "sleepy",
  "soothing",
  "whimsical",
  "witty",
  "zany",
];

const properNames = [
  "banshee",
  "centaur",
  "chimera",
  "chupacabra",
  "cyclops",
  "djinn",
  "dragon",
  "fairy",
  "gargoyle",
  "genie",
  "gnome",
  "goblin",
  "griffin",
  "grizzly",
  "gryphon",
  "hydra",
  "kraken",
  "leprechaun",
  "mermaid",
  "minotaur",
  "mothman",
  "nymph",
  "ogre",
  "oracle",
  "pegasus",
  "phantom",
  "phoenix",
  "pixie",
  "sasquatch",
  "satyr",
  "shapeshifter",
  "siren",
  "sorcerer",
  "spectre",
  "sphinx",
  "troll",
  "unicorn",
  "vampire",
  "warlock",
  "werewolf",
  "wizard",
  "yeti",
];

function randomProjectName(): string {
  return `${choose(adjectives)}_${choose(properNames)}`;
}

function translateProjectNameError(error: string | undefined) {
  switch (error) {
    case "invalid":
      return "Invalid project name";
    case "exists":
      return "Project already exists";
    default:
      return error;
  }
}

function translateEnvironmentError(error: string | undefined) {
  switch (error) {
    case "invalid":
      return "Invalid environment name";
    default:
      return error;
  }
}

type Props = {};

export default function NewProjectDialog({}: Props) {
  const [projectName, setProjectName] = useState(() => randomProjectName());
  const [environmentName, setEnvironmentName] = useState("development");
  const [errors, setErrors] = useState<Record<string, string>>();
  const [creating, setCreating] = useState(false);
  const navigate = useNavigate();
  const handleClose = useCallback(() => {
    navigate("/projects");
  }, [navigate]);
  const handleSubmit = useCallback(
    (ev: FormEvent) => {
      ev.preventDefault();
      setCreating(true);
      setErrors(undefined);
      api
        .createProject(projectName, environmentName)
        .then(({ projectId }) => {
          navigate(`/projects/${projectId}?environment=${environmentName}`);
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
          setCreating(false);
        });
    },
    [navigate, projectName, environmentName],
  );
  return (
    <Dialog title="New project" open={true} onClose={handleClose}>
      {errors && (
        <Alert variant="warning">
          <p>Failed to create project. Please check errors below.</p>
        </Alert>
      )}
      <form onSubmit={handleSubmit}>
        <Field
          label="Project name"
          error={translateProjectNameError(errors?.projectName)}
        >
          <Input type="text" value={projectName} onChange={setProjectName} />
        </Field>
        <Field
          label="Initial environment name"
          error={translateEnvironmentError(errors?.environment)}
        >
          <Input
            type="text"
            value={environmentName}
            onChange={setEnvironmentName}
          />
        </Field>
        <div className="mt-4 flex gap-2">
          <Button type="submit" disabled={creating}>
            Create
          </Button>
          <Button
            type="button"
            outline={true}
            variant="secondary"
            onClick={handleClose}
          >
            Cancel
          </Button>
        </div>
      </form>
    </Dialog>
  );
}

import { FormEvent, useCallback, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useTopic } from "@topical/react";

import Dialog from "./common/Dialog";
import Input from "./common/Input";
import Field from "./common/Field";
import Button from "./common/Button";
import * as models from "../models";
import { choose } from "../utils";
import ErrorsList from "./ErrorsList";

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

function translateError(error: string) {
  switch (error) {
    case "invalid_project_name":
      return "Invalid project name";
    case "project_already_exists":
      return "Project already exists";
    case "invalid_environment_name":
      return "Invalid environment name";
    default:
      return "Unexpected error";
  }
}

type Props = {};

export default function NewProjectDialog({}: Props) {
  const [_projects, { execute }] =
    useTopic<Record<string, models.Project>>("projects");
  const [projectName, setProjectName] = useState(() => randomProjectName());
  const [environmentName, setEnvironmentName] = useState("development");
  const [errors, setErrors] = useState<string[]>();
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
      execute("create_project", projectName, environmentName)
        .then(([success, result]: [true, string] | [false, string[]]) => {
          if (success) {
            navigate(`/projects/${result}?environment=${environmentName}`);
          } else {
            setErrors(result);
          }
        })
        .catch(() => {
          setErrors(["exception"]);
        })
        .finally(() => {
          setCreating(false);
        });
    },
    [execute, navigate, projectName, environmentName]
  );
  return (
    <Dialog title="New project" open={true} onClose={handleClose}>
      <ErrorsList
        message="Failed to create project:"
        errors={errors}
        translate={translateError}
      />
      <form onSubmit={handleSubmit}>
        <Field label="Project name">
          <Input
            type="text"
            value={projectName}
            className="w-full"
            onChange={setProjectName}
          />
        </Field>
        <Field label="Initial environment name">
          <Input
            type="text"
            value={environmentName}
            className="w-full"
            onChange={setEnvironmentName}
          />
        </Field>
        <div className="mt-4 flex gap-2">
          <Button type="submit" disabled={creating}>
            Create
          </Button>
          <Button type="button" outline={true} onClick={handleClose}>
            Cancel
          </Button>
        </div>
      </form>
    </Dialog>
  );
}

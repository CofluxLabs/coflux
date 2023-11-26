import { FormEvent, useCallback, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useTopic } from "@topical/react";

import Dialog from "./common/Dialog";
import Input from "./common/Input";
import Field from "./common/Field";
import Button from "./common/Button";
import * as models from "../models";
import { choose } from "../utils";

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

type Props = {};

export default function NewProjectDialog({}: Props) {
  const [_projects, { execute }] =
    useTopic<Record<string, models.Project>>("projects");
  const [projectId, setProjectId] = useState(() => randomProjectName());
  const [environmentName, setEnvironmentName] = useState("development");
  const [creating, setCreating] = useState(false);
  const navigate = useNavigate();
  const handleClose = useCallback(() => {
    navigate("/projects");
  }, [navigate]);
  const handleSubmit = useCallback(
    (ev: FormEvent) => {
      ev.preventDefault();
      setCreating(true);
      execute("create_project", projectId, environmentName)
        .then(() => {
          navigate(`/projects/${projectId}?environment=${environmentName}`);
        })
        .catch(() => {
          // TODO
        })
        .finally(() => {
          setCreating(false);
        });
    },
    [execute, navigate, projectId, environmentName]
  );
  return (
    <Dialog title="New project" open={true} onClose={handleClose}>
      <form onSubmit={handleSubmit}>
        <Field label="Project ID">
          <Input
            type="text"
            value={projectId}
            className="w-full"
            onChange={setProjectId}
          />
        </Field>
        <Field label="Environment name">
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

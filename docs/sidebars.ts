import type { SidebarsConfig } from "@docusaurus/plugin-content-docs";

const sidebars: SidebasConfig = {
  docs: [
    "intro",
    {
      type: "category",
      label: "Getting started",
      items: ["workflows", "server", "agents", "runs"],
    },
    {
      type: "category",
      label: "Advanced",
      items: ["sensors", "stubs"],
    },
  ],
};

export default sidebars;

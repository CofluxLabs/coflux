import type { SidebarsConfig } from "@docusaurus/plugin-content-docs";

const sidebars: SidebarsConfig = {
  docs: [
    "intro",
    {
      type: "category",
      label: "Getting started",
      items: [
        "getting_started/workflows",
        "getting_started/server",
        "getting_started/agents",
        "getting_started/runs",
      ],
    },
    "concepts",
    "async",
    "retries",
    "caching",
    "deferring",
    "memoising",
    "logging",
    {
      type: "category",
      label: "Advanced",
      items: ["sensors", "stubs"],
    },
  ],
};

export default sidebars;

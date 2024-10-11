# Concepts

This page outlines the main concepts in Coflux.

## Projects

A Coflux _server_ can host multiple _projects_. Data for each project is isolated from each other, and orchestration is handled by a dedicated process for each project.

## Environments

A project can contain multiple environments. These may be mapped to deployment environments (e.g., production, staging, development), or separated further - for example a production environment per customer, or a development environment per developer.

### Environment inheritance

By default there is isolation between environments within a project - for example, workflows, runs, results are separated. But environments can be arranged into a hierarchy. This allows cached results to be inherited from parent environments, and for steps to be _re-run_ in a 'child' environment.

For example, a `development` environment can inherit from a `production` environment, allowing you to re-run whole workflows, or specific steps within a workflow, in a development environment, experimenting with changes to the code without having to re-run the whole workflow from scratch. When working with a team on a shared project, you might choose to set up separate environments for each engineer, or even create environments temporarily to work on specific features.

This makes it easier to diagnose issues that arise in a production environment by retrying individual steps locally, and trying out code changes safely.

## Agents

An _agent_ is a process that hosts _repositories_. An agent connects to the server and is associated with a specific project and environment. The agent waits for commands from the server telling it to execute specific tasks, and the agent monitors and reports progress of these executions back to the server.

This model of having agents connect to the server provides flexibility over where and how agents are run. During development an agent can run locally on a laptop, restarting automatically as code changes are made. Or multiple agents can run in the cloud, or on dedicated machines - or a combination. An agent can be started with specific environment variables associated with the deployment environment (e.g., production access keys).

## Workflows

A _workflow_ is defined in a repository, in code. Additionally, _tasks_ can be defined, and called from workflows (or other tasks).

Workflows and tasks are collectively referred to as _targets_, although workflows are really just special forms of tasks, from which runs can be started. You can think of the distinction between workflows and tasks a bit like the distinction between public and private functions in a module.

Workflows need to be registered with a project and environment so that they appear in the UI. This can be done explicitly (e.g., for a production environment as part of a build process), or automatically by an agent when it starts/restarts (using the `--register` or `--dev` flag).

## Runs

When a workflow is submitted, this initiates a _run_. A run is made up of _steps_, which each correspond to a target to be executed. The target (a workflow or task) can call other tasks, which cause those to scheduled as steps. Each step has at least one associated _execution_. Steps can be retried (manually or automatically), which will lead to multiple executions being associated with the step.

# Assets

Executions can 'persist' _assets_ (files or directories) so that they can be shared with other executions. A persisted asset is given a reference, which must be passed to other executions so that it can be 'restored'.

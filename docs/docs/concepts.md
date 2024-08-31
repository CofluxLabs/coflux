# Concepts

This page outlines the main concepts in Coflux.

## Projects

An instance of a Coflux _server_ may host multiple _projects_, and a project is separated into _environments_. The data in each project are isolated from each other. With a project, environments can be defined in a hierarchy, such that cache data can be inherited from child environments. For example, a `development` environment can inherit from a `production` environment, allowing you to re-run workflows, or parts of workflows, in a development environment, experimenting with changes to the code without having to re-run the whole workflow. When working with a team on a single server, you can setup separate environments for each developer, or even create environments temporarily to work on specific features.

## Agents

An _agent_ is a process that hosts _repositories_. An agent connects to the server and is associated with a specific project and environment.

When the agent starts, it registers _manifests_ for the repositories that it's hosting, and then waits for commands from the server telling it to execute specific tasks.

## Workflows

A _workflow_ is defined in a repository in code. A workflow is made up of _tasks_ that are joined together by calling each other.

Workflows and tasks are collectively referred to as _targets_, although workflows are really just specical forms of tasks, which can be scheduled. You can think of the distinction between workflows and tasks a bit like the distinction between public and private functions in a module.

## Runs

When a workflow is scheduled, this initiates a _run_. A run is made up of _steps_, which each correspond to a target to be executed. The target (a workflow or task) can call other tasks, which cause those to scheduled as steps. Each step has at least one associated _execution_. Steps can be retried (manually or automatically), which will lead to multiple executions being associated with the step.

# Assets

Executions can 'persist' _assets_ (files or directories) so that they can be shared with other executions. A persisted asset is given a reference, which must be passed to other executions so that it be be 'restored'.

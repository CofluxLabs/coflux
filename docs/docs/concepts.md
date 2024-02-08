# Concepts

This page outlines the main concepts in Coflux.

## Projects

An instance of a Coflux _server_ may host multiple _projects_. Projects are further sub-divided into _environments_.

The expectation is that the same (or similar) workflows exist in each environment of a project. You might have environments for, e.g., 'production', 'staging', 'development/joe', etc. A shared server can be useful for referring colleagues to runs in specific projects/environments.

Projects (and environments) are relatively well isolated from each other - each have their own database and orchestrator process, though they are of course still sharing the same machine resources.

## Agents

An _agent_ is a process that hosts _repositories_. An agent connects to the server and is associated with a specific project and environment.

When the agent starts, it reports _manifests_ for the repositories that it's hosting, and then waits for commands from the server telling it to execute specific tasks.

## Workflows

A _workflow_ is defined in a repository in code. A workflow is made up of _tasks_ that are joined together by calling each other.

Workflows and tasks are collectively referred to as _targets_, although workflows are really just specical forms of tasks, which can be scheduled. You can think of the distinction between workflows and tasks a bit like the distinction between public and private functions in a module.

## Runs

When a workflow is scheduled, this initiates a _run_. A run is made up of _steps_, which each correspond to a target to be executed. The target (a workflow or task) can call other tasks, which cause those to scheduled as steps. Each step has at least one associated _execution_. Steps can be retried (manually or automatically), which will lead to multiple executions being associated with the step.

# Assets

Executions can 'persist' _assets_ (files or directories) so that they can be shared with other executions. A persisted asset is given a reference, which must be passed to other executions so that it be be 'restored'.

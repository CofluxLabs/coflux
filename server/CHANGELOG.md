## 0.3.0

Enhancements:

- Re-works environments so that results can be shared across environments, based on a hierarchy.

## 0.2.5

Fixes:

- Upgrades and pins versions of the base images used in the Docker image.

## 0.2.4

Fixes:

- Handling (file-based) repositories containing slashes in the frontend.

## 0.2.3

Fixes:

- Creating Git tag as part of the release.

## 0.2.2

Fixes:

- Handling of 'wait' arguments that aren't present (e.g., because they have default values).

## 0.2.1

Enhancements:

- Updated graph rendering in web UI, using elkjs.

Fixes:

- Reliable cancellation of recurrent (i.e., sensor) runs.
- Rendering of sensor runs page in web UI.

## 0.2.0

Features:

- Supports persisting and restorig assets (files or directories) within tasks, and previewing these in the web UI.
- Supports explicitly waiting for executions in specific parameters before starting a task.

## 0.1.1

Enhancements:

- Supports configuring the data directory from an environment variable.

## 0.1.0

First public release.

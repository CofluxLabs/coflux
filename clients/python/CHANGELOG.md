## 0.5.0

Enhancements:

- Updates CLI configuration to use TOML (instead of YAML).
- Uses new serialisation format, and adds serialisers for Pandas, Pydantic and pickle.
- Supports using S3 as blob store.
- Replaces `cf.restore_asset(asset)` with `asset.restore()` (for consistency with `execution.result()`).
- More types can be passed to log functions (including executions and assets), and specifying a log 'template' is now optional.

Fixes:

- Fixes submitting a workflow run through the CLI uses the workflow configuration registered with the server, matching the behaviour of the UI.
- Fixes flushing stdout/stderr at end of execution.

## 0.4.0

Enhancements:

- Adds CLI command for registering manifests.
- Adds CLI command for starting the server.
- Adds a '--dev' to the `agent` command (equivalent to `--reload` and `--register`).
- Tidies up command naming.

Fixes:

- Support for 'stub' targets.

## 0.3.0

Enhancements:

- Updates client/agent to use re-worked environments.
- Updates CLI to: add commands for managing environments; replace 'init' command with simpler 'configure' command; renamed 'workflow.run' to 'workflow.schedule'.

## 0.2.6

Fixes:

- Loading of file-based (as opposed to module-based) repositories with the agent (i.e., `coflux agent.run path/to/repo.py`).

## 0.2.5

Enhancements:

- The 'wait_for' option has been renamed to 'wait', and now supports boolean/string values (e.g., `wait=True`, or `wait="foo, bar"`).

## 0.2.4

Enhancements:

- Executions are started in spawned (rather than forked) processes, and better handle interrupt signals (SIGINT) for more graceful shutdown.

## 0.2.3

Features:

- Supports persisting and restoring assets (`persist_asset(...)`, `restore_asset(...)`).
- Supports explicitly waiting for for executions (`wait_for={...}`).

## 0.2.2

First (official) public release.

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

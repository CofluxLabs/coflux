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

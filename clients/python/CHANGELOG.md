## 0.2.4

Enhancements:

- Executions are started in spawned (rather than forked) processes, and better handle interrupt signals (SIGINT) for more graceful shutdown.

## 0.2.3

Features:

- Supports persisting and restoring assets (`persist_asset(...)`, `restore_asset(...)`).
- Supports explicitly waiting for for executions (`wait_for={...}`).

## 0.2.2

First (official) public release.

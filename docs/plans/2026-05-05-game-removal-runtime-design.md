# Game Removal Runtime Design

## Context

Issue #3 requests that deleting a game should not delete play records. The current UI has a single destructive action named "删除游戏" that removes the library entry and cover cache, which also removes play time and status history.

Gala now shares Wine prefixes by runtime profile. Because a prefix may be used by multiple games, per-game removal cannot blindly delete a Wine prefix.

## Goals

- Preserve play records when the user only wants to remove a game's runnable environment.
- Provide a separate action that truly removes the game from the library.
- Avoid deleting shared Wine configuration while another configured game still uses the same profile.
- Make environment setup explicit: a game is configured before it can be launched.

## User Model

Each game has two separate states:

- Library record: title, cover, VNDB metadata, status, favorite flag, play time, and executable path.
- Runtime environment: whether the game has a configured runnable Wine/native environment.

The user-facing actions are:

- "移除运行环境": keep the library record and play history, but make the game unavailable for launch until its environment is configured again.
- "从库中移除": remove the library record and related local metadata, including play time and cover cache.

## Runtime Deletion Rule

Both actions check whether the game's runtime profile is still used by any other configured game.

- If no other configured game uses that prefix, delete the corresponding Wine configuration by default.
- If another configured game uses the same prefix, keep the shared Wine configuration and only update/remove the current game.

This deletes only the Wine prefix for the runtime profile. It does not delete the global Wine runtime, fonts, helper tools, or original game files.

## Launch Flow

Adding a game creates the library entry but does not initialize a Wine prefix immediately.

The detail page primary action is state-based:

- Not configured: "配置环境"
- Configuring: "正在配置..."
- Configured: "启动"
- Running: "运行中..."

"启动" does not silently configure an environment. The user explicitly configures the environment first, then launches the game.

## Data Model

Add a runtime configuration marker to `Game`, for example `isRuntimeConfigured`.

Existing library entries should decode with a conservative default:

- If the stored `bottleConfig.prefixPath` is not empty, treat the game as configured.
- If it is empty, treat the game as not configured.

This keeps existing user libraries usable after upgrade.

## UI Naming

Recommended labels:

- Context menu: "移除运行环境"
- Context menu: "从库中移除"
- Detail primary button: "配置环境" / "启动"

"卸载运行环境" is avoided because it can sound like uninstalling the global Wine runtime.

## Testing

Tests should cover:

- Removing runtime keeps the game in the library and preserves play time.
- Removing from library deletes the game record and cover cache.
- A Wine prefix is deleted when the removed game is the last configured user of that prefix.
- A shared Wine prefix is kept when another configured game still uses it.
- Existing JSON without the new runtime marker decodes correctly.

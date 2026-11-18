# lock-mute

A small macOS daemon that mutes sound when you lock the screen and restores it when you unlock.

- One Swift file with system frameworks only.
- Runs as a per-user LaunchAgent. No root, no polling.
- Waits for macOS screen lock and unlock notifications.

## Install

Install the Xcode Command Line Tools with `xcode-select --install`, then run
these commands from your macOS desktop session.

```sh
git clone https://github.com/leo-mathurin/lock-mute.git
cd lock-mute
make install
```

This builds the binary, copies it to `~/Library/Application Support/lock-mute/`,
writes `~/Library/LaunchAgents/local.lock-mute.plist`, and starts the agent.
The agent starts again at each login.

## Uninstall

```sh
make uninstall
```

This stops the agent and removes the two paths above.

## Behavior

- A screen lock mutes the default output device. Sleep or the screen saver
  alone do not, unless they also lock the screen.
- Unlock restores sound on the output that the agent muted. Sound that was
  already muted before lock stays muted.
- The volume level and the microphone do not change.
- If the screen is already locked when the daemon starts, it mutes immediately.

## Limits

- Only the default output device at the time of the lock is muted. A device
  that becomes the default output during the lock is not muted.
- If the agent restarts while the screen is locked, it loses the mute state
  from before the lock.
- Some outputs have no mute control, for example many HDMI and DisplayPort
  monitors. The daemon does not change these outputs and writes an error to
  the log.
- With Fast User Switching, each user must install their own copy.

## Commands

```sh
make build      # compile to build/lock-mute
make test       # simulate lock and unlock without locking the screen
make status     # show the LaunchAgent state
build/lock-mute status   # print muted, unmuted, or unsupported
build/lock-mute mute     # mute now
build/lock-mute unmute   # unmute now
```

`make test` mutes the output for a moment, then restores the initial state.

## Logs

```sh
log show --last 1h --predicate 'subsystem == "local.lock-mute"'
```

# Advanced usage

Two patterns for getting more out of an isolated container: **bridging out** to
the host for things the container can't do, and **staying in** — running whole
test environments fully sandboxed.

---

## Bridging to the host

klaus isolates the container on purpose: no host GUI, and the network is locked
down. But some things can only happen on the host — running an app on an
Android emulator, opening a GUI, hitting hardware. The pattern for those is
**keep the work on the host, and bridge only the result into the container**
through the one channel that already crosses the boundary: the mounted project
directory.

### The pattern

The current directory is mounted into the container, so it's shared, live, in
both directions. Anything the host writes there, Claude sees; anything Claude
writes there, the host sees. So:

- **The host does the thing** it's suited for (emulator, GUI app, a device).
- **The host writes output/logs into the project directory.**
- **Claude reads those files inside the container** and reacts — reads a stack
  trace, greps a log, adjusts code.

Claude never starts the host process; it just sees what the host leaves behind.

### Example: run on an Android emulator, read the logs in klaus

The emulator runs on the host (it needs a GUI and hardware acceleration the
container doesn't have). Point its logcat at the project directory:

```bash
# on the HOST, from the project root:
adb logcat > ./logs/app.log &
./gradlew installDebug && adb shell am start -n com.example/.MainActivity
```

Now inside klaus:

```bash
klaus         # then, e.g.: "read ./logs/app.log and find the crash"
```

Claude reads `./logs/app.log` like any project file. Same idea for a GUI app, a
local server, or a hardware test rig: run it on the host, tee its output into
the mount, work on it in the container.

### ⚠️ Logs can carry secrets into the sandbox

This bridge partly undoes the isolation that klaus gives you — you're
deliberately piping host activity into the sandbox. Logs are the usual
offender: they often contain tokens, environment variables, absolute host
paths, internal hostnames, session IDs, or secrets inside stack traces. Once a
log lands in the mounted directory, Claude can read all of it.

So bridge **deliberately, not blindly**:

- **Log what you need, not everything.** Filter before writing
  (`adb logcat MyTag:D *:S`, `grep`, redact) rather than dumping the full
  firehose into the mount.
- **Keep the bridge files scoped** — a `./logs/` dir you can review, not a
  home-directory logfile you happen to mount in.
- **Treat anything you write into the mount as visible to Claude.** If it
  shouldn't be, don't put it there.

---

## Test environments inside the container

The opposite of bridging out: a lot of real testing runs *entirely* inside the
container, no device or host needed. If your tests are written to be
self-contained — in-process servers, throwaway temp databases, headless UI —
Claude can run the whole suite in the sandbox and iterate on failures.

Container-safe test styles (all run under the `kmp` module's JDK + Gradle):

- **Pure JVM unit tests** — `./gradlew jvmTest`. No display, no network.
- **In-process server integration tests** — start an embedded Ktor/Netty server
  inside the test on a local port, hit it, tear it down. Nothing binds outside
  the container.
- **Throwaway data** — tests that create temp dirs / a `--tmp` SQLite DB never
  touch real state, so they're safe to run repeatedly in the sandbox.
- **Headless web tests** — `./gradlew jsBrowserTest` / `wasmJsBrowserTest`
  (Karma drives headless Chrome via Gradle).
- **Multi-process suites** — an e2e script that launches a throwaway server plus
  a couple of client processes, all in the mounted dir, with port pre-flighting
  and cleanup traps, runs fine as one sandboxed process tree.

What does **not** run in the container: anything needing a real device or
emulator (`adb`, Android instrumented tests), the OS keychain/keystore (tests
fake it), or actual GUI rendering on a screen. For those, use the host bridge
above — run on the host, read results in the container.

The takeaway: structure tests to be self-contained (embedded servers, temp
state, headless) and they double as your sandboxed inner loop — Claude runs
them, reads failures, fixes, re-runs, without ever leaving the container.

---

## Loosening permissions

By default Claude Code asks before each action — keep that; it's the safe
default and klaus doesn't change it.

But inside klaus the blast radius is already small: Claude can only touch the
mounted directory and only reach the Anthropic API. So this is a reasonable
place to let it run without the prompts, per project, when you trust the repo:

```bash
klaus --dangerously-skip-permissions
```

That flag is passed straight through to `claude` and applies only to that run —
the next plain `klaus` prompts as usual. It's a per-run choice, not a saved
setting, so there's nothing to undo. Only do it in a directory whose contents
(and `.env`) you're fine with Claude modifying freely.

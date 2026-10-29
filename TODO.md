# sbx TODO

Features discussed but not yet implemented.

## System scope and services

Containerize system services, e.g. those installed by `.deb` packages, the
same way as desktop software and development projects.

### Scopes and search path
Look up containers, templates, images and `local.yml` in the user's
directories, then `/etc/sbx` (admin), then `$SBX_LIB` (vendor, e.g.
`/usr/lib/sbx` for packages).  A file earlier in the path shadows a later
one, an override can import the shadowed file by path.  System scope homes
in `/var/lib/sbx/containers/<name>`, via `StateDirectory=` for units
with `User=`.  Machine defaults, e.g. a proxy, in `/etc/sbx/local.yml`.

### Single file containers and templates
`<name>.yml` next to `<name>/config.yml`, for the latter when scripts
are shipped.  Packages drop `/usr/lib/sbx/containers/<name>.yml` and use
`ExecStart=/usr/bin/sbx run <name>` in their unit.

### Service support
`sd_notify`, binding `NOTIFY_SOCKET`, and socket activation, passing
`LISTEN_FDS`, where `LISTEN_PID` does not match inside a PID namespace.
Verify what bwrap leaves root without a user namespace, refuse root or drop
all capabilities until then.  `listen-port` with addresses, e.g.
`0.0.0.0/443`.

## Security primitives

### cwd blacklist
Refuse to run a sandbox whose cwd is bound from a sensitive host path. Override
with `--force-cwd`. Wrinkle: cwd handling is a property of the `bind` action
(`cwd: true`), not a top-level concept. The check belongs inside `action_bind`
when `cwd: true` is set. Must `realpath`-resolve before comparing to the
blacklist, and must catch ancestry (cwd inside a blacklisted dir, not just
exact match).

Default blacklist: `$HOME`, `$HOME/.ssh`, `$HOME/.gnupg`, `$HOME/.aws`,
`$HOME/.config`, `$HOME/.local`, `$HOME/Documents`, `$HOME/Desktop`,
`$HOME/Downloads`, `/`, `/etc`, `/root`.

### Network domain allowlist
Restrict a sandbox's internet access to listed domains, via a proxy.

### Wayland socket filtering
Create a `security-context-v1` socket per sandbox so wlroots compositors hide
privileged protocols (`virtual-keyboard`, `wlr-screencopy`,
`wlr-data-control`, `foreign-toplevel`).  Needs a small Wayland client.  With
a nested X server, e.g. Xwayland per sandbox, X11 applications would be
isolated by construction rather than by sbx-x11's filtering.

### sbx-x11 extension resources
Requests of allowed extensions are checked against known opcodes, but not all
check that the resources they change are the sandbox's, e.g. RENDER
FreePicture, XFIXES DestroyRegion, SYNC SetCounter.

### sbx-x11 follow-ups
Performance, measured with x11perf on Intel Iris Xe:

| Test (per second)   | Direct  | sbx-x11 | Two chained |
|---------------------|---------|---------|-------------|
| PutImage 500x500    | 9,390   | 2,570   |             |
| ShmPutImage 500x500 | 13,900  | 3,630   | 3,090       |
| GetProperty         |         | 36,200  | 21,900      |
| NoOperation         |         | 3.2 M   |             |

x11perf syncs each image with a 1 pixel GetImage, so these are round trip
bound.  Profiling shows the proxy mostly idle in epoll, so the cost is wake
up latency per hop, ~18 µs per round trip, ~60 µs when the server is busy
between requests.  Open: the direct numbers were taken on the host, outside
any sandbox, and a first hop appears to cost ~190 µs.  Compare with
`x11-trusted` in a sandbox to separate proxy and sandbox costs.  A C or Rust
rewrite would cut processing, not wake ups.

Screen contents under a sandbox window, unpainted (background None) or
overlapped by another window, are readable without a compositing manager.
Fix: track which drawables are windows and deny reading windows into
readable drawables, e.g. `GetImage`, `CopyArea` to a pixmap, RENDER sources.

Other: check `PointerRoot` focus.  `NV-GLX` is opaque and passed unfiltered.  Offline tests:
`tests/sbx-x11`.

### readonly-overlay action
Bind a host path read-only with a writable tmpfs upper layer. Writes go to
the overlay and are discarded on sandbox exit. Solves vscode extensions, npm
cache poisoning, pip cache poisoning, language server binaries. bwrap supports
this via `--overlay-src` / `--overlay`.

## Rules library

### Credential rules
Selective auth binds, one rule per tool. Each binds only the credential
file(s) that tool needs, nothing else.

- `claude-creds` - `~/.claude/.credentials.json`
- `gh-creds` - `~/.config/gh/hosts.yml`
- `npm-creds` - `~/.npmrc`
- `pip-creds` - `~/.pypirc`
- `aws-creds` - `~/.aws/credentials`, `~/.aws/config`
- `cargo-creds` - `~/.cargo/credentials.toml`

### vscode-shared rule
Shared read-only `~/.vscode/extensions` via `--extensions-dir`, per-sandbox
writable `--user-data-dir` under `$SANDBOX_HOME/.vscode-user`. Avoids
re-installing extensions per sandbox.

### Shared cache rules
Read-only binds of `~/.npm`, `~/.cache/pip`, `~/.cargo/registry`. Reduces
repeated downloads. Consider readonly-overlay variants for cases where the
tool needs to think it can write.

## Host-side

### sbx install-shims / uninstall-shims
Drop symlinks in `~/.local/bin/sbx-shims/` named after blocked tools (`npm`,
`npx`, `pip`, `pip3`, `pipx`, `node`, `cargo`, `code`, etc). Each symlink
points to the sbx binary itself.

sbx detects shim mode via `os.path.basename(os.path.dirname(sys.argv[0])) == 'shims'`.
In shim mode:
- If `SANDBOX` env var is set (already inside a sandbox), find the real
  binary via `which -a` excluding the shim dir and exec it.
- Otherwise, refuse with a message suggesting `sbx run`. Honor `SBX_BYPASS=1`
  as an escape hatch that execs the real binary.

Tool list configurable in `~/.config/sbx/shims.yml`.

## Worktree workflow

### Worktree pre-hook (not a built-in action)
A template ships a `pre-hook` script that creates a `git worktree`, and a
`delete-hook` (or `post-hook`) that removes it. Verify the existing hook
support is sufficient for this; if not, fix it.

This is the `claude-worktree` template that motivates parallel Claude
sessions on one repo. Worth building and shipping as a reference template
once the security primitives are in place.

## Other

### Shared credential access via pre-hook
The general pattern: pre-hook copies/decrypts credentials from a host vault
(pass, 1password, plain file, whatever) into `$SANDBOX_HOME` before bwrap
starts. No sbx changes needed - just document the pattern with examples.

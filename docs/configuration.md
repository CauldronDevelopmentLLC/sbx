# Configuration

A sandbox's ``config.yml`` may contain:

- ``use``     - Rules to apply.  Set by ``sbx create``, overridden by ``-r``.
- ``command`` - Command and arguments.  In ``global.yml``, the default for new
  sandboxes.
- ``imports`` - Configs to import rules from, relative to the importing file.
  Later imports override earlier ones and the importing config overrides all.
- ``rules``   - Named lists of actions, see *Actions*.  If the first item is a
  string, it is the rule's help shown by ``sbx list-rules``.
- ``create-hook``, ``pre-hook``, ``post-hook``, ``update-hook``,
  ``delete-hook`` - See *Hooks*.

Example, the complete config for the game
[Mindustry](https://mindustrygame.github.io/) with the jar in the sandbox's
home:

```yaml
use: [gui, gpu, audio, private-home]
command: [java, -jar, Mindustry.jar]
imports: [$SBX_LIB/global.yml]
```

``global.yml`` defines many rules, see ``sbx list-rules``.  sbx installs it
in ``$SBX_LIB``.  New sandboxes import ``~/.config/sbx/global.yml`` instead,
if it exists.

## Variables

Strings may reference environment variables, ``$NAME`` or ``${NAME}``, and
``~``.  sbx sets ``SANDBOX``, ``SANDBOX_HOME``, ``SANDBOX_CONFIG``,
``SANDBOX_ROOT``, ``APP_NAME`` (``org.sbx.<sandbox>``), ``SBX_LIB``, where
sbx's default rules and templates are installed, e.g. ``/usr/local/lib/sbx``,
and ``SBX_APPS``, ``~/.local/share/sbx-apps``.  They are not passed to the
sandbox unless set with ``env``.

## Hooks

Shell commands run on the host with ``bash -c``:

- ``create-hook`` - After ``sbx create``.
- ``pre-hook``    - Before the command starts.
- ``post-hook``   - After the command exits, with ``$SANDBOX_EXIT_CODE``.
- ``update-hook`` - On ``sbx update``.
- ``delete-hook`` - Before ``sbx delete`` removes any files.

Hooks get the variables above and the sandbox's config directory is prepended
to ``PATH``, so scripts shipped with ``config.yml`` can be called by name.  A
non-zero exit code aborts the operation.

```yaml
pre-hook: setup.sh
post-hook: cleanup.sh "$SANDBOX_EXIT_CODE"
```

## Templates

A template is a directory with a ``config.yml``, any scripts it uses and
optionally a ``home`` directory to fill the sandbox's home with.  ``sbx create
-t`` copies it.  Those installed with sbx, in ``$SBX_LIB/templates``, install
their program on the host, in ``$SBX_APPS/<program>``, and bind it read-only
into each sandbox made from them:

```yaml
use: [browser, private-home, app]
command: [/opt/brave/brave]
imports: [$SBX_LIB/global.yml]
pre-hook: >-
  [ -e "$SBX_APPS/brave-browser/current" ] ||
  "$SBX_LIB/templates/brave/install" brave-browser
update-hook: '"$SBX_LIB/templates/brave/install" brave-browser'
rules:
  app:
    - bind: {path: $SBX_APPS/brave-browser/current, dst: /opt/brave}
```

Install scripts use the helpers in ``$SBX_LIB/templates/app.sh``.  They must
verify downloads before unpacking them and never run anything downloaded.
Versions are kept side by side and ``current`` is resolved when a sandbox
starts, so the program's path stays the same and updating does not disturb
running sandboxes.

Firefox based browsers, e.g. Floorp, keep a default profile per install path.
After copying a home from another install, choose its profile once with e.g.
``sbx run floorp -- --ProfileManager``.

# Actions

### ``allow-net: <net> | [<net>...]``
Unblock ``<cidr>`` or one TCP port, ``<addr>:<port>`` or ``[<addr>]:<port>``
for IPv6, see [Network](security.md#network).

### ``allow-syscalls: <group> | [<group>...]``
Unblock syscall groups, see [Syscall filter](security.md#syscall-filter).

### ``args: [<arg>...]``
Pass arguments to ``bwrap``, e.g. ``args: [--unshare-pid]``.

### ``bind: <path> | {...}``
Bind a host path, read-only by default.  Keys:

- ``path``       - Source path.
- ``dst``        - Destination path, defaults to ``path``.
- ``read-write`` - Writable bind.
- ``dev``        - Allow device access.
- ``try``        - Skip if ``path`` does not exist.
- ``cwd``        - Use the current directory as ``path``.
- ``create``     - Create ``path`` if missing.  ``skel`` also fills it from
  ``/etc/skel``, see ``skel``.
- ``perms``      - Permissions of the destination, e.g. ``0o700``.

### ``chdir: <path>``
Set the working directory.

### ``dbus-forward: <name> | [<name>...]``
Forward D-Bus names to the host's session bus, see
[D-Bus and portals](security.md#d-bus-and-portals).

### ``dev: <path> | {path: <path>, perms: <perms>}``
Mount a new ``/dev``.

### ``die-with-parent: <bool>``
Kill the sandbox when sbx exits.  Set by ``common``.  ``false`` lets it
outlive sbx, e.g. when the command starts an application and returns.

### ``dir: <path> | {path: <path>, perms: <perms>}``
Create a directory.

### ``env: [<name>...] | {<name>: <value>...}``
Copy variables from sbx's environment, if set, or set them.

```yaml
- env: {PATH: /usr/bin:/bin}
- env: [LANG, TERM]
```

### ``file: <path> | {path: <path>, data: <data>, perms: <perms>}``
Create a file containing ``data``, empty by default.

### ``hide: <path> | [<path>...]``
Hide host paths.  Directories are covered with a ``tmpfs``, files with
``/dev/null``.  Missing paths are skipped.

### ``host-port: <port> | [<port>...]``
Forward TCP ports on the sandbox's ``localhost`` to the host's.

### ``ifdef: [<var>, <action>...]``
Apply the actions if the variable is set in sbx's environment, e.g.
``ifdef: [DISPLAY, {x11: untrusted}]``.

### ``ifeq: [<value1>, <value2>, <action>...]``, ``ifneq: ...``
Apply the actions if the values, after variable replacement, are equal or
not equal.

### ``net: host | isolated | none``
Network access, ``isolated`` by default, see [Network](security.md#network).
If several are requested, the most permissive wins.

### ``portal: <portal> | [<portal>...]``
Enable portals, see [D-Bus and portals](security.md#d-bus-and-portals).

### ``proc: <path> | {path: <path>, perms: <perms>}``
Mount a new ``/proc``.

### ``skel: <path>``
Copy ``/etc/skel`` to the path, without overwriting, and add the sandbox's
name to the bash prompt.

### ``symlink: [<target>, <path>]``
Create a symlink, e.g. ``symlink: [usr/bin, /bin]``.

### ``tmp-overlay: {path: <path>, skel: true}``
Mount a writable directory, filled from ``/etc/skel``, whose changes are
discarded on exit.

### ``tmpfs: <path> | {path: <path>, size: <bytes>, perms: <perms>}``
Mount a ``tmpfs``.

### ``use: <rule> | [<rule>...]``
Apply rules.

### ``x11: filtered | untrusted | trusted``
Allow access to ``$DISPLAY``, see [X11](security.md#x11).  If several are
requested, the most permissive wins.

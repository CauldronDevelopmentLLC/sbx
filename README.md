# sbx

Sandbox AI agents and untrusted software on Linux.

In typical setups, AI agents and 3rd party software run with full access to
your login account.  They can read ``~/.ssh``, alter startup scripts, copy
browser data or even read your passwords in the background as you type them.
That may be an acceptable access level for vetted distribution packages, but
not for untrusted code from sources like ``npm``, ``pip`` or VSCode or
extensions.  sbx makes it possible to give each application only the access
it needs.

sbx uses [bubblewrap](https://github.com/containers/bubblewrap) and gives
sandboxes their own D-Bus session bus and
[XDG Desktop Portal](https://flatpak.github.io/xdg-desktop-portal/).
Inspired by [code from Simon Lipp](https://gist.github.com/sloonz/4b7f5f575a96b6fe338534dbc2480a5d),
see [his blog post](https://sloonz.github.io/posts/sandboxing-3/).

# Install

On Debian:

    sudo apt-get install -y python3 python3-yaml python3-seccomp python3-gi \
      bubblewrap dbus-daemon xauth passt iproute2 xdg-desktop-portal-gtk
    make install

``util-linux`` 2.39 or later is needed.  ``make install`` copies ``sbx``,
``sbx-portal`` and ``sbx-x11`` to ``~/.local/bin``, or ``$PREFIX/bin``, which
must be on your ``PATH``.  It copies ``global.yml`` to ``~/.config/sbx``
unless one exists, otherwise it shows how to merge the changes.  Install by
copying, never by linking to a checkout which a sandbox can write.  ``make
check`` runs the tests.  See also *Display* below.

# Usage

    create       create a new sandbox
    run          run an existing sandbox
    list         list existing sandboxes
    ps           list running sandboxes
    enter        enter a running sandbox
    list-rules   list available rules
    delete       delete an existing sandbox
    show         print sandbox config and exit
    edit         edit sandbox config with $EDITOR
    template     create a template from an existing sandbox

See ``sbx <subcommand> --help``.  For example, to sandbox ``npm``:

    sbx create npm -r cli npm    # Sandbox "npm" using rule "cli" runs "npm"
    sbx run npm run build
    sbx run npm -- --help        # "--" passes options to the command

``sbx run`` returns the command's exit code, unless the ``post-hook`` fails.

``sbx enter <name>`` starts a login shell in a running sandbox, on the current
terminal, with the same restrictions as the sandbox's processes.  It needs no
privileges.  If several instances are running, give a PID from ``sbx ps``.

``sbx template <name> <template>`` saves a sandbox's config directory and
home to ``~/.local/share/sbx-templates/<template>/``.  ``sbx create <name> -t
<template>`` creates a sandbox from it, as is, so ``-r`` and a command are not
allowed.

# Configuration

A sandbox's ``config.yml`` may contain:

- ``use``     - Rules to apply.  Set by ``sbx create``, overridden by ``-r``.
- ``command`` - Command and arguments.  In ``global.yml``, the default for new
  sandboxes.
- ``imports`` - Configs to import rules from, relative to the importing file.
  Later imports override earlier ones and the importing config overrides all.
- ``rules``   - Named lists of actions, see *Actions*.  If the first item is a
  string, it is the rule's help shown by ``sbx list-rules``.
- ``create-hook``, ``pre-hook``, ``post-hook``, ``delete-hook`` - See *Hooks*.

Example, the complete config for the game
[Mindustry](https://mindustrygame.github.io/) with the jar in the sandbox's
home:

```yaml
use: [gui, gpu, audio]
command: [java, -jar, Mindustry.jar]
imports: [$HOME/.config/sbx/global.yml]
```

``global.yml`` defines many rules, see ``sbx list-rules``.

## Variables

Strings may reference environment variables, ``$NAME`` or ``${NAME}``, and
``~``.  sbx sets ``SANDBOX``, ``SANDBOX_HOME``, ``SANDBOX_CONFIG``,
``SANDBOX_ROOT`` and ``APP_NAME`` (``org.sbx.<sandbox>``).  They are not
passed to the sandbox unless set with ``env``.

## Hooks

Shell commands run on the host with ``bash -c``:

- ``create-hook`` - After ``sbx create``.
- ``pre-hook``    - Before the command starts.
- ``post-hook``   - After the command exits, with ``$SANDBOX_EXIT_CODE``.
- ``delete-hook`` - Before ``sbx delete`` removes any files.

Hooks get the variables above and the sandbox's config directory is prepended
to ``PATH``, so scripts shipped with ``config.yml`` can be called by name.  A
non-zero exit code aborts the operation.

```yaml
pre-hook: setup.sh
post-hook: cleanup.sh "$SANDBOX_EXIT_CODE"
```

# Security

## Syscall filter

Every sandbox runs under a seccomp filter which blocks kernel interfaces
rarely needed by applications but often used by kernel exploits.  It blocks
these groups:

- ``sockets``  - Socket families other than ``AF_UNIX``, ``AF_INET``,
  ``AF_INET6`` and ``AF_NETLINK``, e.g. ``AF_ALG``.
- ``io-uring`` - ``io_uring_setup``, ``io_uring_enter``,
  ``io_uring_register``.
- ``keyring``  - ``keyctl``, ``add_key``, ``request_key``.
- ``userns``   - Creating user namespaces.  Chromium, Electron and other
  programs with their own sandbox need the ``userns`` rule.

Use ``allow-syscalls`` to unblock a group.  Terminal input injection
(``TIOCSTI``, ``TIOCLINUX``) and non-native syscalls, e.g. from 32-bit
binaries, are always blocked.

## Network

Each sandbox gets its own network namespace with internet access through
``pasta``.  Policy rules in the namespace block private, shared, link-local
and multicast ranges, IPv4 and IPv6, and the host's own addresses.  So a
sandbox cannot reach the LAN, VPNs, services on the host or the host's
abstract Unix sockets.  DNS goes to the host's resolver through ``pasta``.
The host's firewall is not involved.

Rules which relax this:

- ``host-net`` - Share the host's network.
- ``cups``     - The host's CUPS on ``localhost:631``.

``no-net`` gives loopback only.  ``allow-net`` unblocks ranges or single TCP
ports, e.g. a VPN's subnet, but not the host's addresses.

Proxies in sbx's ``http_proxy``, ``https_proxy``, ``ftp_proxy`` and
``all_proxy``, or their upper case forms, are allowed automatically, only on
their port.  A proxy on the host's loopback is forwarded as with
``host-port``.  Hostnames are resolved when the sandbox starts.

## D-Bus and portals

Sandboxes never connect to the host's session bus.  With the ``portal`` or
``dbus-forward`` actions, sbx gives a sandbox a private bus, served by
``sbx-portal``, with:

- ``file-chooser`` - Files are chosen in the host's dialog and only those are
  exposed, via the host's document portal.
- ``open-uri``     - ``http``, ``https`` and ``mailto`` links open in the
  host's default application.  Files open only after the user picks an
  application.  Executables are refused.
- ``print``        - Printing via the host's print dialog.  Browsers' own print
  previews need CUPS, see the ``cups`` rule, otherwise use their system
  dialog, e.g. Chrome's Ctrl+Shift+P or Firefox's
  ``print.prefer_system_dialog``.
- ``settings``, ``network-monitor``, ``proxy-resolver`` - Forwarded to the
  host's portal.
- ``dbus-forward`` names - Forwarded to the host's bus.

Nothing else is available and the bus cannot start services.  Dialogs use
the host's portal backend, e.g. ``xdg-desktop-portal-gtk``.

sbx does not pretend to be Flatpak, i.e. there is no ``/.flatpak-info``,
because libraries then expect other Flatpak tools.  The ``dbus`` rule sets
environment variables which make GTK, GLib and Qt use portals.  Some
applications need their own setting, e.g. Firefox's
``widget.use-xdg-desktop-portal.file-picker``.

All instances of a sandbox share one bus, so single instance applications
work.  It stops after the last instance exits, so configuration changes apply
once all instances have exited.  The bus and ``portal.log`` are in
``$XDG_RUNTIME_DIR/sbx/<sandbox>/``.

## Display

### X11

There are three levels of access:

- ``x11`` (filtered) - Clients connect to ``sbx-x11``, a proxy which forwards
  their requests with the host's credentials but drops those which read or
  inject other clients' input or read their windows.
- ``x11-untrusted`` - The X server's SECURITY extension restricts clients.
  Each run gets a new cookie, revoked after the sandbox's last process exits.
- ``x11-trusted`` - Full access, also with a per run cookie.

|                                              | ``x11`` | untrusted | trusted |
|----------------------------------------------|---------|-----------|---------|
| Read keystrokes or inject input              | blocked | blocked   | yes     |
| Capture other windows or the screen          | mostly  | blocked   | yes     |
| GPU rendering, MIT-SHM, themed cursors       | yes     | no        | yes     |
| Paste from host                              | yes     | yes       | yes     |
| Copy to host                                 | yes     | no        | yes     |
| Read the clipboard without pasting           | blocked | yes       | yes     |
| Read other windows' titles                   | blocked | yes       | yes     |

``sbx-x11`` hides extensions it does not know, including RECORD and XTEST,
zeroes ``QueryKeymap`` and XKB keycodes, and blocks key event selection,
grabs and synthetic input on other clients' windows, and reads of other
clients' drawables via core requests, MIT-SHM, RENDER, Composite, DAMAGE,
DBE, DRI3 and GLX.  It also:

- Allows reading a selection owned outside the sandbox for 2 seconds after a
  paste action in a focused sandbox window, and only from the owner at the
  first read.  CLIPBOARD: ``Ctrl+V``, ``Ctrl+Shift+V``, ``Shift+Insert``,
  left or right click.  PRIMARY: middle click, ``Shift+Insert``.  Dropping
  from the host allows reading the dragged data.
- Allows keyboard grabs only while a sandbox window has the focus and drops
  key events while it does not, so a grab cannot capture keys typed
  elsewhere, only swallow them.
- Allows reading only properties needed for drag and drop, embedding and
  settings, e.g. ``WM_STATE``, on other clients' windows.  Titles, class,
  command line, PID and icons are hidden, and data pasted in host
  applications cannot be read in transit.
- Blocks changes to other clients' windows: mapping, moving, destroying,
  reparenting, drawing on them, creating windows inside them, their
  properties, except to answer a paste from the sandbox, and synthetic events
  other than selection, drag and drop and embedding messages.
- Blocks server wide changes: keyboard and pointer mappings and settings, XKB
  keymaps and controls, XInput devices, font path, access control, screen
  configuration, ``GrabServer`` and ``KillClient`` of other clients.
- Allows setting the focus, taking CLIPBOARD or PRIMARY and pointer warps
  only while a sandbox window has the focus or within 2 seconds of user input
  in the sandbox, drag messages only while a button pressed in the sandbox is
  held, and never taking manager selections, e.g. the window manager's.

Limits: with ``PointerRoot`` focus, e.g. some focus follows mouse setups, key
events are not checked.  Without a compositing manager, a client can read
the screen's contents under its own windows where they are unpainted or
overlapped.  Vendor extensions such as NVIDIA's ``NV-GLX`` are passed
unfiltered.  With ``-v``, denials are logged to
``$XDG_RUNTIME_DIR/sbx/<sandbox>/x11.log``.

The proxy adds latency to every round trip, about 20 µs when idle and more
when the X server is busy between requests.  Applications which wait for the
server after each drawing operation slow down most, e.g. x11perf's
``PutImage`` and ``ShmPutImage`` run at about a quarter of the direct rate.
GPU rendered applications, which send little X traffic, are hardly affected.

If the X server grants access by user, which Debian does by default, any
sandbox which reaches its socket gets trusted access, since sandboxes run as
your user.  ``x11-untrusted`` binds the socket and ``host-net`` exposes its
abstract socket, so sbx warns in these cases.  To remove the grant, once
``xauth list "$DISPLAY"`` shows a cookie:

```sh
sudo dpkg-divert --local --rename --add \
  --divert /etc/X11/Xsession.d/35x11-common_xhost-local.disabled \
  /etc/X11/Xsession.d/35x11-common_xhost-local
xhost -si:localuser:$USER
```

### Wayland

Wayland clients cannot see each other's input, windows or clipboard and
render on the GPU.  However, wlroots compositors such as Sway offer every
client privileged protocols, e.g. ``virtual-keyboard`` (input injection),
``wlr-screencopy`` (screen capture), ``wlr-data-control`` (clipboard) and
``foreign-toplevel`` (window list).  The ``wayland`` rule binds the
compositor's socket unfiltered, so sandboxes get these.  Filtering needs a
``security-context-v1`` socket per sandbox, which is not implemented yet.
X11 applications under Xwayland share one X server, see *X11*.

## Limitations

- Anything a sandbox can write which the host later runs is a way out, e.g.
  a bound project's scripts or ``.git/hooks`` when git runs on the host.
- Sandboxes share the host's kernel.  A kernel or driver bug can be a way
  out, see also ``userns`` and ``gpu``.
- ``sbx-x11`` and ``sbx-portal`` run on the host, unsandboxed, and parse
  requests from sandboxes.
- The network is filtered by address, not hostname.  A VPN which routes
  public addresses is reachable.
- ``audio`` includes the microphone.
- ``accessibility`` lets a sandbox read text from other applications.
- ``gpu`` exposes the GPU driver's kernel interface.

# Actions

### ``allow-net: <net> | [<net>...]``
Unblock ``<cidr>`` or one TCP port, ``<addr>:<port>`` or ``[<addr>]:<port>``
for IPv6, see *Network*.

### ``allow-syscalls: <group> | [<group>...]``
Unblock syscall groups, see *Syscall filter*.

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
Forward D-Bus names to the host's session bus, see *D-Bus and portals*.

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
Network access, ``isolated`` by default, see *Network*.  If several are
requested, the most permissive wins.

### ``portal: <portal> | [<portal>...]``
Enable portals, see *D-Bus and portals*.

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
Allow access to ``$DISPLAY``, see *X11*.  If several are requested, the most
permissive wins.

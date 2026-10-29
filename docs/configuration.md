# Configuration

A sandbox's ``config.yml``, in ``~/.config/sbx/containers/<name>``, may
contain:

- ``imports`` - Templates to build on, see *Templates*.
- ``use``     - Rules to apply, in addition to those its imports use.
- ``command`` - Command and arguments.
- ``home``    - The image a new home is filled from, ``skel`` by default, see
  *Images*.
- ``rules``   - Named lists of actions, see *Actions*.  If the first item is a
  string, it is the rule's help shown by ``sbx list-rules``.
- ``create-hook``, ``pre-hook``, ``post-hook``, ``update-hook``,
  ``delete-hook`` - See *Hooks*.

Example, the complete config for the game
[Mindustry](https://mindustrygame.github.io/) with the jar in the sandbox's
home:

```yaml
imports: [global]
use: [gui, gpu, audio, private-home]
command: [java, -jar, Mindustry.jar]
```

The ``global`` template defines many rules, see ``sbx list-rules``.

Rules whose names start with ``_`` are private to their config, so they do
not collide with or override rules of the same name in other configs.

``~/.config/sbx/local.yml``, if it exists, holds the machine's defaults.  Its
``use`` is applied to every sandbox, after the sandbox's own, and the
sandbox's rules override its rules.  Other keys are ignored.  E.g. for a proxy
which only login shells know about:

```yaml
use: [_proxy]
rules:
  _proxy:
    - proxy: http://172.16.1.1:3128/
```

## Templates

A template is a ``<name>.yml`` file, or a ``<name>`` directory with a
``config.yml`` and any scripts it uses, looked up by name in
``~/.config/sbx/templates``, then in ``$SBX_LIB/templates``, so yours replace
those installed with sbx.  An import containing ``/`` or ending in ``.yml``
is a path instead, relative to the importing config.  A config's keys
override those of its imports, except ``use``, which adds to them, and
``rules``, see above.

``sbx create <name> -t <template>`` creates a sandbox importing the template,
``default`` if neither ``-t`` nor ``-r`` is given, ``global`` if only ``-r``
is.  ``-r`` and a command are added to the new config.  ``sbx template <name>
<template>`` saves a sandbox's config directory as a template and its home as
an image of the same name, which new sandboxes made from it are filled from.

Those installed with sbx install their program on the host, as an image,
with their ``update-hook`` and bind it read-only into each sandbox made from
them.  Binding a missing image runs the ``update-hook``, so the program is
installed on the first run:

```yaml
use: [browser, private-home, _local]
command: [/opt/brave/brave]
imports: [global]
update-hook: install brave-browser
rules:
  _local:
    - bind: {image: brave-browser, dst: /opt/brave}
```

Install scripts use the helpers in ``$SBX_LIB/app.sh``.  They must verify
downloads before unpacking them and never run anything downloaded.

Firefox based browsers, e.g. Floorp, keep a default profile per install path.
After copying a home from another install, choose its profile once with e.g.
``sbx run floorp -- --ProfileManager``.

## Images

An image is a directory of files, with its versions side by side and
``current`` pointing to the newest, looked up by name in
``~/.local/share/sbx/images``, then in ``$SBX_LIB/images``.  ``current`` is
resolved when a sandbox starts, so paths stay the same and updating does not
disturb running sandboxes.  Images are bound, e.g. a program's install, or
copied, e.g. into a new home by ``private-home`` and ``tmp-home``.  ``skel``
is ``/etc/skel``.

## Variables

Strings may reference environment variables, ``$NAME`` or ``${NAME}``, and
``~``.  sbx sets ``SANDBOX``, ``SANDBOX_HOME``, ``SANDBOX_CONFIG``,
``SANDBOX_ROOT``, ``APP_NAME`` (``org.sbx.<sandbox>``), ``HOME_IMAGE``, from
``home``, ``SBX_LIB``, where sbx's templates and images are installed, e.g.
``/usr/local/lib/sbx``, and ``SBX_IMAGES``, ``~/.local/share/sbx/images``.
They are not passed to the sandbox unless set with ``env``.

## Hooks

Shell commands run on the host with ``bash -c``:

- ``create-hook`` - After ``sbx create``.
- ``pre-hook``    - Before the command starts.
- ``post-hook``   - After the command exits, with ``$SANDBOX_EXIT_CODE``.
- ``update-hook`` - On ``sbx update`` and to install a missing image, see
  ``bind``.
- ``delete-hook`` - Before ``sbx delete`` removes any files.

Hooks get the variables above and the directory of the config defining the
hook is prepended to ``PATH``, so scripts shipped with it can be called by
name.  A non-zero exit code aborts the operation.

```yaml
pre-hook: setup.sh
post-hook: cleanup.sh "$SANDBOX_EXIT_CODE"
```

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
- ``image``      - Bind an image instead, see [Images](#images), running the
  ``update-hook`` first if it is missing.
- ``dst``        - Destination path, defaults to ``path``.
- ``read-write`` - Writable bind.
- ``dev``        - Allow device access.
- ``try``        - Skip if ``path`` does not exist.
- ``cwd``        - Use the current directory as ``path``.
- ``create``     - Create ``path`` if missing.  An image's name also fills it
  from the image, see [Images](#images).
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

### ``host-port: <ports> | [<ports>...]``
Forward TCP ports, e.g. ``631`` or ``8000-8010``, on the sandbox's
``localhost`` to the host's.

### ``ifdef: [<var>, <action>...]``
Apply the actions if the variable is set in sbx's environment, e.g.
``ifdef: [DISPLAY, {x11: untrusted}]``.

### ``ifeq: [<value1>, <value2>, <action>...]``, ``ifneq: ...``
Apply the actions if the values, after variable replacement, are equal or
not equal.

### ``listen-port: <ports> | [<ports>...]``
Forward TCP ports, e.g. ``8080`` or ``8000-8010``, on the host's
``127.0.0.1`` to the sandbox, e.g. for another sandbox to reach with
``host-port``.  With isolated networking only, see
[Network](security.md#network).

### ``net: host | isolated | none``
Network access, ``isolated`` by default, see [Network](security.md#network).
If several are requested, the most permissive wins.

### ``portal: <portal> | [<portal>...]``
Enable portals, see [D-Bus and portals](security.md#d-bus-and-portals).

### ``proc: <path> | {path: <path>, perms: <perms>}``
Mount a new ``/proc``.

### ``proxy: <url> | true``
Set ``http_proxy``, ``https_proxy``, ``ftp_proxy`` and their upper case forms
to ``<url>`` or, with ``true``, copy those, ``all_proxy`` and ``no_proxy`` from
sbx's environment.  Connections to the proxies are allowed, see
[Network](security.md#network).

### ``symlink: [<target>, <path>]``
Create a symlink, e.g. ``symlink: [usr/bin, /bin]``.

### ``tmp-overlay: {path: <path>, image: <image>}``
Mount a writable directory, filled from the image, whose changes are
discarded on exit.

### ``tmpfs: <path> | {path: <path>, size: <bytes>, perms: <perms>}``
Mount a ``tmpfs``.

### ``use: <rule> | [<rule>...]``
Apply rules.

### ``x11: filtered | untrusted | trusted``
Allow access to ``$DISPLAY``, see [X11](security.md#x11).  If several are
requested, the most permissive wins.

### ``x11-allow: <setting> | [<setting>...]``
Let a sandbox with filtered X11 change server wide settings, which persist
after it exits: ``keyboard-control``, e.g. key repeat, the bell and LEDs,
``pointer-control``, e.g. acceleration, or ``screen-saver``.

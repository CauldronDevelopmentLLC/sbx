# sbx

Contain untrusted software on Linux: AI agents, packages from ``npm`` or
``pip``, browsers running untrusted web code, games, editors with third
party extensions or anything else you do not fully trust.

Normally, every program you run has full access to your login account.  It
can read ``~/.ssh``, alter startup scripts, copy browser data or read your
passwords as you type them.  sbx gives each application only the access it
needs: a private home, the directories you choose, the internet but not your
local network, and a display it cannot use to spy on other applications.  It
needs no root privileges, daemons or container images.

## Quick start

See *Install*, then:

```sh
# Claude Code with only the current directory, installed on the first run
sbx create claude -t claude-code
cd ~/src/project && sbx run claude

# Brave, also e.g. -t brave-origin-nightly or -t floorp
sbx create brave -t brave
sbx run brave
sbx update brave            # Updates the install shared by brave sandboxes

# Visual Studio Code, its projects live in the sandbox's home
sbx create code -t vscode
sbx run code

# A browser from your distribution, e.g. chromium
sbx create firefox -r browser -r firefox -r private-home firefox
sbx run firefox

# npm with only the current directory
sbx create npm -r cli npm
sbx run npm install
```

Each sandbox has its own home in ``~/.local/share/sbx/containers/<name>`` and
config in ``~/.config/sbx/containers/<name>/config.yml``.  Sandboxes made from
the same template share one read-only install of the program, an image in
``~/.local/share/sbx/images``.
``sbx list-rules`` shows the rules available, see
[Configuration](docs/configuration.md) to write your own.

## Threats

What a program in a sandbox can no longer do, with the default rules:

| Threat | How sbx stops or mitigates it |
|---|---|
| Read or alter your files, keys, browser data or startup scripts | Only paths its rules bind are visible.  It gets a private home and read-only system directories. |
| Log keystrokes, capture the screen or inject input | ``sbx-x11`` hides other applications' input, windows and titles and blocks synthetic input. |
| Read the clipboard, or replace it before you paste | Only right after you paste into the sandbox.  Taking the clipboard needs your input in the sandbox. |
| Attack your LAN, VPN or services on your computer | Its own network with internet access only. |
| Use desktop services, e.g. to start programs | A private D-Bus with portals only.  Files are shared via your file dialog, links and files open in host applications after your choice. |
| Exploit the kernel | A syscall filter removes interfaces rarely needed but often used by exploits.  No capabilities and no new privileges. |
| Attack other processes or inject input into your terminal | Its own process IDs, terminal injection blocked. |
| Listen through the microphone or watch through the camera | Only with the ``audio`` or ``video`` rules, which ``browser`` includes. |

What sbx does not stop:

- Use of anything you grant, e.g. sending what it can read to the internet.
- Files a sandbox writes are untrusted wherever else they are used.
- Kernel, driver, X server or ``sbx`` bugs.

See [Security](docs/security.md) for details and limitations.

## Install

On Debian, or the equivalent packages on other distributions:

    sudo apt-get install -y python3 python3-yaml python3-seccomp python3-gi \
      bubblewrap dbus-daemon xauth passt iproute2 xdg-desktop-portal-gtk \
      libglib2.0-bin curl gpg unzip xz-utils
    sudo make install

``util-linux`` 2.39 or later is needed.  ``make install`` installs ``sbx``,
``sbx-portal`` and ``sbx-x11`` in ``/usr/local/bin``, templates, including the
default rules in ``global``, and images in ``/usr/local/lib/sbx`` and bash and
fish completions, or under ``$PREFIX``.  Install by copying, never by linking
to a checkout which a sandbox can write.  ``make check`` runs the tests.

To upgrade from the layout before templates were imported, move each
``~/.config/sbx/<name>`` to ``~/.config/sbx/containers/<name>``, each
``~/.local/share/sbx/<name>`` to ``~/.local/share/sbx/containers/<name>`` and
``~/.local/share/sbx-apps/*`` to ``~/.local/share/sbx/images/``.  Then replace
each ``config.yml`` made from a template with ``imports: [<template>]``, and
in the others ``imports: [$SBX_LIB/global.yml]`` with ``imports: [global]``.

On X11, see also [X11](docs/security.md#x11) on removing the X server's
access grant by user.

## Usage

    create       create a new sandbox
    run          run an existing sandbox
    update       update a sandbox, e.g. its program
    rename       rename an existing sandbox
    list         list existing sandboxes
    ps           list running sandboxes
    enter        enter a running sandbox
    list-rules   list available rules
    delete       delete an existing sandbox
    show         print sandbox config and exit
    edit         edit sandbox config with $EDITOR
    template     create a template from an existing sandbox

See ``sbx <subcommand> --help``.  ``-r`` adds rules and may be repeated.  Options for the command follow ``--``, e.g.
``sbx run npm -- --help``.

``sbx run`` returns the command's exit code, unless the ``post-hook`` fails.

``sbx enter <name> [-- <command>...]`` runs a login shell, or the command, in
a running sandbox, on the current terminal, with the same restrictions as
the sandbox's processes.  It needs no privileges.  If several instances are
running, give a PID from ``sbx ps``.

``sbx update <name>`` runs the sandbox's ``update-hook``, e.g. to update the
program a template installed.

``sbx rename <old> <new>`` renames a sandbox's config and home.  Files shared
with it through the file dialog are not carried over.

``sbx create <name> -t <template>`` creates a sandbox importing a template,
with ``-r`` and a command added.  Without ``-t`` it imports ``default``, or
with ``-r``, only the rules given.  Templates are looked up in
``~/.config/sbx/templates``, then in those installed with sbx, so yours can
replace them.  ``sbx template <name> <template>`` saves a sandbox's config
directory as a template there and its home as an image new sandboxes made
from it start with, see [Templates](docs/configuration.md#templates).

## Documentation

- [Configuration](docs/configuration.md) - Config files, hooks and actions.
- [Security](docs/security.md) - How each layer works, and its limitations.

## License

sbx is free software, licensed under the GNU General Public License, version
3 or later, see [LICENSE](LICENSE).  To report a vulnerability, see
[SECURITY.md](SECURITY.md).

Inspired by [code from Simon Lipp](https://gist.github.com/sloonz/4b7f5f575a96b6fe338534dbc2480a5d),
see [his blog post](https://sloonz.github.io/posts/sandboxing-3/).

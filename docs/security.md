# Security

Each sandbox is a set of Linux namespaces made with
[bubblewrap](https://github.com/containers/bubblewrap): its own mounts, with
only the paths its rules bind, its own process IDs and its own network.  It
runs as your user, without capabilities or the ability to gain privileges.
This document describes the other layers.

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
  host's default application, also those opened with ``xdg-open``.  Files
  open only after the user picks an application.  Executables are refused.
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
- Allows reading only listed properties of other clients' windows, e.g.
  ``WM_STATE`` for drag and drop, and of the root window, e.g. the window
  manager's settings.  Titles, class, command line, PID, icons, workspace
  names and data pasted in host applications are hidden.  The active window
  and window lists show only the sandbox's windows.
- Denies requests it does not know.  Each core request and each request of
  an allowed extension is passed, checked or denied.  GLX and ``NV-GLX``
  requests are not listed, GLX is checked by drawable.
- Blocks changes to other clients' windows and resources: mapping, moving,
  destroying, reparenting, drawing on them, creating windows inside them,
  freeing or changing their pixmaps, GCs, fonts, colormaps or cursors, their
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
unfiltered.  Whether the user is active stays visible, e.g. through the
pointer's position.  X11 shares one server between all clients, so filtering
it can only approach the isolation of Wayland.  With ``-v``, denials and
hidden properties are logged to ``$XDG_RUNTIME_DIR/sbx/<sandbox>/x11.log``,
e.g. to find a property an application needs.

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

- Files a sandbox writes are untrusted wherever else they are used.
- Sandboxes share the host's kernel.  A kernel or driver bug can be a way
  out, see also ``userns`` and ``gpu``.
- ``sbx-x11`` and ``sbx-portal`` run on the host, unsandboxed, and parse
  requests from sandboxes.
- The network is filtered by address, not hostname.  A VPN which routes
  public addresses is reachable.
- ``audio`` includes the microphone.
- ``accessibility`` lets a sandbox read text from other applications.
- ``gpu`` exposes the GPU driver's kernel interface.

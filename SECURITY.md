# Security policy

## Reporting a vulnerability

Report vulnerabilities privately, via this repository's *Security* tab,
*Report a vulnerability*.  Please do not open public issues for them.
Include the sbx commit, the sandbox's rules and the steps to reproduce.

## Scope

In scope, a sandboxed program gaining access its rules do not grant, e.g.:

- Reading or writing host files which are not bound.
- Reaching networks or host services blocked by ``isolated`` networking.
- Reading other applications' input, windows or clipboard, or injecting
  input, through ``sbx-x11``.
- Using D-Bus or portals beyond what ``sbx-portal`` allows.
- Escaping the namespaces, seccomp filter or other restrictions sbx sets up,
  including via ``sbx enter``.
- Running code in ``sbx``, ``sbx-portal`` or ``sbx-x11``.

Out of scope:

- Bugs in the kernel, drivers, X server, Wayland compositors or other
  software sbx relies on.  Please report those upstream, and to us if sbx
  could mitigate them.
- Documented limitations, see [Security](docs/security.md#limitations).
- Access granted by rules, e.g. ``x11-trusted``, ``host-net`` or ``audio``.

Fixes go to the latest version only.

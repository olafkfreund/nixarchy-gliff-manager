# Working in this repository

A NixOS-ready fork of Gliff-Manager (MIT, Gavin Nugent), shipped as a default
plugin by nixarchy. `CLAUDE.md` is a symlink to this file.

## Layout

- `manifest.json`, `Panel.qml`, `gliff-manager.sh`, `LICENSE`: the plugin. The
  flake copies exactly these four files; the validator refuses symlinks.
- `flake.nix`: the package, the Home Manager module, and one `checks.default`.
- `tests/behaviour.sh`: runs the helper against real processes named
  `.Hyprland-wrapp` and `.gliff-wrapped`, stubbing only `gliff`, `gliff-server`
  and `ssh`. It never asserts `.channel`: that is the host's `os-release`.
- `docs/`: the one-page Pages site. `docs/index.md` is `README.md` plus four
  lines of front matter, and CI fails when they differ.
- `UPSTREAM`: the 28allday commit this fork last synced to.

## Rules

- **No pacman, no yay** on any non-comment line, in `gliff-manager.sh` or
  `Panel.qml`. The flake check greps for it, and so does nixarchy's build.
- `REMOTE_PROBE` runs on the remote under `sh -s`: POSIX only, and no single
  quote inside it (it is a single-quoted string).
- Keep `LICENSE` word for word.

## The behaviour test and its break proofs

Revert one fix at a time and run `nix flake check`; each must fail at its own
assertion: `rpm -q gliff` for the version (status), `pgrep -x gliff` (live),
`ps -C Hyprland` (probe's `hyprOwner` empty). Reverting to `pacman -Q gliff`
is caught earlier, by the no-pacman grep. Prove the break landed with
`git diff` first, then restore the file from HEAD (a plain checkout of the
path restores the index, which may hold the break).

## Syncing upstream

`git log $(cat UPSTREAM)..upstream/main`, port what applies, then write the new
sha into `UPSTREAM`. The weekly `upstream` workflow opens an issue when it moves.

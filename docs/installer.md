# Installer ISO

The image and its installed-system template live in `hosts/installer-iso`.
They import `zenpkgs.nixosModules.default` and use its canonical `zen-dsl`.
ZenPkgs owns the public GNOME, installed-base, and OOBE modules, including their
internal NixOS lowering. This repository composes the live image and supplies
the installed flake's local discovery and compilation logic.

## Setup handoff: ready contract

- This follows `ZenOS-Setup/TEMPLATE-CONTRACT.md`. The runner reads
  `/iso-config-template/flake.nix` before disk work and copies it to
  `/mnt/etc/ZenOS/flake.nix`. It generates `hosts/<host>/host.zcfg` and its ZCFG
  imports, not `host.nix`. The template compiles them into the Nix store.
- The installed template contains only the `zenpkgs` input. It owns host
  discovery and compilation in its generated `flake.nix`. Each `host.zcfg`
  includes `_import "./hardware.zcfg";`. No hardware Nix, hardware input,
  hardware JSON, or OOBE JSON is consumed. `flake.nix` is the only editable Nix
  file; installed defaults and runtime support come from ZenPkgs.
- Hardware includes filesystems for manual partition selection. For automatic
  partitioning, `drives.zcfg` supplies the disk layout and hardware detection
  must omit filesystem assignments from `hardware.zcfg`. Root and a FAT ESP
  mounted at `/boot` are required. The installed system uses systemd-boot
  generation files behind the restored rEFInd picker, with GRUB and NVRAM
  writes disabled. The pinned legacy rEFInd resource tree and generation sync
  script are unchanged; firmware fallback resources go under `EFI/BOOT`.
- The temporary host enables OOBE declaratively with
  `system.oobeMode = true` in zcfg. The final host omits that assignment;
  ZenPkgs gates OOBE behavior on the evaluated module option. Import names,
  formatting, comments, and unrelated `enable = true` assignments do not select
  a stage. There is no `installerStage` argument in the installed flake.
  Setup publishes the final host and removes the temporary host only after a
  successful boot-generation rebuild. Setup's finalization JSON records support
  cleanup retries only; they do not select OOBE or contain hardware configuration.
- The live session is `zenos-oobe`, but launches `zenos-setup` without `--oobe`.
  Installed OOBE has exactly one Setup service, `zenos-oobe`, running
  `zenos-setup --oobe`. Both Setup services set `ZENOS_SETUP_DRY_RUN=0` directly
  in their service environment. Starting the app must not
  install anything: partitioning and installation wait for the user's clicks.
- Setup comes only from `pkgs.zenos.system.zenos-setup`; the GNOME mode comes
  only from `pkgs.zenos.system.zenos-oobe-mode`. Setup must export
  `meta.mainProgram = "zenos-setup"`. The mode package must install
  `share/gnome-shell/modes/zenos-oobe.json` and extension UUID
  `zenos-oobe-mode@neg-zero.com`. The image supplies GnomeDesktop, GWeather,
  and NetworkManager typelib search paths as well as the GNOME session wrapper.
- The installed composition does not select GNOME, force its public enable
  option off, or add GNOME applications against the user's selections. GNOME,
  other desktops, and no-desktop choices come from Setup's generated ZCFG.
  `desktops.gnome.enable = true` owns GDM and its `gnome-login` greeter session.
  OOBE temporarily overrides display managers and autologin in favor of greetd;
  its account, services, and login overrides disappear when the option is absent.
  Permanent users use `users.<name>.legacy`, UID 1000 for Setup's first user,
  and `/Users/<name>` homes. The hostname comes from
  `legacy.networking.hostName`. Packages use full-path boolean selectors.
- Automatic drives lower from `system.disks.disk.main` to `disko.devices.disk.main`.
  Its GPT layout has a 1G FAT ESP at
  `/boot` with `umask=0077` and an ext4 root using the remaining space.
  Manual preflight supplies `legacy.fileSystems` without mounting devices.
  The template checks ZCFG, compiles it in the store, and parses generated Nix.
- `/Config` is a symlink to `/etc`; XDG config/data/cache/state point to
  `$HOME/.private/{Config,Packages,Live,State}`. The composition creates those
  directories for normal users. It does not implement the rest of ZenFS.
- ZenPkgs owns Nixpkgs and its other upstream inputs. The installed flake retains
  the generated zcfg tree, local hardware output, and the ZenPkgs dependency
  closure.

## Canonical user sources

Setup writes `hosts/<host>/users/<user>/main.zcfg`, then publishes the canonical
file at `/Users/<user>/.private/Config/main.zcfg`. The host entry becomes a
symlink. Existing user sources are not overwritten.

Before passing configuration to pure Nix, Setup copies those linked files into
a private snapshot. The installed closure retains both that snapshot and its
generated host Nix, as well as hardware and input sources. The editable tree
keeps its links. Later rebuild tooling must use the same snapshot step rather
than directly evaluating home symlinks from the flake.

## Outputs

```text
packages.x86_64-linux.iso
nixosConfigurations.zenos-installer-iso.config.system.build.isoImage
packages.x86_64-linux.config-template
checks.x86_64-linux.installer-contract
checks.x86_64-linux.repository-structure
```

Focused evaluation may run locally; runtime and installation acceptance must
run only in the ZenOS VM. Use a private snapshot below `/tmp`
and `path:` flake references so untracked composition files are included.
The final ZenPkgs commit and lock update belong to the integration owner after
the two packages are published. Until then, use `--override-input zenpkgs
path:/tmp/<private-zenpkgs-snapshot>`; do not publish that temporary override.

After building `packages.x86_64-linux.config-template` in the VM, run:

```sh
python3 hosts/installer-iso/test-template.py /nix/store/<template-output>
python3 hosts/installer-iso/test-template.py /nix/store/<template-output> --zenpkgs-source /tmp/<zenpkgs-snapshot>
python3 hosts/installer-iso/test-template.py /nix/store/<template-output> --zenpkgs-source /tmp/<zenpkgs-snapshot> --setup-source /tmp/<setup-snapshot>
```

This only evaluates private fixtures. It checks the single root input, offline
reevaluation, imported hardware ZCFG, checked/parsed compiler output, XDG
defaults, desktop choices, nested/imported OOBE syntax, misleading comments,
and removal of the temporary option without installing or activating a system.
The optional source argument exercises the external Setup generator's actual
automatic-disk and account output. No Setup package is mocked by these tests.
`installer-contract` also checks package
contents and the live/OOBE commands, and therefore needs the two public packages.

The manual acceptance run is live app -> short install -> reboot -> OOBE ->
permanent desktop. Check the session, app log, `/boot` loader, imported hardware
ZCFG, and absence of generated Nix under `/Config/ZenOS` at each installed
stage. This task does not boot the ISO or perform those disk operations.

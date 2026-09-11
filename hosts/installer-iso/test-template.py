"""Evaluate the installed flake in a private directory; never install or activate."""

import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def run(*args):
    result = subprocess.run(args, text=True, capture_output=True, timeout=300)
    if result.returncode:
        diagnostics = "\n".join(
            line for line in result.stderr.splitlines()
            if not line.startswith("trace: ZenPkgs metadata warning:")
        )
        raise RuntimeError(f"{' '.join(args)}\n{diagnostics}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("template", type=Path)
    parser.add_argument("--setup-source", type=Path)
    parser.add_argument("--zenpkgs-source", type=Path, help="Local integration checkout; overrides only the private test lock")
    args = parser.parse_args()
    template = args.template.resolve()
    template_text = (template / "flake.nix").read_text()
    assert 'github:zenos-n/zenpkgs/migration/path-derived-dsl' in template_text
    assert "zenosSource" not in template_text
    assert "setup-hardware" not in template_text
    assert "github:NixOS/nixpkgs" not in template_text
    assert "path:/nix/store" not in template_text
    assert "hasInfix" not in template_text
    assert "hardware-configuration.nix" not in template_text
    assert "installerStage" not in template_text
    fixtures = Path(__file__).resolve().parent / "fixtures"
    with tempfile.TemporaryDirectory(prefix="zenos-template-test-", dir="/tmp") as work:
        config = Path(work) / "config"
        shutil.copytree(fixtures / "config", config)
        (config / "flake.nix").write_text(template_text)
        pending_dir = config / "hosts/oobe-test"
        assert not list(config.rglob("*.json"))
        assert list(config.rglob("*.nix")) == [config / "flake.nix"]
        override = (
            ["--override-input", "zenpkgs", f"path:{args.zenpkgs_source.resolve()}"]
            if args.zenpkgs_source else []
        )
        ref = f"path:{config}"
        run("nix", "flake", "lock", *override, ref)
        lock = json.loads((config / "flake.lock").read_text())
        root_inputs = lock["nodes"]["root"]["inputs"]
        assert set(root_inputs) == {"zenpkgs"}
        zenpkgs_node = lock["nodes"][root_inputs["zenpkgs"]]
        if not args.zenpkgs_source:
            assert zenpkgs_node["locked"]["owner"] == "zenos-n", zenpkgs_node
            assert zenpkgs_node["locked"]["repo"] == "zenpkgs", zenpkgs_node
            assert re.fullmatch(r"[0-9a-f]{40}", zenpkgs_node["locked"]["rev"]), zenpkgs_node
        run(
            "nix", "eval", "--no-write-lock-file", "--raw",
            f"{ref}#nixosConfigurations.oobe-test.config.system.build.toplevel.drvPath",
        )
        print("PASS: temporary OOBE toplevel evaluation", flush=True)
        run("nix", "flake", "lock", "--offline", ref)

        def evaluate(host, expression):
            return json.loads(run(
                "nix", "eval", "--offline", "--no-write-lock-file", "--json",
                f"{ref}#nixosConfigurations.{host}.config", "--apply", expression,
            ))

        summary = """c: {
          gnome = c.services.desktopManager.gnome.enable;
          gdm = c.services.displayManager.gdm.enable;
          sddm = c.services.displayManager.sddm.enable;
          plasmaLogin = c.services.displayManager.plasma-login-manager.enable;
          greetd = c.services.greetd.enable;
          temporaryUser = c.users.users ? zenos;
          setupService = c.systemd.user.services ? zenos-oobe;
          liveService = c.systemd.user.services ? zenos-setup;
          oobe = c.zenos.system.oobeMode;
          failures = map (a: a.message) (builtins.filter (a: !a.assertion) c.assertions);
          root = c.fileSystems."/".device;
          esp = c.boot.loader.efi.efiSysMountPoint;
        }"""
        pending = evaluate("oobe-test", summary)
        assert pending["greetd"] and pending["temporaryUser"] and pending["setupService"]
        assert not pending["liveService"] and not pending["failures"]
        assert evaluate("oobe-test", "c: c.systemd.user.services.zenos-oobe.environment.ZENOS_SETUP_DRY_RUN") == "0"
        assert not pending["gdm"]
        desktop = evaluate("desktop-test", summary)
        assert desktop["gdm"] and not desktop["greetd"]
        assert not desktop["temporaryUser"] and not desktop["setupService"]
        assert not desktop["liveService"] and not desktop["failures"]
        assert pending["root"] == desktop["root"] == "/dev/disk/by-uuid/fixture-root"
        assert pending["esp"] == desktop["esp"] == "/boot"
        for host in ("headless-test", "kde-test"):
            selected = evaluate(host, summary)
            assert not selected["gnome"] and not selected["gdm"] and not selected["greetd"]
            assert not selected["sddm"]
            assert selected["plasmaLogin"] == (host == "kde-test")
            assert not selected["failures"]
        assert evaluate("desktop-test", "c: c.home-manager.users.alice.xdg.configHome") == (
            "/Users/alice/.private/Config"
        )
        assert evaluate("desktop-test", "c: c.home-manager.users.alice.xdg.cacheHome") == (
            "/Users/alice/.private/Live"
        )
        desktop_drv = evaluate("desktop-test", "c: c.system.build.toplevel.drvPath")
        assert desktop_drv.startswith("/nix/store/") and desktop_drv.endswith(".drv")

        assert evaluate("oobe-test", "c: c.zenos.system.oobeMode")
        assert not evaluate("desktop-test", "c: c.zenos.system.oobeMode")
        # Same evaluated option through nested spelling and a differently named import.
        (pending_dir / "system.zcfg").write_text('_import "./phase.zcfg";\n')
        (pending_dir / "phase.zcfg").write_text("system = { oobe = { enable = true; }; };\n")
        assert evaluate("oobe-test", summary)["oobe"]
        with (pending_dir / "host.zcfg").open("a") as output:
            output.write('users.alice.legacy = { isNormalUser = true; home = "/Users/alice"; '
                         'password = "evaluation-only"; extraGroups = [ "wheel" ]; };\n')
        (pending_dir / "phase.zcfg").write_text("system.oobeMode = false;\n")
        assert not evaluate("oobe-test", "c: c.zenos.system.oobeMode")
        # Misleading comments and an unrelated true option must not select OOBE.
        (pending_dir / "phase.zcfg").write_text(
            "# oobe = { enable = true; };\nlegacy.hardware.graphics.enable = true;\n"
        )
        final = evaluate("oobe-test", summary)
        assert final["gdm"] and not final["greetd"] and not final["oobe"]
        assert not final["temporaryUser"] and not final["setupService"]
        assert not final["failures"]
        # Removing the temporary option restores the public default, with no marker.
        (pending_dir / "system.zcfg").write_text("")
        assert not evaluate("oobe-test", "c: c.zenos.system.oobeMode")
        print("PASS: single-input installed flake, offline evaluation, ZCFG check/parse,")
        print("      local hardware, XDG, GNOME/KDE/headless choices, and declarative OOBE")
        print(f"Permanent desktop derivation: {desktop_drv}")

        if args.setup_source:
            # Import only the external generator. Never call installation/lifecycle functions.
            sys.dont_write_bytecode = True
            sys.path.insert(0, str(args.setup_source.resolve()))
            from src.builder import build_config_documents
            from src.runner import build_disko_zcfg, _write_host_documents

            generated_root = Path(work) / "generated"
            generated_host = generated_root / "hosts/generated-test"
            generated_host.mkdir(parents=True)
            payload = {"pages": [
                {"id": "computer_name", "hostname": "generated-test"},
                {"id": "user", "username": "alice", "fullname": "Fixture User"},
                {"id": "desktop", "install_de": False},
            ]}
            documents = build_config_documents(payload, password_hash="$6$fixture$not-a-login")
            _write_host_documents(
                str(generated_host), documents,
                extra_imports=("hardware.zcfg", "drives.zcfg"),
            )
            drives = build_disko_zcfg("/dev/vda")
            (generated_host / "drives.zcfg").write_text(drives)
            (generated_host / "hardware.zcfg").write_text(
                'legacy.boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" ];\n'
            )
            assert '_import "./hardware.zcfg";' in (generated_host / "host.zcfg").read_text()
            (generated_root / "flake.nix").write_text(template_text)
            generated_ref = f"path:{generated_root}"
            run("nix", "flake", "lock", "--offline", *override, generated_ref)
            actual = json.loads(run(
                "nix", "eval", "--offline", "--no-write-lock-file", "--json",
                f"{generated_ref}#nixosConfigurations.generated-test.config", "--apply", """c: {
                  disk = c.disko.devices.disk.main.device;
                  root = c.fileSystems."/".fsType;
                  boot = c.fileSystems."/boot".fsType;
                  host = c.networking.hostName;
                  uid = c.users.users.alice.uid;
                  home = c.users.users.alice.home;
                  shell = c.users.users.alice.shell.pname;
                  userPackages = builtins.length c.users.users.alice.packages;
                  gnome = c.services.desktopManager.gnome.enable;
                  drv = c.system.build.toplevel.drvPath;
                }""",
            ))
            assert actual["disk"] == "/dev/vda"
            assert actual["root"] == "ext4" and actual["boot"] == "vfat"
            assert actual["uid"] == 1000 and actual["home"] == "/Users/alice"
            assert actual["shell"] == "zsh" and actual["userPackages"] > 0
            assert actual["host"] == "generated-test" and not actual["gnome"]
            print("PASS: external Setup generator, automatic Disko filesystem mapping, hostname and user choices")


if __name__ == "__main__":
    main()

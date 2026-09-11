{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  releaseVersion = "1.0.0Nb";
  configHash = builtins.substring 0 7 (builtins.hashString "sha256" inputs.self.sourceInfo.narHash);
  displayVersion = "${releaseVersion} (${configHash})";
  setup = pkgs.zenos.system.zenos-setup;
  mode = pkgs.zenos.system.zenos-oobe-mode;
  sessionCommand = "${pkgs.coreutils}/bin/env XDG_SESSION_TYPE=wayland XDG_SESSION_CLASS=user XDG_SESSION_DESKTOP=GNOME XDG_CURRENT_DESKTOP=GNOME ZENOS_OOBE=1 ${config.services.displayManager.sessionData.wrapper} ${pkgs.gnome-session}/bin/gnome-session --session=zenos-oobe";
  normalUsers = lib.filterAttrs (_: user: user.enable && user.isNormalUser) config.users.users;
  bootHooks = import (inputs.zenpkgs + "/lib/installer-boot.nix") {
    inherit pkgs lib;
    bootPackage = pkgs.zenos.theming.system.zenos-plymouth.override {
      distroName = "ZenOS";
      releaseVersion = displayVersion;
      deviceName = "ZenOS Installer";
    };
    refindInstaller = pkgs.zenos.system.zenos-refind-installer;
    refindTheme = pkgs.zenos.theming.system.zenos-refind-theme;
  };
in
{
  imports = [
    (import (inputs.zenpkgs + "/lib/zenfs-runtime.nix") {
      managedUsers = lib.mapAttrs (_: user: { inherit (user) home group; }) normalUsers;
      includeBootAlias = false;
    })
    bootHooks.common
  ];
  zenos.system.installed-base.enable = false;
  zenos.system.zenfs.enable = true;
  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "26.05";
  system.nixos = {
    distroId = "zenos";
    distroName = "ZenOS";
    version = displayVersion;
    versionSuffix = "";
    label = "${releaseVersion}-${configHash}";
    vendorId = "zenos";
    vendorName = "ZenOS";
    extraOSReleaseArgs = {
      BUILD_ID = "${releaseVersion}-${configHash}";
      CPE_NAME = "cpe:/o:zenos:zenos:${releaseVersion}";
      LOGO = "zenos";
      VERSION = displayVersion;
      VERSION_ID = releaseVersion;
      PRETTY_NAME = "ZenOS ${displayVersion}";
    };
    extraLSBReleaseArgs = {
      DISTRIB_DESCRIPTION = "ZenOS ${displayVersion}";
      DISTRIB_ID = "ZenOS";
      DISTRIB_RELEASE = releaseVersion;
    };
  };
  system.image = {
    id = "zenos-installer";
    version = "${releaseVersion}-${configHash}";
  };
  system.configurationRevision = configHash;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.registry.zenpkgs.flake = inputs.zenpkgs;
  networking.networkmanager.enable = true;
  time.timeZone = lib.mkDefault "UTC";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
  console.keyMap = lib.mkDefault "us";
  users.mutableUsers = false;
  users.users = {
    root.hashedPassword = lib.mkDefault "!";
    zenos = {
      isNormalUser = true;
      description = "ZenOS Installer";
      home = "/Users/zenos";
      createHome = true;
      homeMode = "0700";
      hashedPassword = "";
      extraGroups = [
        "input"
        "networkmanager"
        "video"
        "wheel"
      ];
    };
  };
  security.sudo.wheelNeedsPassword = false;
  security.rtkit.enable = true;
  hardware.graphics.enable = true;
  hardware.enableRedistributableFirmware = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  services.fwupd.enable = true;
  services.fstrim.enable = true;
  services.qemuGuest.enable = true;
  zramSwap.enable = true;
  nix.settings.auto-optimise-store = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  services.desktopManager.gnome.enable = true;
  services.gnome.gnome-initial-setup.enable = false;
  services.displayManager = {
    gdm.enable = lib.mkForce false;
    autoLogin.enable = lib.mkForce false;
    autoLogin.user = lib.mkForce null;
    sddm.enable = lib.mkForce false;
    plasma-login-manager.enable = lib.mkForce false;
  };
  services.xserver.displayManager.lightdm.enable = lib.mkForce false;
  services.greetd = {
    enable = true;
    restart = false;
    settings = {
      initial_session = {
        command = sessionCommand;
        user = "zenos";
      };
      default_session = {
        command = sessionCommand;
        user = "zenos";
      };
    };
  };
  systemd.services.greetd.environment = {
    XDG_SESSION_TYPE = "wayland";
    XDG_SESSION_CLASS = "user";
    XDG_SESSION_DESKTOP = "GNOME";
  };
  environment.etc."xdg/gnome-session/sessions/zenos-oobe.session".text = ''
    [GNOME Session]
    Name=ZenOS Setup
  '';
  systemd.user.targets."gnome-session@zenos-oobe" = {
    overrideStrategy = "asDropin";
    unitConfig.Requires = [
      "gnome-session-services.target"
      "org.gnome.Shell@zenos-oobe.service"
    ];
  };
  systemd.user.services."org.gnome.Shell@zenos-oobe" = {
    overrideStrategy = "asDropin";
    environment = {
      PATH = lib.mkForce "/run/wrappers/bin:/run/current-system/sw/bin";
      ZENOS_OOBE = "1";
      GNOME_SHELL_SESSION_MODE = "zenos-oobe";
    };
  };
  systemd.user.services.zenos-setup = {
    description = "ZenOS installer";
    wantedBy = [ "graphical-session.target" ];
    after = [ "gnome-session.target" ];
    partOf = [ "graphical-session.target" ];
    unitConfig.ConditionUser = "zenos";
    path = lib.mkForce [ ];
    environment = {
      PATH = "/run/wrappers/bin:/run/current-system/sw/bin";
      ZENOS_SETUP_DRY_RUN = "0";
      ZENOS_OOBE = "0";
      GI_TYPELIB_PATH = lib.makeSearchPath "lib/girepository-1.0" [
        pkgs.gnome-desktop
        pkgs.libgweather
        pkgs.networkmanager
      ];
    };
    serviceConfig = {
      Type = "exec";
      ExecStart = lib.getExe setup;
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
  environment.systemPackages = [
    inputs.zenpkgs.packages.x86_64-linux.zen-dsl
    pkgs.nixos-rebuild
    pkgs.zenos.programs.zenos-rebuild
    setup
    mode
    pkgs.gnome-console
    pkgs.nautilus
  ];
  system.extraDependencies = [
    setup.src
    mode.src
  ];
  environment.pathsToLink = [
    "/bin"
    "/sbin"
    "/lib"
    "/libexec"
    "/share"
    "/share/gnome-shell/extensions"
    "/share/gnome-shell/modes"
  ];
  environment.gnome.excludePackages = [ pkgs.gnome-tour ];
  environment.sessionVariables = {
    XDG_CONFIG_HOME = "$HOME/.private/Config";
    XDG_DATA_HOME = "$HOME/.private/Packages";
    XDG_CACHE_HOME = "$HOME/.private/Live";
    XDG_STATE_HOME = "$HOME/.private/State";
    ZENOS_SETUP_DRY_RUN = "0";
    ZENOS_INSTALLER = "1";
  };
  home-manager = {
    useGlobalPkgs = lib.mkForce true;
    useUserPackages = lib.mkForce false;
    users = lib.mapAttrs (_: user: {
      home = {
        stateVersion = lib.mkDefault "26.05";
        username = lib.mkDefault user.name;
        homeDirectory = lib.mkDefault user.home;
      };
      xdg = {
        enable = true;
        configHome = "${user.home}/.private/Config";
        dataHome = "${user.home}/.private/Packages";
        cacheHome = "${user.home}/.private/Live";
        stateHome = "${user.home}/.private/State";
      };
    }) normalUsers;
  };
  programs.dconf.enable = true;
  systemd.tmpfiles.rules = [ "d /etc/ZenOS 0755 zenos users -" ];
}

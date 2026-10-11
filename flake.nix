{
  description = "Gliff-Manager for the Nixarchy bar: a NixOS-ready fork";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f s nixpkgs.legacyPackages.${s});
      manifest = builtins.fromJSON (builtins.readFile ./manifest.json);
    in
    {
      packages = forAll (
        _: pkgs:
        let
          # Plain copies only: omarchy's plugin validator refuses symlinks.
          plugin =
            pkgs.runCommand "nixarchy-gliff-manager-${manifest.version}"
              {
                meta = {
                  description = "Gliff remote desktop manager for the Nixarchy bar";
                  homepage = "https://github.com/olafkfreund/nixarchy-gliff-manager";
                  license = pkgs.lib.licenses.mit;
                  platforms = pkgs.lib.platforms.linux;
                };
              }
              ''
                mkdir -p $out
                cp ${./manifest.json} $out/manifest.json
                cp ${./LICENSE} $out/LICENSE
                cp ${./Panel.qml} $out/Panel.qml
                cp ${./gliff-manager.sh} $out/gliff-manager.sh
              '';
        in
        {
          default = plugin;
          nixarchy-gliff-manager = plugin;
        }
      );

      homeManagerModules.default =
        args@{
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.programs.gliff-manager;
          # Absent outside a NixOS-hosted Home Manager; a `?` default on the
          # argument itself would not be honoured.
          nixarchyOn = (args.osConfig or { }).programs.nixarchy.enable or false;
        in
        {
          options.programs.gliff-manager = {
            enable = lib.mkEnableOption "the Gliff-Manager bar widget";
            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
              description = "The plugin directory to link.";
            };
          };
          config = lib.mkIf cfg.enable (
            if nixarchyOn then
              {
                warnings = [
                  "programs.gliff-manager: nixarchy already ships Gliff-Manager as a default plugin; this module does nothing."
                ];
              }
            else
              {
                xdg.configFile."omarchy/plugins/nixarchy.gliff-manager".source = cfg.package;
                home.packages = map lib.lowPrio (
                  with pkgs;
                  [
                    jq
                    openssh
                    pciutils
                    procps
                    util-linux
                  ]
                );
              }
          );
        };

      checks = forAll (
        system: pkgs:
        let
          plugin = self.packages.${system}.default;
          hm =
            osConfig:
            home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                self.homeManagerModules.default
                {
                  home = {
                    username = "tester";
                    homeDirectory = "/home/tester";
                    stateVersion = "24.11";
                  };
                  programs.gliff-manager.enable = true;
                }
              ];
              extraSpecialArgs = { inherit osConfig; };
            };
          off = (hm { }).config;
          on = (hm { programs.nixarchy.enable = true; }).config;
          flag = pkgs.lib.boolToString;
        in
        {
          default =
            pkgs.runCommand "nixarchy-gliff-manager-check"
              {
                nativeBuildInputs = with pkgs; [
                  jq
                  shellcheck
                  qt6.qtdeclarative
                  bash
                  coreutils
                  findutils
                  gnugrep
                  procps
                  gawk
                ];
                offLinks = flag (off.xdg.configFile ? "omarchy/plugins/nixarchy.gliff-manager");
                offWarns = flag (off.warnings != [ ]);
                onLinks = flag (on.xdg.configFile ? "omarchy/plugins/nixarchy.gliff-manager");
                onWarns = flag (on.warnings != [ ]);
              }
              ''
                cd ${plugin}
                jq -e '.id == "nixarchy.gliff-manager" and (.id | startswith("omarchy.") | not)
                  and (.kinds | index("bar-widget")) != null' manifest.json
                test -f "$(jq -r .entryPoints.barWidget manifest.json)"
                test -z "$(find . -mindepth 1 -type l)"
                # A whole-line comment may name them; code may not.
                if grep -nwE 'pacman|yay' gliff-manager.sh Panel.qml |
                  grep -vE ':[0-9]+:[[:space:]]*(#|//)'; then
                  echo "pacman/yay on a non-comment line"; exit 1
                fi
                shellcheck -s sh gliff-manager.sh
                rc=0; qmllint Panel.qml || rc=$?
                [ "$rc" -ne 255 ]
                # The module: links the plugin when nixarchy is off, only warns when on.
                [ "$offLinks $offWarns $onLinks $onWarns" = "true false false true" ]
                cd "$TMPDIR"
                sh ${./tests/behaviour.sh} ${plugin}
                touch $out
              '';
        }
      );

      devShells = forAll (
        _: pkgs: {
          default = pkgs.mkShell {
            packages = with pkgs; [
              shellcheck
              jq
              qt6.qtdeclarative
            ];
          };
        }
      );

      formatter = forAll (_: pkgs: pkgs.nixfmt);
    };
}

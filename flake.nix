{
  description = "Simple NixOS VMs";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-20.09";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.flake-utils.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, flake-utils }:
    {
      nixosModule = { config, lib, pkgs, ... }:
        let
          types = lib.types;
        in
        {
          options = {
            boot.enableSimpleVMs = lib.mkOption {
              type = types.bool;
              default = false;
              description = ''
                Whether to enable support for simple-vms.
              '';
            };

            virtualMachines = lib.mkOption
              {
                type = types.attrsOf (types.submodule {
                  options.vm = lib.mkOption {
                    type = types.package;
                    description = ''
                      A derivation for the vm to use. e.g. a NixOS system's `config.system.build.vm`.
                    '';
                  };
                  options.persistState = lib.mkOption {
                    type = types.bool;
                    default = false;
                    description = ''
                      Whether to delete the drive pre & post start.
                    '';
                  };
                  options.autoStart = lib.mkOption {
                    type = types.bool;
                    description = ''
                      Whether to start VM this automatically.
                    '';
                    default = true;
                  };
                });
                default = { };
                example = lib.literalExample
                  ''
                    { 
                      database = {
                        vm = self.nixosConfigurations.database.config.system.build.vm;
                        persistState = true; 
                        autoStart = true; 
                      };
                    }
                  '';
                description = ''
                  A set whose values contain the config for a VM.
                '';
              };

          };

          config =
            let
              cleanupScript = name: persistState: pkgs.writeScript "cleanup" ''
                #!${pkgs.bash}/bin/bash
                ${if persistState then "" else "rm /var/lib/simple-vms/${name}/nixos.qcow2 || true"};
              '';
              mkService = name: cfg: {
                enable = cfg.autoStart;
                wantedBy = lib.optional cfg.autoStart "machines.target";
                serviceConfig.ExecStartPre = cleanupScript name cfg.persistState;
                serviceConfig.ExecStart = pkgs.writeScript "start-vm" ''
                  #!${pkgs.bash}/bin/bash
                  mkdir -p /var/lib/simple-vms/${name}
                  cd /var/lib/simple-vms/${name}
                  exec ${cfg.vm.out}/bin/run-nixos-vm;
                '';
                serviceConfig.ExecStopPost = cleanupScript name cfg.persistState;
              };
              mkNamedService = name: cfg: lib.nameValuePair "vm@${name}" (mkService name cfg);
            in
            lib.mkIf (config.boot.enableSimpleVMs) {
              systemd.targets."multi-user".wants = [ "machines.target" ];
              systemd.services = lib.listToAttrs (
                lib.mapAttrsToList mkNamedService config.virtualMachines
              );
            };
        };
    };
}

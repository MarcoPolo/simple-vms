# Simple VMs for NixOS

Sometimes you want to run a service without auditing the whole codebase. And
gvisor (or similar) either doesn't work or is tricky to setup. This is for that.

This provides a NixOS module you can use that will create a systemd service that
will start a VM and keep it running. It uses the existing [qemu
vm](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/qemu-vm.nix)
support in NixPkgs. It's really just a thin layer over a systemd service.

## Example

This example has a machine we call `server` and a vm called `small-vm`. The
`small-vm` is defined just like any other NixOS machine. Then the VM definition
is passed to `server`'s config. The `simple-vms` NixOS module takes care of
starting it up.

`flake.nix`
```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-20.09";

  inputs.simple-vms.url = "/home/marco/code/simple-vms";
  inputs.simple-vms.inputs.nixpkgs.follows = "nixpkgs";
  inputs.simple-vms.inputs.flake-utils.follows = "flake-utils";

  outputs = { self , nixpkgs , simple-vms }: {
      nixosConfigurations = {
        server = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            {
              imports = [ simple-vms.nixosModule ];
              boot.enableSimpleVMs = true;
              virtualMachines = {
                downloader = {
                  vm = self.nixosConfigurations.small-vm.config.system.build.vm;
                  autoStart = true;
                  persistState = false;
                };
              };

              # The rest of your config
              # ...
            }
          ];
        };
        # You can test this by running:
        # nix build .#nixosConfigurations.downloader.config.system.build.vm  
        # Then running result/bin/run-nixos-vm
        small-vm = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ({ lib, pkgs, modulesPath, ... }: {
                imports = [
                  (modulesPath + "/virtualisation/qemu-vm.nix")
                ];
                users.mutableUsers = false;
                security.sudo.wheelNeedsPassword = false;
                virtualisation = {
                  memorySize = 1024;
                  graphics = false;
                  qemu.networkingOptions = [
                    # We need to re-define our usermode network driver
                    # since we are overriding the default value.
                    "-net nic,netdev=user.0,model=virtio,"
                    # Then we can use qemu's hostfwd option to forward ports.
                    "-netdev user,hostfwd=tcp::8222-:22,id=user.0\${QEMU_NET_OPTS:+,$QEMU_NET_OPTS}"
                  ];
                };
                services.openssh.enable = true;
                environment.systemPackages = with pkgs; [ git wget vim zsh htop ];

                users.users.marco = {
                  isNormalUser = true;
                  shell = pkgs.zsh;
                  extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
                  createHome = true;
                  openssh.authorizedKeys.keys = [
                    "ssh-ed25519 AAAAC3xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx7 marco@server"
                  ];
                };
              })
            ];
          }
 ;
      };
    };
}

```
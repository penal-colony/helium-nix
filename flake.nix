{
  description = "Helium browser packaged from source for Nix/NixOS";

  nixConfig = {
    extra-substituters = [ "https://helium-nix.cachix.org" ];
    extra-trusted-public-keys = [ "helium-nix.cachix.org-1:a8YPjt9O4GPyX0u3gjg/aWpb14teU9aRiSG/MOaSFgw=" ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          helium = pkgs.callPackage ./default.nix { };
          helium-ccache = pkgs.callPackage ./default.nix { enableCcache = true; };
          default = self.packages.${system}.helium;
        });

      overlays.default = final: prev: {
        helium = final.callPackage ./default.nix { };
      };
    };
}

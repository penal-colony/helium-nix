{
  description = "Helium browser packaged from source for Nix/NixOS";

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

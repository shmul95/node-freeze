{ ... }:
{
  perSystem = { pkgs, self', ... }: {
    devShells.default = pkgs.mkShell {
      packages = [
        self'.packages.default
        pkgs.nixfmt
      ];
    };
  };
}

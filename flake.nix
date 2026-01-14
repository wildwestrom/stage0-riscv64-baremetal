{
  description = "RISC-V toolchain based on the rocket-chip flake";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        legacyPackages = pkgs;
        devShell = pkgs.mkShell.override { stdenv = pkgs.clangStdenv; } {
          buildInputs = with pkgs; [
            pkgsCross.riscv64-embedded.buildPackages.gcc
            pkgsCross.riscv64-embedded.buildPackages.gdb
            qemu
            clang-tools
            tup
          ];
        };
      }
    );
}

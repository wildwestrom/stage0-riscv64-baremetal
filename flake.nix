{
  description = "RISC-V toolchain based on the rocket-chip flake";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    qemu-cheri-flake.url = "github:wildwestrom/qemu-cheri-flake";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      qemu-cheri-flake,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        qemu-cheri = qemu-cheri-flake.packages.${system}.default;
      in
      {
        legacyPackages = pkgs;
        checks.default = pkgs.stdenv.mkDerivation {
          name = "stage0-riscv64-test";
          src = ./.;
          nativeBuildInputs = [
            qemu-cheri
            pkgs.just
            pkgs.unixtools.xxd
          ];
          buildPhase = ''
            just test
          '';
          installPhase = ''
            touch $out
          '';
        };
        devShells.default = pkgs.mkShell.override { stdenv = pkgs.clangStdenv; } {
          packages = with pkgs; [
            pkgsCross.riscv64-embedded.buildPackages.gcc
            pkgsCross.riscv64-embedded.buildPackages.gdb
            qemu-cheri
            clang-tools
            just
            pkgs.unixtools.xxd
          ];
        };
      }
    );
}

{
  description = "Small COBOL applications built with GnuCOBOL";

  # The one pin for the toolchain. The app Dockerfiles build from the
  # same nixpkgs revision (their NIXPKGS build arg), and CI checks that
  # they match flake.lock.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # One app's CLI, built and tested by its own Makefile.
      app = pkgs: name: pkgs.stdenv.mkDerivation {
        pname = name;
        version = "0.0.0";
        src = ./${name};
        # The ledger tests URL-encode form posts with Python.
        nativeBuildInputs = [ pkgs.gnucobol.bin pkgs.python3 ];
        postPatch = "patchShebangs tests";
        doCheck = true;
        checkTarget = "test";
        installFlags = [ "PREFIX=$(out)" ];
        meta.mainProgram = name;
      };
    in
    {
      packages = forAllSystems (pkgs: {
        amortise = app pkgs "amortise";
        ledger = app pkgs "ledger";
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.gnucobol.bin pkgs.gnumake pkgs.python3 ];
        };
      });
    };
}

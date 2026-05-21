{
  description = "LAN CTF toolkit: reproducible dev shell + challenge-image builders for an Ubuntu/Docker host";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        # ----------------------------------------------------------------------
        # Dev shell: everything you need to AUTHOR and TEST challenges, plus the
        # admin tooling to drive the compose stack. Enter with `nix develop`.
        #
        # Why a flake for this at all (on Ubuntu): it pins exact versions of gcc,
        # gdb, pwntools, etc. So every club member who runs `nix develop` gets a
        # byte-identical toolchain regardless of their machine's apt state. That
        # reproducibility matters most for pwn/reversing challenges, where the
        # exact compiler and libc affect whether an exploit works.
        # ----------------------------------------------------------------------
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            # Container orchestration (talks to the Ubuntu host's Docker daemon)
            docker-compose

            # Challenge authoring / testing
            python3
            python3Packages.pwntools     # exploit dev + local testing of pwn challs
            python3Packages.requests     # scripting CTFd's API, smoke-testing web challs
            python3Packages.pycryptodome # building crypto challenges
            gcc
            gdb
            binutils                     # objdump, strings, readelf for reversing
            file
            socat                        # per-connection wrapper for pwn services

            # Recon / verification tooling to confirm isolation actually works
            nmap
            netcat-gnu
            jq
          ];

          shellHook = ''
            echo "=== CTF authoring shell ==="
            echo "Build a challenge image:  docker compose build <service>"
            echo "Bring the stack up:       docker compose up -d"
            echo "Verify isolation:         see RUNBOOK.md section 6"
          '';
        };

        formatter = pkgs.nixpkgs-fmt;
      });
}

{
  description = "LAN CTF toolkit: reproducible dev shells (authoring + red/blue team) and challenge image builders for an Ubuntu/Docker host";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        # allowUnfree is needed for a few security tools (e.g. burpsuite) whose
        # licenses nixpkgs marks unfree. Scoped to this flake only.
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        # ====================================================================
        # SHARED TOOL GROUPS
        # Defined once, composed into the role shells below so there's no
        # copy-paste drift. Each group is just a list of nixpkgs packages.
        # ====================================================================

        # Baseline every shell gets: shell niceties + the absolute basics.
        baseTools = with pkgs; [
          coreutils curl wget git jq file vim tmux
        ];

        # Tools for AUTHORING and TESTING challenges (the original shell).
        authoringTools = with pkgs; [
          docker-compose
          python3
          python3Packages.pwntools
          python3Packages.requests
          python3Packages.pycryptodome
          gcc gdb binutils socat
        ];

        # RED TEAM: offense. Recon, web, exploitation, cracking, reversing.
        # Dual-use security tools — see the ethics banner and TEAM-TOOLKITS.md.
        # Use ONLY against the club's own CTF targets / authorized systems.
        redTeamTools = with pkgs; [
          # Recon / scanning
          nmap masscan rustscan
          # Web testing
          ffuf gobuster nikto sqlmap burpsuite whatweb
          # Exploitation framework
          metasploit
          # Password / hash cracking
          hashcat john hydra
          # Reverse engineering / pwn
          ghidra-bin radare2 gdb python3Packages.pwntools
          # Wordlists
          seclists wordlists
          # Network / pivoting helpers
          netcat-gnu socat proxychains-ng
        ];

        # BLUE TEAM: defense. Traffic analysis, forensics, detection, IR.
        blueTeamTools = with pkgs; [
          # Packet capture / analysis
          wireshark tshark tcpdump
          # Network visibility
          nmap ngrep iftop
          # Detection / IDS
          suricata zeek yara
          # Host & file forensics
          binwalk foremost sleuthkit exiftool
          # Integrity / hashing
          openssl
          # Container introspection (watch the CTF stack itself)
          docker-compose dive
        ];

        # CTF PLAYER mid-ground: the offense tools sized to these four
        # challenge categories, without the full red-team arsenal.
        playerTools = with pkgs; [
          nmap curl ffuf gobuster sqlmap
          python3 python3Packages.pwntools python3Packages.pycryptodome
          gdb radare2 binwalk exiftool netcat-gnu socat
        ];

        # Banner + shared ethics reminder stamped into each shell.
        mkBanner = role: extra: ''
          echo ""
          echo "============================================================"
          echo "  CTF environment - ${role} shell"
          echo "============================================================"
          echo "  Authorized use ONLY: the club's own CTF targets and"
          echo "  systems you have explicit permission to test. These are"
          echo "  dual-use tools; using them against anything else may be"
          echo "  illegal. You are responsible for staying in scope."
          echo "------------------------------------------------------------"
          ${extra}
          echo ""
        '';

      in
      {
        devShells = {
          # default = challenge AUTHORING.  `nix develop`
          default = pkgs.mkShell {
            packages = baseTools ++ authoringTools;
            shellHook = mkBanner "authoring" ''
              echo "  Build a challenge image:  docker compose build <svc>"
              echo "  Bring the stack up:       docker compose up -d"
              echo "  Verify isolation:         see RUNBOOK.md section 6"
            '';
          };

          # red = OFFENSE toolkit.  `nix develop .#red`
          red = pkgs.mkShell {
            packages = baseTools ++ redTeamTools;
            shellHook = mkBanner "RED TEAM (offense)" ''
              echo "  Recon:        nmap / rustscan / masscan"
              echo "  Web:          ffuf gobuster nikto sqlmap burpsuite"
              echo "  Exploitation: msfconsole (metasploit)"
              echo "  Cracking:     hashcat john hydra"
              echo "  Reversing:    ghidra radare2 gdb pwntools"
            '';
          };

          # blue = DEFENSE toolkit.  `nix develop .#blue`
          blue = pkgs.mkShell {
            packages = baseTools ++ blueTeamTools;
            shellHook = mkBanner "BLUE TEAM (defense)" ''
              echo "  Capture:   wireshark / tshark / tcpdump"
              echo "  Detect:    suricata zeek yara"
              echo "  Forensics: binwalk foremost sleuthkit exiftool"
              echo "  Stack:     dive (inspect image layers), docker compose"
            '';
          };

          # player = lean offense kit sized to THESE four challenges.
          # `nix develop .#player`
          player = pkgs.mkShell {
            packages = baseTools ++ playerTools;
            shellHook = mkBanner "CTF PLAYER" ''
              echo "  web:       curl ffuf gobuster sqlmap"
              echo "  pwn:       gdb radare2 pwntools (python3)"
              echo "  crypto:    python3 + pycryptodome"
              echo "  forensics: binwalk exiftool"
            '';
          };
        };

        formatter = pkgs.nixpkgs-fmt;
      });
}

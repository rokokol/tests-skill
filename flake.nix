{
  description = "A standard for tests that mean something when they are green";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      # Darwin too: the harness travels to repositories that run CI on macOS, and a
      # contributor there gets `nix develop -c ./check.sh` rather than a flake that does
      # not know their system. Apple silicon only — Apple stopped selling Intel machines
      # in 2023 and nixpkgs 26.11 dropped x86_64-darwin, so naming it was a platform this
      # flake could not even be evaluated for, which the gate now refuses.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # The pinned toolbox for check.sh, locally and in CI. Every tool a check runs comes
      # from here rather than from whatever the runner happens to have: an unpinned lookup
      # changes a check's behaviour with zero change in the repository
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            actionlint
            # The lint half reads t.sh with awk, and the awks disagree about what they say
            # on a program: only gawk names an escape POSIX leaves undefined. Unpinned, the
            # proof that the gate catches such an escape would pass on a Linux runner and
            # fail on a contributor's mac for the awk, not for the defect
            gawk
            shellcheck
            shfmt
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}

# nvm-freeze / node-freeze

A tiny flake that gives you:

- `node-freeze`
- `nvm-freeze`

Both names point to the same tool.

This repo follows the dendritic pattern from `shmulistan`: a minimal `flake.nix`,
with one concern per file under `modules/` and auto-loading via `import-tree`.

It freezes a concrete Node.js version into a `.node-source.nix` file:

```nix
{
  version = "24.15.0";
  sha256 = "sha256-...";
}
```

Then downstream projects can package the official upstream Node.js tarball with:

```nix
freezedNodejs = inputs.nvm-freeze.lib.mkFreezedNode pkgs ./.node-source.nix;
```

## Why

This is meant to feel a bit like NVM for choosing a version, but produce a Nix-pinned source file for reproducibility.

## Commands

```bash
node-freeze
nvm-freeze

node-freeze 24.15.0
nvm-freeze 24.15.0

node-freeze --from-nvmrc
nvm-freeze --from-nvmrc

node-freeze --path modules
nvm-freeze --path modules
```

## Behavior

* no args: uses the currently active Node version from `node -v`
* explicit version: uses that exact semver
* `--from-nvmrc`: reads `.nvmrc`
* `--path modules`: writes `modules/.node-source.nix`

## Local development

```bash
nix develop
node-freeze --help
```

## Repo structure

```text
.
├── flake.nix
├── flake.lock
├── modules/
│   ├── dev-shell.nix
│   ├── lib.nix
│   ├── packages.nix
│   └── systems.nix
└── README.md
```

## Example downstream flake

```nix
{
  description = "example project using nvm-freeze";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nvm-freeze.url = "github:YOUR_GITHUB_USER/nvm-freeze";
  };

  outputs = { self, nixpkgs, nvm-freeze }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      freezedNodejs = nvm-freeze.lib.mkFreezedNode pkgs ./.node-source.nix;
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          freezedNodejs
          nvm-freeze.packages.${system}.default
        ];
      };

      packages.${system}.freezedNodejs = freezedNodejs;
    };
}
```

## Typical workflow

If you already have Node active in your shell:

```bash
node -v
node-freeze
```

If you want an explicit version:

```bash
node-freeze 24.15.0
```

If your project has `.nvmrc`:

```bash
node-freeze --from-nvmrc
```

Then enter your project shell:

```bash
nix develop
node -v
```

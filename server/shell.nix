{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    elixir
    elixir-ls
    sqlite
    nodejs
    nodePackages.typescript
    nodePackages.typescript-language-server
    nodePackages.prettier
  ];
}


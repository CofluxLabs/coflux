{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    elixir
    elixir-ls
    sqlite-interactive
    nodejs
    nodePackages.typescript
    nodePackages.typescript-language-server
    nodePackages.prettier
  ];
}


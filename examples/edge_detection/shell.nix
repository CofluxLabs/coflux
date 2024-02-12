{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = [
    pkgs.python311
    pkgs.nodePackages.pyright
    pkgs.ruff-lsp
    pkgs.black
  ];
}

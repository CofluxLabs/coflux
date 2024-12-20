{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = [
    pkgs.python311
    pkgs.poetry
    pkgs.pyright
    pkgs.ruff-lsp
    pkgs.black
  ];
}

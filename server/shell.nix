{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = [
    pkgs.elixir
    pkgs.elixir-ls
    pkgs.sqlite
  ];
}


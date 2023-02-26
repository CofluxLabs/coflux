{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = [
    pkgs.elixir_1_14
    pkgs.elixir_ls
    pkgs.postgresql
  ];
}


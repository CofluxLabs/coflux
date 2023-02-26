{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    nodejs
    yarn
    nodePackages.typescript
    nodePackages.typescript-language-server
    nodePackages.prettier
  ];
}

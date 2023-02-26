{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    nodejs
    nodePackages.typescript
    nodePackages.typescript-language-server
    nodePackages.prettier
  ];
}

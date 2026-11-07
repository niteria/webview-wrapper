{
  description = "Android WebView wrappers for websites, built with the Android SDK";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/46db2e09e1d3f113a13c0d7b81e2f221c63b8ce9";
  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAll = nixpkgs.lib.genAttrs systems;
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };
    in
    {
      # lib.<system>.{mkApk, mkSigner, keygen}; see README.md.
      lib = forAll (system: import ./lib.nix { pkgs = pkgsFor system; });
      packages = forAll (system: {
        inherit (self.lib.${system}) keygen;
        example = self.lib.${system}.mkApk {
          name = "example";
          title = "Example";
          url = "https://example.org/";
        };
      });
      checks = forAll (system: {
        inherit (self.packages.${system}) example;
        trusted-ca = self.lib.${system}.mkApk {
          name = "trusted";
          title = "Trusted \"CA\" & co";
          url = "https://example.test/";
          noun = "printer";
          allowCleartext = false;
          trustedCertificate = ./tests/ca.pem;
          trustedDomains = [ "example.test" ];
        };
      });
      formatter = forAll (system: (pkgsFor system).nixfmt);
    };
}

{
  description = "SelfPrivacy module for Headscale";

  outputs = { self }: {
    nixosModules.default = import ./module.nix;

    configPathsNeeded =
      builtins.fromJSON (builtins.readFile ./config-paths-needed.json);

    meta = { lib, ... }: {
      spModuleSchemaVersion = 1;
      id = "headscale";
      name = "Headscale";
      description = "Open-source coordination server for Tailscale clients";
      svgIcon = builtins.readFile ./icon.svg;

      showUrl = true;
      primarySubdomain = "subdomain";

      isMovable = true;
      isRequired = false;
      canBeBackedUp = true;
      backupDescription = "Headscale state and database.";

      systemdServices = [ "headscale.service" ];
      user = "headscale";
      group = "headscale";

      folders = [
        "/var/lib/headscale"
      ];

      homepage = "https://headscale.net";
      sourcePage = "https://github.com/juanfont/headscale";
      supportLevel = "normal";
      license = [ lib.licenses.bsd3 ];
    };
  };
}

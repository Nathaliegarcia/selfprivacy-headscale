{ config, lib, pkgs, ... }:

let
  sp = config.selfprivacy;
  cfg = sp.modules.headscale;

  fqdn = "${cfg.subdomain}.${sp.domain}";
  dataDir = "/var/lib/headscale";
in
{
  options.selfprivacy.modules.headscale = {
    enable = (lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Headscale";
    }) // {
      meta = {
        type = "enable";
      };
    };

    location = (lib.mkOption {
      type = lib.types.str;
      description = "Data location";
      default = "/volumes/${config.selfprivacy.useBinds.defaultVolume or "sda1"}/headscale";
    }) // {
      meta = {
        type = "location";
      };
    };

    subdomain = (lib.mkOption {
      default = "vpn";
      type = lib.types.strMatching "[A-Za-z0-9][A-Za-z0-9\\-]{0,61}[A-Za-z0-9]";
      description = "Subdomain for Headscale";
    }) // {
      meta = {
        widget = "subdomain";
        type = "string";
        regex = "[A-Za-z0-9][A-Za-z0-9\\-]{0,61}[A-Za-z0-9]";
        weight = 0;
      };
    };

    baseDomain = (lib.mkOption {
      type = lib.types.str;
      default = "tail.vpn";
      description = "MagicDNS base domain used by Headscale";
    }) // {
      meta = {
        type = "string";
        weight = 1;
      };
    };

    enableDerp = (lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable embedded DERP server";
    }) // {
      meta = {
        type = "bool";
        weight = 2;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = sp.domain != null && sp.domain != "";
        message = "selfprivacy.domain must be set for the Headscale module.";
      }
    ];

    fileSystems.${dataDir} = lib.mkIf (sp.useBinds or false) {
      device = cfg.location;
      fsType = "none";
      options = [ "bind" ];
    };

    services.headscale = {
      enable = true;

      settings = {
        server_url = "https://${fqdn}";
        listen_addr = "127.0.0.1:8098";
        metrics_listen_addr = "127.0.0.1:9090";

        tls_cert_path = null;
        tls_key_path = null;

        log = {
          format = "text";
          level = "info";
        };

        dns = {
          override_local_dns = false;
          base_domain = cfg.baseDomain;
          magic_dns = true;
        };

        derp = lib.mkIf cfg.enableDerp {
          server = {
            enabled = true;
            region_id = 999;
            region_code = "selfprivacy";
            region_name = "SelfPrivacy DERP";
            stun_listen_addr = "0.0.0.0:3478";
          };
        };
      };
    };

    services.nginx = {
      enable = true;

      virtualHosts.${fqdn} = {
        enableACME = true;
        forceSSL = true;

        locations."/" = {
          proxyPass = "http://127.0.0.1:8098";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };
    };

    security.acme = {
      acceptTerms = true;
      defaults.email = "hass@${sp.domain}";
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
    networking.firewall.allowedUDPPorts = lib.mkIf cfg.enableDerp [ 3478 ];
  };
}

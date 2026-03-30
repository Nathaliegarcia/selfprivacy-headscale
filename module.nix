{ config, lib, pkgs, ... }:

let
  sp = config.selfprivacy;
  cfg = sp.modules.headscale;

  dataDir = "/var/lib/headscale";

  auth-passthru = sp.passthru.auth or null;
  hasAuth       = sp.sso.enable or false;

  oauthClientID = "headscale";
  adminsGroup   = "sp.headscale.admins";
  usersGroup    = "sp.headscale.users";
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
      default = "headscale";
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
        server_url = "https://${cfg.subdomain}.${sp.domain}";
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

      virtualHosts."${cfg.subdomain}.${sp.domain}" = {
        useACMEHost = sp.domain;
        forceSSL = true;

        locations."/" = {
          proxyPass = "http://127.0.0.1:8098";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_redirect http:// https://;
            proxy_buffering off;
          '';
        };
      };
    };

    services.headscale.settings.oidc = lib.mkIf hasAuth {
      issuer                          = "https://auth.${sp.domain}/oauth2/openid/${oauthClientID}";
      client_id                       = oauthClientID;
      client_secret_path              = auth-passthru.mkOAuth2ClientSecretFP "headscale";
      only_start_if_oidc_is_available = false;
      allowed_groups                  = [ usersGroup adminsGroup ];
      pkce.enabled                    = true;
    };

    selfprivacy.auth.clients = lib.mkIf hasAuth {
      ${oauthClientID} = {
        inherit adminsGroup usersGroup;
        imageFile     = ./icon.svg;
        displayName   = "Headscale";
        subdomain     = cfg.subdomain;
        isTokenNeeded = false;
        originUrl     = "https://${cfg.subdomain}.${sp.domain}/oidc/callback";
        originLanding = "https://${cfg.subdomain}.${sp.domain}";
        enablePkce    = true;
        clientSystemdUnits = [ "headscale.service" ];
        scopeMaps = {
          "${usersGroup}"  = [ "openid" "email" "profile" ];
          "${adminsGroup}" = [ "openid" "email" "profile" ];
        };
      };
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
    networking.firewall.allowedUDPPorts = lib.mkIf cfg.enableDerp [ 3478 ];
  };
}

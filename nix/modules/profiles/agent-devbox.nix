# Persistent, low-idle-footprint development coordinator. Expensive database
# and browser verification belongs on isolated runners rather than this guest.
{ lib, pkgs, unstablePkgs, ... }:
let
  agent-local-check = pkgs.writeShellApplication {
    name = "agent-local-check";
    runtimeInputs = [ pkgs.coreutils pkgs.systemd ];
    text = ''
      if [ "$#" -eq 0 ]; then
        echo "usage: agent-local-check <command> [args...]" >&2
        exit 2
      fi
      exec systemd-run --user --scope --quiet --collect \
        --property=MemoryMax=2G \
        --property=MemorySwapMax=512M \
        timeout --signal=TERM --kill-after=5s 30s "$@"
    '';
  };
  githubSecret = pkgs.writeShellApplication {
    name = "agent-github-secret";
    runtimeInputs = with pkgs; [ coreutils jq openbao ];
    text = ''
      set -euo pipefail
      test "$(id -u)" -eq 0 || { echo "root execution required" >&2; exit 1; }
      bootstrap=/var/lib/agent-secrets/approle.env
      test -r "$bootstrap" || { echo "missing AppRole bootstrap" >&2; exit 1; }
      set -a
      # shellcheck disable=SC1090
      source "$bootstrap"
      set +a
      : "''${BAO_ROLE_ID:?missing BAO_ROLE_ID}"
      : "''${BAO_SECRET_ID:?missing BAO_SECRET_ID}"
      export BAO_ADDR="''${BAO_ADDR:-https://openbao.sulibot.com}"
      token="$(bao write -format=json auth/approle/login role_id="$BAO_ROLE_ID" secret_id="$BAO_SECRET_ID" | jq -er '.auth.client_token')"
      BAO_TOKEN="$token" bao kv get -format=json -mount=kv automation/agent-devbox01/github-dispatch | jq -e '.data.data'
    '';
  };
  githubSigner = pkgs.writeShellApplication {
    name = "agent-sign-verification-dispatch";
    runtimeInputs = with pkgs; [ coreutils gawk jq openssl ];
    text = ''
      set -euo pipefail
      secret="$(${lib.getExe githubSecret})"
      key="$(jq -er '.hmac_key' <<<"$secret")"
      test "''${#key}" -ge 32 || { echo "invalid dispatch key" >&2; exit 1; }
      openssl dgst -sha256 -hmac "$key" -hex | awk '{print $NF}'
    '';
  };
  githubExec = pkgs.writeShellApplication {
    name = "agent-github-exec";
    runtimeInputs = with pkgs; [ coreutils curl jq openssl util-linux ];
    text = ''
      set -euo pipefail
      phase="''${1:-}"
      test "$#" -ge 2 || { echo "usage: agent-github-exec <ref-write|observe> <command> [args...]" >&2; exit 2; }
      shift
      case "$phase" in
        ref-write) permissions='{"contents":"write"}' ;;
        observe) permissions='{"actions":"read","checks":"read","contents":"read"}' ;;
        *) echo "unsupported GitHub token phase" >&2; exit 2 ;;
      esac
      secret="$(${lib.getExe githubSecret})"
      app_id="$(jq -er '.app_id' <<<"$secret")"
      installation_id="$(jq -er '.installation_id' <<<"$secret")"
      key_file="$(mktemp)"
      trap 'rm -f "$key_file"' EXIT
      jq -er '.private_key' <<<"$secret" >"$key_file"
      chmod 0600 "$key_file"
      base64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
      now="$(date +%s)"
      header="$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | base64url)"
      payload="$(jq -cn --argjson iat "$((now - 60))" --argjson exp "$((now + 540))" --arg iss "$app_id" '{iat:$iat,exp:$exp,iss:$iss}' | base64url)"
      unsigned="$header.$payload"
      signature="$(printf '%s' "$unsigned" | openssl dgst -sha256 -sign "$key_file" -binary | base64url)"
      jwt="$unsigned.$signature"
      token="$(curl --silent --show-error --fail-with-body --request POST \
        --header "Authorization: Bearer $jwt" \
        --header 'Accept: application/vnd.github+json' \
        --header 'X-GitHub-Api-Version: 2022-11-28' \
        --data "{\"permissions\":$permissions}" \
        "https://api.github.com/app/installations/$installation_id/access_tokens" | jq -er '.token')"
      exec runuser -u agent -- env HOME=/home/agent GH_TOKEN="$token" GITHUB_TOKEN="$token" "$@"
    '';
  };
in
{
  programs = {
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    nix-ld.enable = true;
    ssh.knownHosts.github = {
      hostNames = [ "github.com" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
    };
    zsh.enable = true;
  };

  users.users.agent = {
    isNormalUser = true;
    description = "Agent development coordinator";
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILS7qW4IWbXx+9hk1A59X8vTtj5gCiEglr+cKNA+gRe5 sulibot@gmail.com"
    ];
  };

  security.sudo.extraRules = [
    {
      users = [ "agent" ];
      commands = [
        {
          command = lib.getExe githubSigner;
          options = [ "NOPASSWD" ];
        }
        {
          command = lib.getExe githubExec;
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  nix.settings = {
    auto-optimise-store = true;
    max-jobs = 2;
    cores = 2;
  };

  environment.systemPackages = with pkgs; [
    agent-local-check
    githubExec
    githubSigner
    unstablePkgs.codex
    unstablePkgs.claude-code
    corepack
    curl
    fd
    fzf
    gcc
    gh
    git-lfs
    gnumake
    jq
    kubectl
    kubernetes-helm
    kustomize
    nodejs_24
    openssl
    pkg-config
    postgresql_17
    python3
    ripgrep
    rsync
    tmux
    yq-go
  ];
}

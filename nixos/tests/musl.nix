{ hostPkgs, ... }:
{
  name = "musl";

  node.pkgsReadOnly = false;

  defaults =
    { modulesPath, ... }:
    {
      imports = [ (modulesPath + "/profiles/minimal.nix") ];
      nixpkgs.buildPlatform = hostPkgs.stdenv.buildPlatform.system;
      nixpkgs.hostPlatform = "x86_64-unknown-linux-musl";

      boot.loader.grub.enable = false;
      virtualisation.qemu.guestAgent.enable = false;
      virtualisation.graphics = false;

      # Ensure no glibc leaks into the musl NixOS runtime closure.
      system.forbiddenDependenciesRegexes = [ "glibc" ];
    };

  nodes = {
    server = {
      nix.enable = true;
      system.switch.enable = true;
      boot.loader.systemd-boot.enable = true;

      networking.useNetworkd = true;
      networking.dhcpcd.enable = false;
      services.resolved.enable = true;

      services.openssh = {
        enable = true;
        settings.PasswordAuthentication = false;
      };

      security.sudo.enable = true;
      users.users.alice = {
        isNormalUser = true;
        password = "secret";
        extraGroups = [ "wheel" ];
      };

      specialisation.switched.configuration = {
        environment.etc."musl-switched".text = "ok\n";
        users.users.bob = {
          isNormalUser = true;
          password = "secret";
        };
      };
    };

    client = {
      networking.dhcpcd.enable = true;
    };
  };

  testScript = ''
    def check_musl_only(node, pid):
      node.succeed(f"grep -q musl /proc/{pid}/maps")
      node.fail(f"grep -qi glibc /proc/{pid}/maps")

    def check_service_musl(node, unit):
      node.wait_for_unit(unit)
      pid = node.succeed(f"systemctl show -p MainPID --value {unit}").strip()
      assert pid and pid != "0", f"No MainPID for {unit} on {node.name}"
      check_musl_only(node, pid)

    def check_system_healthy(node):
      node.wait_for_unit("multi-user.target")
      check_musl_only(node, 1)
      status = node.succeed("systemctl is-system-running").strip()
      assert status == "running", f"{node.name}: unexpected systemd state: {status}"
      failed = node.succeed("systemctl --failed --no-legend").strip()
      assert failed == "", f"{node.name}: failed units: {failed}"
      journal_err = node.succeed("journalctl -b -p err --no-pager -o cat").strip()
      assert journal_err == "", f"{node.name}: journal errors: {journal_err}"

    start_all()

    check_system_healthy(server)
    check_system_healthy(client)

    with subtest("core daemons run on musl without glibc"):
      check_service_musl(server, "sshd.service")
      check_service_musl(server, "systemd-networkd.service")
      check_service_musl(server, "systemd-resolved.service")
      check_service_musl(client, "dhcpcd.service")

    with subtest("cross-VM SSH key authentication works"):
      client.succeed('mkdir -p /root/.ssh && ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519')
      pubkey = client.succeed("cat /root/.ssh/id_ed25519.pub").strip()
      server.succeed("su - alice -c 'mkdir -p ~/.ssh && chmod 700 ~/.ssh'")
      server.succeed(f"printf '%s\\n' '{pubkey}' > /home/alice/.ssh/authorized_keys")
      server.succeed("chown alice:users /home/alice/.ssh/authorized_keys && chmod 600 /home/alice/.ssh/authorized_keys")
      ssh_out = client.succeed("ssh -o StrictHostKeyChecking=no -o BatchMode=yes alice@server id").strip()
      assert "uid=1000(alice)" in ssh_out, f"Unexpected SSH id output: {ssh_out}"

    with subtest("sudo SUID wrapper and PAM authentication work"):
      sudo_out = server.succeed("su - alice -c 'echo secret | sudo -S id'").strip()
      assert "uid=0(root)" in sudo_out, f"Unexpected sudo output: {sudo_out}"

    with subtest("resolved, bootctl, nix, and kbd work"):
      server.succeed("resolvectl status --no-pager")
      server.succeed("getent hosts localhost")
      server.succeed("bootctl --version")
      server.succeed("nix --version")
      server.succeed("loadkeys -b us >/dev/null")

    with subtest("live switch-to-configuration works on musl"):
      server.fail("test -e /etc/musl-switched")
      server.fail("id bob")
      switched = server.succeed("readlink -f /run/current-system/specialisation/switched").strip()
      server.succeed(f"{switched}/bin/switch-to-configuration test")
      server.succeed('test "$(cat /etc/musl-switched)" = ok')
      server.succeed("id bob")
      assert server.succeed("systemctl is-system-running").strip() == "running"
  '';
}

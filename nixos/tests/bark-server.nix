{ lib, ... }:
{

  name = "bark-server";

  meta = {
    maintainers = with lib.maintainers; [ moraxyc ];
  };

  nodes.machine =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.curl ];
      services.bark-server = {
        enable = true;
      };
    };

  testScript = ''
    machine.wait_for_unit("bark-server.service")

    machine.wait_for_open_port(8080)

    machine.succeed("curl --fail --max-time 10 http://127.0.0.1:8080/ping")
  '';
}

defmodule Wardwright.CLITest do
  use ExUnit.Case, async: true

  alias Wardwright.CLI.Admin

  test "bare command prints help instead of starting or crashing" do
    collector = collector()

    assert {:halt, 0} = Wardwright.CLI.run([], collector)

    output = collected(collector)
    assert output =~ "wardwright serve"
    assert output =~ "Print this help"
  end

  test "help advertises the service and authoring tools command" do
    collector = collector()

    assert {:halt, 0} = Wardwright.CLI.run(["--help"], collector)

    output = collected(collector)
    assert output =~ "Start the Wardwright HTTP service"
    assert output =~ "wardwright serve"
    assert output =~ "wardwright admin"
    assert output =~ "wardwright tools"
    assert output =~ "WARDWRIGHT_BIND"
  end

  test "serve command starts the application" do
    assert :start = Wardwright.CLI.run(["serve"], collector())
    assert :start = Wardwright.CLI.run(["start"], collector())
  end

  test "unknown commands print help and fail loudly" do
    collector = collector()

    assert {:halt, 2} = Wardwright.CLI.run(["not-a-command"], collector)

    assert collected(collector) =~ "wardwright serve"
  end

  test "admin command opens the workbench through the admin helper" do
    collector = collector()

    assert {:halt, 0} =
             Wardwright.CLI.run(["admin"], collector, fn path, write_fun ->
               write_fun.("admin path: #{path}")
               0
             end)

    assert collected(collector) =~ "admin path: /admin"
  end

  test "admin access command opens Model Management" do
    collector = collector()

    assert {:halt, 0} =
             Wardwright.CLI.run(["admin", "access"], collector, fn path, write_fun ->
               write_fun.("admin path: #{path}")
               0
             end)

    assert collected(collector) =~ "admin path: /admin?view=model_access"
  end

  test "admin helper opens configured port when service is running" do
    collector = collector()
    test_pid = self()

    assert 0 =
             Admin.open("/admin", collector,
               bind: "0.0.0.0:8797",
               running?: fn url ->
                 send(test_pid, {:admin_running_probe, url})
                 true
               end,
               open_fun: fn url ->
                 send(test_pid, {:admin_browser_open, url})
                 :ok
               end
             )

    assert_receive {:admin_running_probe, "http://127.0.0.1:8797/admin"}
    assert_receive {:admin_browser_open, "http://127.0.0.1:8797/admin"}
    assert collected(collector) =~ "Opened http://127.0.0.1:8797/admin"
  end

  test "admin helper starts the service before opening when port is not responding" do
    collector = collector()
    test_pid = self()

    assert 0 =
             Admin.open("/admin?view=model_access", collector,
               bind: "127.0.0.1:8798",
               running?: fn url ->
                 send(test_pid, {:admin_running_probe, url})
                 false
               end,
               start_fun: fn bind ->
                 send(test_pid, {:admin_start, bind})
                 :ok
               end,
               wait_fun: fn url ->
                 send(test_pid, {:admin_wait, url})
                 true
               end,
               open_fun: fn url ->
                 send(test_pid, {:admin_browser_open, url})
                 :ok
               end
             )

    assert_receive {:admin_running_probe, "http://127.0.0.1:8798/admin?view=model_access"}
    assert_receive {:admin_start, "127.0.0.1:8798"}
    assert_receive {:admin_wait, "http://127.0.0.1:8798/admin?view=model_access"}
    assert_receive {:admin_browser_open, "http://127.0.0.1:8798/admin?view=model_access"}

    output = collected(collector)
    assert output =~ "Starting Wardwright on http://127.0.0.1:8798"
    assert output =~ "Wardwright is ready"
    assert output =~ "Opened http://127.0.0.1:8798/admin?view=model_access"
  end

  test "tools command prints agent-usable MCP and API guidance" do
    collector = collector()

    assert {:halt, 0} = Wardwright.CLI.run(["tools"], collector)

    output = collected(collector)
    assert output =~ "http://127.0.0.1:8787/mcp"
    assert output =~ "WARDWRIGHT_ADMIN_TOKEN"
    assert output =~ "https://wardwright.dev/agent-authoring.html"
    assert output =~ "explain_projection"
    assert output =~ "GET /v1/policy-authoring/projections/{pattern_id}"
    assert output =~ "draft_wardwright_model"
    assert output =~ "POST /v1/policy-authoring/wardwright-models/draft"
    assert output =~ "list_dune_snippets"
    assert output =~ "evaluate_dune_snippet"
    assert output =~ "save_dune_snippet"
    assert output =~ "delete_dune_snippet"
    assert output =~ "activate_wardwright_model"
    assert output =~ "propose_rule_change"
    refute output =~ "not implemented"
    assert output =~ "validate_policy_artifact"
  end

  test "tools JSON is generated from the authoring tool registry" do
    collector = collector()

    assert {:halt, 0} = Wardwright.CLI.run(["tools", "--json"], collector)

    tools =
      collector
      |> collected()
      |> Jason.decode!()

    names =
      tools
      |> Enum.map(& &1["name"])

    assert "simulate_policy" in names
    assert "list_dune_snippets" in names
    assert "evaluate_dune_snippet" in names
    assert "save_dune_snippet" in names
    assert "delete_dune_snippet" in names
    assert "draft_wardwright_model" in names
    assert "activate_wardwright_model" in names
    assert "record_scenario" in names
    assert "delete_scenario" in names
    assert "propose_rule_change" in names
    assert "validate_policy_artifact" in names

    assert Enum.all?(tools, &is_binary(&1["docs_url"]))
    assert Enum.all?(tools, &is_binary(&1["when_to_use"]))
    assert Enum.all?(tools, &is_binary(&1["safety"]))
  end

  defp collector do
    owner = self()

    fn line ->
      send(owner, {:cli_output, line})
    end
  end

  defp collected(_collector) do
    collect_messages([])
  end

  defp collect_messages(lines) do
    receive do
      {:cli_output, line} -> collect_messages([line | lines])
    after
      0 -> lines |> Enum.reverse() |> Enum.join("\n")
    end
  end
end

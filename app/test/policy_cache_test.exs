defmodule Wardwright.PolicyCacheTest do
  use Wardwright.RouterCase
  use ExUnitProperties

  alias Wardwright.Runtime.Events

  property "policy cache eviction keeps deterministic youngest entries" do
    check all(
            capacity <- integer(1..20),
            timestamps <- list_of(integer(0..50), max_length: 80)
          ) do
      Wardwright.PolicyCache.configure(%{"max_entries" => capacity, "recent_limit" => capacity})

      inserted =
        Enum.map(timestamps, fn timestamp ->
          {:ok, event} =
            Wardwright.PolicyCache.add(%{
              "created_at_unix_ms" => timestamp,
              "key" => "shell:ls",
              "kind" => "tool_call",
              "scope" => %{"session_id" => "session-a"}
            })

          {event["sequence"], timestamp}
        end)

      expected =
        inserted
        |> Enum.sort_by(fn {sequence, timestamp} -> {timestamp, sequence} end)
        |> Enum.take(-capacity)
        |> MapSet.new(fn {sequence, _timestamp} -> sequence end)

      recent =
        Wardwright.PolicyCache.recent(
          %{
            "key" => "shell:ls",
            "kind" => "tool_call",
            "scope" => %{"session_id" => "session-a"}
          },
          capacity
        )

      assert length(recent) == MapSet.size(expected)
      assert Enum.all?(recent, &MapSet.member?(expected, &1["sequence"]))
    end
  end

  test "policy cache filters require matching kind and key together" do
    Wardwright.PolicyCache.configure(%{"max_entries" => 8, "recent_limit" => 8})

    for {kind, key} <- [
          {"tool_call", "shell:ls"},
          {"tool_call", "shell:rm"},
          {"response_text", "shell:ls"}
        ] do
      assert {:ok, _event} =
               Wardwright.PolicyCache.add(%{
                 "key" => key,
                 "kind" => kind,
                 "scope" => %{"session_id" => "session-a"}
               })
    end

    assert [%{"key" => "shell:ls", "kind" => "tool_call"}] =
             Wardwright.PolicyCache.recent(%{
               "key" => "shell:ls",
               "kind" => "tool_call",
               "scope" => %{"session_id" => "session-a"}
             })
  end

  test "policy cache is bounded ETS-backed runtime state and publishes writes" do
    Wardwright.PolicyCache.configure(%{"max_entries" => 2, "recent_limit" => 2})
    assert :ok = Events.subscribe(Events.topic(:policies))

    for index <- 1..3 do
      assert {:ok, %{"sequence" => ^index}} =
               Wardwright.PolicyCache.add(%{
                 "created_at_unix_ms" => index,
                 "key" => "shell:#{index}",
                 "kind" => "tool_call",
                 "scope" => %{"session_id" => "session-a"}
               })
    end

    assert_receive {:wardwright_runtime_event, "runtime:policies",
                    %{
                      "entry_count" => 1,
                      "max_entries" => 2,
                      "sequence" => 1,
                      "type" => "policy_cache.event_recorded"
                    }}

    assert %{
             "bounded" => true,
             "entry_count" => 2,
             "kind" => "ets_session_catalog_bounded_history",
             "max_entries" => 2,
             "session_count" => 1,
             "stores" => [
               %{"entry_count" => 2, "scope" => %{"session_id" => "session-a"}, "scope_key" => "session:session-a"}
             ],
             "topology" => "catalog_per_session_tables"
           } = Wardwright.PolicyCache.status()

    assert [%{"sequence" => 3}, %{"sequence" => 2}] = Wardwright.PolicyCache.recent(%{}, 10)
  end

  test "policy cache isolates per-session stores while preserving scoped reads" do
    Wardwright.PolicyCache.configure(%{"max_entries" => 2, "recent_limit" => 10})

    for {session_id, count} <- [{"session-a", 3}, {"session-b", 1}] do
      for index <- 1..count do
        assert {:ok, _event} =
                 Wardwright.PolicyCache.add(%{
                   "created_at_unix_ms" => index,
                   "key" => "shell:ls",
                   "kind" => "tool_call",
                   "scope" => %{"session_id" => session_id}
                 })
      end
    end

    assert %{"entry_count" => 3, "session_count" => 2, "stores" => stores} =
             Wardwright.PolicyCache.status()

    assert Enum.sort(Enum.map(stores, & &1["entry_count"])) == [1, 2]
    assert stores |> Enum.map(& &1["owner"]) |> Enum.uniq() |> length() == 2

    assert [
             %{"scope" => %{"session_id" => "session-a"}},
             %{"scope" => %{"session_id" => "session-a"}}
           ] =
             Wardwright.PolicyCache.recent(
               %{"kind" => "tool_call", "scope" => %{"session_id" => "session-a"}},
               10
             )

    assert [%{"scope" => %{"session_id" => "session-b"}}] =
             Wardwright.PolicyCache.recent(
               %{"kind" => "tool_call", "scope" => %{"session_id" => "session-b"}},
               10
             )

    cross_session = Wardwright.PolicyCache.recent(%{"kind" => "tool_call"}, 10)

    assert cross_session ==
             Enum.sort_by(
               cross_session,
               fn event -> {event["created_at_unix_ms"], event["sequence"], event["id"]} end,
               :desc
             )
  end
end

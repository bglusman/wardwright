defmodule WardwrightWeb.CounterfactualReplayPropertyTest do
  use Wardwright.RouterCase
  use ExUnitProperties

  @replay_module WardwrightWeb.CounterfactualReplay

  setup do
    store_dir = Path.join(System.tmp_dir!(), "wardwright-counterfactual-prop-#{System.unique_integer([:positive])}")
    previous_store_dir = Application.get_env(:wardwright, :counterfactual_transcript_store_dir)

    Application.put_env(:wardwright, :counterfactual_transcript_store_dir, store_dir)

    on_exit(fn ->
      File.rm_rf(store_dir)
      restore_env(:counterfactual_transcript_store_dir, previous_store_dir)
    end)

    :ok
  end

  property "replay_until returns the strict event prefix before the selected cursor" do
    check all({event_count, cursor_index} <- replay_shape(), max_runs: 40) do
      session_id = "prop_session_#{System.unique_integer([:positive])}"
      events = numbered_events(session_id, event_count)
      cursor = Enum.at(events, cursor_index - 1)["cursor"]

      write_events!(session_id, events)

      assert {:ok, replay} = @replay_module.replay_until(session_id, cursor)
      assert replay["events"] == Enum.take(events, cursor_index - 1)
      assert replay["next_event_cursor"] == cursor
      assert replay["provider_called"] == false
      assert replay["session_id"] == session_id
    end
  end

  property "replay_until rejects cursors outside the recorded event stream" do
    check all(event_count <- integer(1..12), max_runs: 40) do
      session_id = "prop_session_#{System.unique_integer([:positive])}"

      write_events!(session_id, numbered_events(session_id, event_count))

      assert {:error, message} = @replay_module.replay_until(session_id, "#{session_id}:missing")
      assert message =~ "unknown transcript cursor"
    end
  end

  property "adapter fidelity never claims equivalent resume while any hidden-state requirement is missing" do
    check all(
            native_session_import <- boolean(),
            native_session_resume <- boolean(),
            native_tool_results <- boolean(),
            workspace_snapshot <- boolean(),
            private_agent_state <- boolean(),
            max_runs: 40
          ) do
      equivalent =
        :wardwright@harness_adapter.can_claim_equivalent_agent_resume(
          native_session_import,
          native_session_resume,
          native_tool_results,
          workspace_snapshot,
          private_agent_state
        )

      assert equivalent ==
               (native_session_import and native_session_resume and native_tool_results and workspace_snapshot and
                  private_agent_state)
    end
  end

  defp replay_shape do
    bind(integer(2..12), fn event_count ->
      map(integer(1..event_count), fn cursor_index ->
        {event_count, cursor_index}
      end)
    end)
  end

  defp numbered_events(session_id, event_count) do
    Enum.map(1..event_count, fn sequence ->
      %{
        "cursor" => "#{session_id}:#{sequence}",
        "schema" => "wardwright.counterfactual_replay.v0",
        "sequence" => sequence,
        "session_id" => session_id,
        "type" => "event.#{sequence}"
      }
    end)
  end

  defp write_events!(session_id, events) do
    store_dir = Application.fetch_env!(:wardwright, :counterfactual_transcript_store_dir)
    session_dir = Path.join(store_dir, Base.url_encode64(session_id, padding: false))

    File.mkdir_p!(session_dir)
    File.write!(Path.join(session_dir, "events.jsonl"), Enum.map_join(events, "\n", &JSON.encode!/1) <> "\n")
  end

  defp restore_env(key, nil), do: Application.delete_env(:wardwright, key)
  defp restore_env(key, value), do: Application.put_env(:wardwright, key, value)
end

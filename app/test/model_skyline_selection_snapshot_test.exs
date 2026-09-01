defmodule Wardwright.ModelSkyline.SelectionSnapshotTest do
  use ExUnit.Case, async: true

  alias Wardwright.ModelSkyline.CanonicalJson
  alias Wardwright.ModelSkyline.SelectionSnapshot

  @fixture_a Path.expand("fixtures/model_skyline/selection-a.json", __DIR__)
  @fixture_b Path.expand("fixtures/model_skyline/selection-b.json", __DIR__)
  @expected %{
    "frontier_id" => "coding-value",
    "selection_id" => "coding-agent-defaults",
    "workload" => %{
      "id" => "coding-session",
      "unit" => "completed_session",
      "version" => "v1"
    }
  }
  @verification_time ~U[2026-08-31 12:30:00Z]
  @stable_snapshot_id "78014ee076a47e77026e6df594c47a6586dbd2f6d86987e3684334a4f9693567"
  @explicit_null_snapshot_id "3025988e63e2219675074eba55dd01fd89d13968e6fd1b012ee4f70174f478d5"

  test "verifies ModelSkyline golden bytes with UTF-16 object-key ordering" do
    assert {:ok, snapshot} = verify_fixture(@fixture_a)

    assert snapshot.snapshot_id == @stable_snapshot_id

    assert Enum.map(snapshot.choices, & &1.offering["offering_id"]) == [
             "openai/gpt-5.4@direct-us",
             "anthropic/claude-fable-5@direct-us"
           ]

    assert get_in(hd(snapshot.choices).metadata, ["😀"]) == 7
    assert get_in(hd(snapshot.choices).metadata, [""]) == 8
  end

  test "verifies a second ModelSkyline golden snapshot with reversed choices" do
    assert {:ok, snapshot} = verify_fixture(@fixture_b)

    assert snapshot.snapshot_id ==
             "e9b953a0e0f6076641b5b09b4ef66649f0ad192b382899f1c208aa34c7b4ca16"

    assert Enum.map(snapshot.choices, & &1.offering["offering_id"]) == [
             "anthropic/claude-fable-5@direct-us",
             "openai/gpt-5.4@direct-us"
           ]
  end

  test "accepts the producer contract's capability-count boundary" do
    document = @fixture_a |> File.read!() |> JSON.decode!()

    capabilities =
      1..128
      |> Enum.map(fn index -> "capability-#{String.pad_leading(Integer.to_string(index), 3, "0")}" end)
      |> Enum.sort()

    offering = document |> get_in(["default", "offering"]) |> Map.put("capabilities", capabilities)

    assert {:ok, normalized} = SelectionSnapshot.normalize_offering(offering)
    assert normalized["capabilities"] == capabilities

    assert {:error, :invalid_selection} =
             SelectionSnapshot.normalize_offering(Map.put(offering, "capabilities", capabilities ++ ["capability-129"]))
  end

  test "accepts the publisher's explicit-null billing compatibility hash" do
    raw =
      @fixture_a
      |> File.read!()
      |> String.replace(@stable_snapshot_id, @explicit_null_snapshot_id)

    assert {:ok, snapshot} =
             SelectionSnapshot.verify(raw, @expected, now: @verification_time)

    assert snapshot.snapshot_id == @explicit_null_snapshot_id
  end

  test "fails closed when hashed selection content is tampered without changing its digest" do
    raw = @fixture_a |> File.read!() |> String.replace(~s("value": "0.42"), ~s("value": "0.41"))

    assert {:error, :invalid_selection_digest} =
             SelectionSnapshot.verify(raw, @expected, now: @verification_time)
  end

  test "rejects null and non-string axis values in every routing choice" do
    null_default =
      @fixture_a
      |> File.read!()
      |> String.replace(~s("value": "0.42"), ~s("value": null))

    integer_fallback =
      @fixture_a
      |> File.read!()
      |> String.replace(~s("value": "0.55"), ~s("value": 55))

    assert {:error, :invalid_selection} =
             SelectionSnapshot.verify(null_default, @expected, now: @verification_time)

    assert {:error, :invalid_selection} =
             SelectionSnapshot.verify(integer_fallback, @expected, now: @verification_time)
  end

  test "rejects non-string digest fields without raising" do
    document = @fixture_a |> File.read!() |> JSON.decode!()

    for field <- ["snapshot_id", "policy_hash", "frontier_snapshot_id"] do
      raw = document |> Map.put(field, 1) |> JSON.encode!()

      assert {:error, :invalid_selection} =
               SelectionSnapshot.verify(raw, @expected, now: @verification_time)
    end
  end

  test "rejects duplicate JSON object names before building a map" do
    raw =
      @fixture_a
      |> File.read!()
      |> String.replace(~s("kind": "selection",), ~s("kind": "selection", "kind": "selection",))

    escaped_equivalent = ~S({"plain": 1, "\u0070lain": 2})

    assert {:error, :duplicate_object_name} =
             SelectionSnapshot.verify(raw, @expected, now: @verification_time)

    assert {:error, :duplicate_object_name} = CanonicalJson.decode(escaped_equivalent)
  end

  test "rejects floating-point and unsafe-integer JSON numbers" do
    float_raw =
      @fixture_a
      |> File.read!()
      |> String.replace(~s("label": "primary"), ~s("label": "primary", "fraction": 1.25))

    unsafe_integer_raw =
      @fixture_a
      |> File.read!()
      |> String.replace(
        ~s("label": "primary"),
        ~s("label": "primary", "unsafe": 9007199254740992)
      )

    assert {:error, :unsupported_json_number} =
             SelectionSnapshot.verify(float_raw, @expected, now: @verification_time)

    assert {:error, :unsupported_json_number} =
             SelectionSnapshot.verify(unsafe_integer_raw, @expected, now: @verification_time)
  end

  test "rejects excessive nesting and I-JSON noncharacters" do
    too_deep = String.duplicate("[", 65) <> "null" <> String.duplicate("]", 65)
    assert {:error, :json_too_deep} = CanonicalJson.decode(too_deep)

    noncharacter_raw =
      @fixture_a
      |> File.read!()
      |> String.replace(~s("label": "primary"), ~s("label": "primary", "bad": "\\uffff"))

    assert {:error, :unsupported_json_value} =
             SelectionSnapshot.verify(noncharacter_raw, @expected, now: @verification_time)
  end

  test "requires exact configured selection, frontier, and workload identities" do
    raw = File.read!(@fixture_a)

    assert {:error, :selection_id_mismatch} =
             SelectionSnapshot.verify(raw, Map.put(@expected, "selection_id", "other"), now: @verification_time)

    assert {:error, :frontier_id_mismatch} =
             SelectionSnapshot.verify(raw, Map.put(@expected, "frontier_id", "other"), now: @verification_time)

    assert {:error, :workload_mismatch} =
             SelectionSnapshot.verify(
               raw,
               put_in(@expected, ["workload", "version"], "v2"),
               now: @verification_time
             )
  end

  test "enforces generated-at and valid-until admission bounds" do
    raw = File.read!(@fixture_a)

    assert {:error, :future_selection} =
             SelectionSnapshot.verify(raw, @expected, now: ~U[2026-08-31 11:59:59Z])

    assert {:error, :expired_selection} =
             SelectionSnapshot.verify(raw, @expected, now: ~U[2026-08-31 13:00:00Z])
  end

  test "rejects unknown publisher fields rather than silently hashing a wider contract" do
    raw =
      @fixture_a
      |> File.read!()
      |> String.replace(~s("kind": "selection",), ~s("kind": "selection", "unexpected": true,))

    assert {:error, :invalid_selection} =
             SelectionSnapshot.verify(raw, @expected, now: @verification_time)
  end

  defp verify_fixture(path) do
    path
    |> File.read!()
    |> SelectionSnapshot.verify(@expected, now: @verification_time)
  end
end

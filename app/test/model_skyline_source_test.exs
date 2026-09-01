defmodule Wardwright.ModelSkyline.SourceTest do
  use ExUnit.Case, async: true

  alias Wardwright.ModelSkyline.Source

  @fixture Path.expand("fixtures/model_skyline/selection-a.json", __DIR__)

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "wardwright-model-skyline-source-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf(directory) end)
    %{directory: directory}
  end

  test "loads a bounded absolute regular file", %{directory: directory} do
    path = Path.join(directory, "selection.json")
    File.cp!(@fixture, path)

    assert {:ok, raw} = Source.load(path)
    assert raw == File.read!(@fixture)
  end

  test "rejects relative paths, directories, and a final path that is a symbolic link", %{
    directory: directory
  } do
    path = Path.join(directory, "selection.json")
    link = Path.join(directory, "selection-link.json")
    File.cp!(@fixture, path)
    File.ln_s!(path, link)

    assert {:error, :selection_source_invalid} = Source.load("selection.json")
    assert {:error, :selection_source_not_regular} = Source.load(directory)
    assert {:error, :selection_source_not_regular} = Source.load(link)
  end

  test "rejects a file that exceeds the configured bound without returning its path", %{
    directory: directory
  } do
    path = Path.join(directory, "too-large.json")
    File.write!(path, "12345")

    result = Source.load(path, max_bytes: 4)

    assert result == {:error, :selection_source_too_large}
    refute inspect(result) =~ directory
  end

  test "returns content-free errors for missing sources", %{directory: directory} do
    path = Path.join(directory, "missing.json")
    result = Source.load(path)

    assert result == {:error, :selection_source_unreadable}
    refute inspect(result) =~ path
  end
end

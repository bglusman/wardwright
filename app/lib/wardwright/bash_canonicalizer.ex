defmodule Wardwright.BashCanonicalizer do
  @moduledoc """
  Conservative Bash command canonicalization for agent tool calls.

  This module is intentionally narrow. It models approval friction cases where a
  command is semantically equivalent to allowlisted atomic commands but is shaped
  in a way a permission analyzer may not match. Unknown or dynamic shell behavior
  returns a repair instruction instead of being rewritten.
  """

  @repair "repair"
  @rewritten "rewritten"
  @unchanged "unchanged"

  @type result :: %{
          required("status") => String.t(),
          required("commands") => [String.t()],
          required("diagnostics") => [map()]
        }

  @doc """
  Canonicalizes a Bash command when equivalence is straightforward.

  Options:

    * `:cwd` - current working directory for path equivalence checks.
    * `:repo_root` - current repository root for redundant `git -C` removal.

  The return value is a map so it can be serialized directly into eval reports,
  receipts, or model-repair feedback.
  """
  @spec canonicalize(String.t(), keyword()) :: result()
  def canonicalize(command, opts \\ []) when is_binary(command) do
    command = String.trim(command)
    cwd = opts[:cwd]
    repo_root = opts[:repo_root]

    cond do
      command == "" ->
        result(@unchanged, [], [%{"kind" => "empty_command"}])

      dynamic_shell_variable?(command) ->
        result(@repair, [command], [
          %{
            "kind" => "dynamic_shell_expansion",
            "message" =>
              "Shell variable assignment and later expansion cannot be safely canonicalized; inline the expression or split into explicit commands."
          }
        ])

      true ->
        command
        |> split_top_level_commands()
        |> Enum.map(&canonicalize_simple_command(&1, cwd, repo_root))
        |> combine_results(command)
    end
  end

  def canonicalize(command, opts), do: canonicalize(to_string(command), opts)

  defp combine_results(parts, original_command) do
    commands = Enum.map(parts, & &1.command)
    diagnostics = Enum.flat_map(parts, & &1.diagnostics)

    cond do
      Enum.any?(parts, &(&1.status == @repair)) ->
        result(@repair, [original_command], diagnostics)

      commands != [original_command] ->
        result(@rewritten, commands, diagnostics)

      true ->
        result(@unchanged, commands, diagnostics)
    end
  end

  defp canonicalize_simple_command(command, cwd, repo_root) do
    case tokenize(command) do
      ["git", "-C", path | rest] when rest != [] ->
        canonicalize_git_c(command, path, rest, cwd, repo_root)

      ["git", "--git-dir" | _rest] ->
        %{
          command: command,
          status: @repair,
          diagnostics: [
            %{
              "kind" => "unsupported_git_context",
              "message" => "`git --git-dir` changes repository context and must be repaired by the model."
            }
          ]
        }

      _tokens ->
        %{command: command, status: @unchanged, diagnostics: []}
    end
  end

  defp canonicalize_git_c(original, path, rest, cwd, repo_root) do
    if equivalent_context_path?(path, cwd, repo_root) do
      %{
        command: Enum.join(["git" | rest], " "),
        status: @rewritten,
        diagnostics: [
          %{
            "kind" => "removed_redundant_git_c",
            "message" => "Removed redundant `git -C` because it targeted the active cwd or repo root."
          }
        ]
      }
    else
      %{
        command: original,
        status: @repair,
        diagnostics: [
          %{
            "kind" => "git_c_external_context",
            "message" =>
              "`git -C` targets a different path; rerun from that repo context or pass a trusted cwd outside the Bash command."
          }
        ]
      }
    end
  end

  defp equivalent_context_path?(_path, nil, nil), do: false

  defp equivalent_context_path?(path, cwd, repo_root) do
    expanded = expand_path(path, cwd)

    [cwd, repo_root]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Path.expand/1)
    |> Enum.any?(&(&1 == expanded))
  end

  defp expand_path(path, cwd) do
    if Path.type(path) == :absolute do
      Path.expand(path)
    else
      Path.expand(path, cwd || File.cwd!())
    end
  end

  defp dynamic_shell_variable?(command) do
    Regex.match?(~r/(^|[\s;])[_A-Za-z][_A-Za-z0-9]*=\$\(/, command) and
      Regex.match?(~r/(^|[^\$])\$[_A-Za-z][_A-Za-z0-9]*/, command)
  end

  defp split_top_level_commands(command) do
    command
    |> do_split_top_level([], [], :normal)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp do_split_top_level(<<>>, current, commands, _mode) do
    [current |> Enum.reverse() |> IO.iodata_to_binary() | commands]
    |> Enum.reverse()
  end

  defp do_split_top_level(<<"&&", rest::binary>>, current, commands, :normal) do
    command = current |> Enum.reverse() |> IO.iodata_to_binary()
    do_split_top_level(rest, [], [command | commands], :normal)
  end

  defp do_split_top_level(<<";", rest::binary>>, current, commands, :normal) do
    command = current |> Enum.reverse() |> IO.iodata_to_binary()
    do_split_top_level(rest, [], [command | commands], :normal)
  end

  defp do_split_top_level(<<"\\", char::binary-size(1), rest::binary>>, current, commands, mode) do
    do_split_top_level(rest, [char, "\\" | current], commands, mode)
  end

  defp do_split_top_level(<<"'", rest::binary>>, current, commands, :normal) do
    do_split_top_level(rest, ["'" | current], commands, :single_quote)
  end

  defp do_split_top_level(<<"'", rest::binary>>, current, commands, :single_quote) do
    do_split_top_level(rest, ["'" | current], commands, :normal)
  end

  defp do_split_top_level(<<"\"", rest::binary>>, current, commands, :normal) do
    do_split_top_level(rest, ["\"" | current], commands, :double_quote)
  end

  defp do_split_top_level(<<"\"", rest::binary>>, current, commands, :double_quote) do
    do_split_top_level(rest, ["\"" | current], commands, :normal)
  end

  defp do_split_top_level(<<char::binary-size(1), rest::binary>>, current, commands, mode) do
    do_split_top_level(rest, [char | current], commands, mode)
  end

  defp tokenize(command) do
    command
    |> do_tokenize([], [], :normal)
    |> Enum.reverse()
  end

  defp do_tokenize(<<>>, current, tokens, _mode), do: finish_token(current, tokens)

  defp do_tokenize(<<char::binary-size(1), rest::binary>>, current, tokens, :normal)
       when char in [" ", "\t", "\n"] do
    do_tokenize(rest, [], finish_token(current, tokens), :normal)
  end

  defp do_tokenize(<<"\\", char::binary-size(1), rest::binary>>, current, tokens, mode) do
    do_tokenize(rest, [char | current], tokens, mode)
  end

  defp do_tokenize(<<"'", rest::binary>>, current, tokens, :normal),
    do: do_tokenize(rest, current, tokens, :single_quote)

  defp do_tokenize(<<"'", rest::binary>>, current, tokens, :single_quote),
    do: do_tokenize(rest, current, tokens, :normal)

  defp do_tokenize(<<"\"", rest::binary>>, current, tokens, :normal),
    do: do_tokenize(rest, current, tokens, :double_quote)

  defp do_tokenize(<<"\"", rest::binary>>, current, tokens, :double_quote),
    do: do_tokenize(rest, current, tokens, :normal)

  defp do_tokenize(<<char::binary-size(1), rest::binary>>, current, tokens, mode) do
    do_tokenize(rest, [char | current], tokens, mode)
  end

  defp finish_token([], tokens), do: tokens
  defp finish_token(current, tokens), do: [current |> Enum.reverse() |> IO.iodata_to_binary() | tokens]

  defp result(status, commands, diagnostics) do
    %{
      "commands" => commands,
      "diagnostics" => diagnostics,
      "status" => status
    }
  end
end

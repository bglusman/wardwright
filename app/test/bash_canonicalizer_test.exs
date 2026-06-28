defmodule Wardwright.BashCanonicalizerTest do
  use ExUnit.Case, async: true

  alias Wardwright.BashCanonicalizer

  @repo "/workspace/example-repo"

  test "removes redundant git -C targeting the current repo root" do
    assert %{
             "commands" => ["git status --short"],
             "diagnostics" => [%{"kind" => "removed_redundant_git_c"}],
             "status" => "rewritten"
           } =
             BashCanonicalizer.canonicalize("git -C /workspace/example-repo status --short",
               cwd: @repo,
               repo_root: @repo
             )
  end

  test "removes redundant quoted git -C targeting the current cwd" do
    assert %{"commands" => ["git diff --stat"], "status" => "rewritten"} =
             BashCanonicalizer.canonicalize(~s(git -C "/workspace/example-repo" diff --stat),
               cwd: @repo
             )
  end

  test "splits top-level command chains after canonicalizing each safe command" do
    assert %{
             "commands" => ["git status --short", "git diff --stat"],
             "status" => "rewritten"
           } =
             BashCanonicalizer.canonicalize(
               "git -C /workspace/example-repo status --short && git -C /workspace/example-repo diff --stat",
               cwd: @repo,
               repo_root: @repo
             )
  end

  test "does not split separators inside quotes" do
    assert %{
             "commands" => [~s(printf 'ready && still one command')],
             "status" => "unchanged"
           } =
             BashCanonicalizer.canonicalize(~s(printf 'ready && still one command'), cwd: @repo)
  end

  test "asks for model repair when git -C targets a different repo context" do
    assert %{
             "commands" => ["git -C /workspace/other-repo status --short"],
             "diagnostics" => [%{"kind" => "git_c_external_context"}],
             "status" => "repair"
           } =
             BashCanonicalizer.canonicalize("git -C /workspace/other-repo status --short",
               cwd: @repo,
               repo_root: @repo
             )
  end

  test "asks for model repair for shell variable assignment and expansion" do
    assert %{
             "commands" => ["FILES=$(rg --files | head -5); wc -l $FILES"],
             "diagnostics" => [%{"kind" => "dynamic_shell_expansion"}],
             "status" => "repair"
           } =
             BashCanonicalizer.canonicalize("FILES=$(rg --files | head -5); wc -l $FILES",
               cwd: @repo
             )
  end
end

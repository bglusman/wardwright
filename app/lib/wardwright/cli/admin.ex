defmodule Wardwright.CLI.Admin do
  @moduledoc false

  @default_bind "127.0.0.1:8787"
  @probe_timeout_ms 180
  @startup_attempts 24
  @startup_sleep_ms 125

  def open(path, write_fun, opts \\ []) do
    bind = Keyword.get(opts, :bind, configured_bind())
    url = admin_url(bind, path)
    running? = Keyword.get(opts, :running?, &running?/1)
    start_fun = Keyword.get(opts, :start_fun, &start_server/1)
    wait_fun = Keyword.get(opts, :wait_fun, &wait_until_running/1)
    open_fun = Keyword.get(opts, :open_fun, &open_browser/1)

    case ensure_running(url, bind, running?, start_fun, wait_fun, write_fun) do
      :ok ->
        case open_fun.(url) do
          :ok ->
            write_fun.("Opened #{url}")
            0

          {:error, message} ->
            write_fun.("Open #{url}")
            write_fun.("Browser launch failed: #{message}")
            1
        end

      {:error, status} ->
        status
    end
  end

  defp ensure_running(url, bind, running?, start_fun, wait_fun, write_fun) do
    if running?.(url) do
      :ok
    else
      write_fun.("Starting Wardwright on #{base_url(url)}...")

      case start_fun.(bind) do
        :ok ->
          if wait_fun.(url) do
            write_fun.("Wardwright is ready at #{base_url(url)}.")
          else
            write_fun.("Wardwright was started, but did not respond yet at #{base_url(url)}.")
          end

          :ok

        {:error, message} ->
          write_fun.("Could not start Wardwright automatically: #{message}")
          write_fun.("Start it with `wardwright serve`, then open #{url}.")
          {:error, 2}
      end
    end
  end

  defp admin_url(bind, path) do
    base = bind |> String.trim() |> base_url()
    path = if String.starts_with?(path, "/"), do: path, else: "/#{path}"
    "#{base}#{path}"
  end

  defp base_url(raw) do
    uri =
      if String.contains?(raw, "://") do
        URI.parse(raw)
      else
        URI.parse("http://#{raw}")
      end

    scheme = uri.scheme || "http"
    host = browser_host(uri.host || @default_bind)
    port = uri.port || 8787
    "#{scheme}://#{host}:#{port}"
  end

  defp browser_host("0.0.0.0"), do: "127.0.0.1"
  defp browser_host("::"), do: "localhost"
  defp browser_host(host), do: host

  defp running?(url) do
    uri = URI.parse(url)
    host = uri.host |> browser_host() |> String.to_charlist()
    port = uri.port || 80

    case :gen_tcp.connect(host, port, [:binary, active: false], @probe_timeout_ms) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _reason} ->
        false
    end
  end

  defp wait_until_running(url) do
    Enum.reduce_while(1..@startup_attempts, false, fn _attempt, _ready? ->
      if running?(url) do
        {:halt, true}
      else
        Process.sleep(@startup_sleep_ms)
        {:cont, false}
      end
    end)
  end

  defp start_server(bind) do
    with {:ok, command} <- server_command(),
         {:ok, secret} <- secret_key_base() do
      case System.cmd("sh", ["-c", "#{command} >/dev/null 2>&1 &"],
             env: [{"WARDWRIGHT_BIND", bind}, {"WARDWRIGHT_SECRET_KEY_BASE", secret}],
             stderr_to_stdout: true
           ) do
        {_output, 0} ->
          :ok

        {output, status} ->
          {:error, "background command exited #{status}: #{String.trim(output)}"}
      end
    end
  end

  defp configured_bind do
    System.get_env("WARDWRIGHT_BIND")
    |> blank_to_nil()
    |> case do
      nil -> persisted_bind() || @default_bind
      bind -> bind
    end
  end

  defp persisted_bind do
    [
      "/opt/homebrew/etc/wardwright/bind",
      "/usr/local/etc/wardwright/bind"
    ]
    |> Enum.find_value(fn path ->
      with {:ok, value} <- File.read(path) do
        blank_to_nil(value)
      else
        _ -> nil
      end
    end)
  end

  defp server_command do
    cond do
      configured = System.get_env("WARDWRIGHT_ADMIN_SERVER_COMMAND") ->
        {:ok, configured}

      executable = System.find_executable("wardwright") ->
        {:ok, "#{shell_quote(executable)} serve"}

      true ->
        {:error, "could not find a `wardwright` executable on PATH"}
    end
  end

  defp secret_key_base do
    System.get_env("WARDWRIGHT_SECRET_KEY_BASE")
    |> blank_to_nil()
    |> case do
      nil -> persisted_secret_key_base()
      secret -> {:ok, secret}
    end
  end

  defp persisted_secret_key_base do
    homebrew_secret_paths()
    |> Enum.find_value(&read_secret/1)
    |> case do
      nil -> local_secret_key_base()
      secret -> {:ok, secret}
    end
  end

  defp homebrew_secret_paths do
    [
      "/opt/homebrew/etc/wardwright/secret_key_base",
      "/usr/local/etc/wardwright/secret_key_base"
    ]
  end

  defp read_secret(path) do
    with {:ok, value} <- File.read(path),
         secret when is_binary(secret) <- blank_to_nil(String.trim(value)) do
      secret
    else
      _ -> nil
    end
  end

  defp local_secret_key_base do
    path = Path.join([System.user_home!(), ".wardwright", "secret_key_base"])

    case read_secret(path) do
      nil ->
        secret = Base.encode64(:crypto.strong_rand_bytes(64))

        with :ok <- File.mkdir_p(Path.dirname(path)),
             :ok <- File.write(path, secret <> "\n"),
             :ok <- File.chmod(path, 0o600) do
          {:ok, secret}
        else
          {:error, reason} -> {:error, "could not create #{path}: #{inspect(reason)}"}
        end

      secret ->
        {:ok, secret}
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp blank_to_nil(_value), do: nil

  defp shell_quote(value) do
    "'#{String.replace(value, "'", "'\"'\"'")}'"
  end

  defp open_browser(url) do
    with {:ok, executable, args} <- browser_command(url) do
      case System.cmd(executable, args, stderr_to_stdout: true) do
        {_output, 0} -> :ok
        {output, status} -> {:error, "#{executable} exited #{status}: #{String.trim(output)}"}
      end
    end
  end

  defp browser_command(url) do
    case :os.type() do
      {:unix, :darwin} ->
        {:ok, "open", [url]}

      _ ->
        case System.find_executable("xdg-open") do
          nil -> {:error, "no browser opener found; install xdg-open or open the URL manually"}
          executable -> {:ok, executable, [url]}
        end
    end
  end
end

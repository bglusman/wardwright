defmodule Wardwright.SQLiteStore do
  @moduledoc false

  alias Exqlite.Sqlite3

  @schema_version 2

  def enabled?, do: not is_nil(store_path())

  def store_path do
    case Application.get_env(:wardwright, :sqlite_store_path, :default) do
      nil -> nil
      :default -> System.get_env("WARDWRIGHT_SQLITE_STORE") || default_store_path()
      path -> path
    end
  end

  def load_active_model do
    case list_active_models() do
      {:ok, [config | _]} -> {:ok, config}
      _ -> :error
    end
  end

  def list_active_models do
    with {:ok, result} <-
           with_conn(fn conn ->
             query_all(
               conn,
               """
               SELECT config_json
               FROM wardwright_models
               WHERE active = 1
               ORDER BY model_id ASC
               """,
               []
             )
           end),
         configs when is_list(configs) <- result do
      {:ok,
       configs
       |> Enum.flat_map(fn
         [config_json] ->
           case Jason.decode(config_json) do
             {:ok, config} -> [Wardwright.normalize_config(config)]
             _ -> []
           end

         _ ->
           []
       end)}
    else
      _ -> {:ok, []}
    end
  end

  def save_model_config(config, opts \\ []) when is_map(config) do
    config = Wardwright.normalize_config(config)
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    replace_active? = Keyword.get(opts, :replace_active, false)

    with_conn(fn conn ->
      transaction!(conn, fn ->
        if replace_active? do
          execute!(conn, "UPDATE wardwright_models SET active = 0")
        end

        exec!(
          conn,
          """
          INSERT INTO wardwright_models (model_id, config_json, active, created_at, updated_at)
          VALUES (?, ?, 1, ?, ?)
          ON CONFLICT(model_id) DO UPDATE SET
            config_json = excluded.config_json,
            active = 1,
            updated_at = excluded.updated_at
          """,
          [config["model_id"], Jason.encode!(config), now, now]
        )
      end)
    end)
  end

  def list_api_keys(model_id \\ nil) do
    with_conn(fn conn ->
      {sql, params} =
        if model_id do
          {
            """
            SELECT id, model_id, label, prefix, key_hash, created_at
            FROM model_api_keys
            WHERE model_id = ?
            ORDER BY created_at DESC
            """,
            [model_id]
          }
        else
          {
            """
            SELECT id, model_id, label, prefix, key_hash, created_at
            FROM model_api_keys
            ORDER BY created_at DESC
            """,
            []
          }
        end

      query_all(conn, sql, params)
      |> Enum.map(&key_record/1)
    end)
  end

  def insert_api_key(record) do
    with_conn(fn conn ->
      exec!(
        conn,
        """
        INSERT INTO model_api_keys (id, model_id, label, prefix, key_hash, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        [
          record["id"],
          record["model_id"],
          record["label"],
          record["prefix"],
          record["key_hash"],
          record["created_at"]
        ]
      )
    end)
  end

  def delete_api_key(id) do
    with_conn(fn conn ->
      exec!(conn, "DELETE FROM model_api_keys WHERE id = ?", [id])
      Sqlite3.changes(conn)
    end)
  end

  def clear_api_keys do
    with_conn(fn conn ->
      execute!(conn, "DELETE FROM model_api_keys")
    end)
  end

  def list_receipts do
    with_conn(fn conn ->
      query_all(
        conn,
        """
        SELECT receipt_json
        FROM receipts
        ORDER BY created_at DESC, receipt_id DESC
        """,
        []
      )
      |> Enum.flat_map(&decode_receipt_row/1)
    end)
  end

  def get_receipt(receipt_id) do
    with_conn(fn conn ->
      case query_one(conn, "SELECT receipt_json FROM receipts WHERE receipt_id = ?", [receipt_id]) do
        {:row, [receipt_json]} -> decode_receipt(receipt_json)
        _other -> nil
      end
    end)
  end

  def insert_receipt(receipt) when is_map(receipt) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    with_conn(fn conn ->
      exec!(
        conn,
        """
        INSERT INTO receipts (
          receipt_id,
          receipt_json,
          created_at,
          model_id,
          model_version,
          run_id,
          selected_model,
          selected_provider,
          session_id,
          simulation,
          status,
          updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(receipt_id) DO UPDATE SET
          receipt_json = excluded.receipt_json,
          created_at = excluded.created_at,
          model_id = excluded.model_id,
          model_version = excluded.model_version,
          run_id = excluded.run_id,
          selected_model = excluded.selected_model,
          selected_provider = excluded.selected_provider,
          session_id = excluded.session_id,
          simulation = excluded.simulation,
          status = excluded.status,
          updated_at = excluded.updated_at
        """,
        [
          receipt["receipt_id"],
          Jason.encode!(receipt),
          receipt["created_at"],
          receipt["model_id"],
          receipt["model_version"],
          sourced_value(receipt, ["caller", "run_id"]) || receipt["run_id"],
          get_in(receipt, ["decision", "selected_model"]),
          selected_provider(receipt),
          sourced_value(receipt, ["caller", "session_id"]),
          if(receipt["simulation"] || false, do: 1, else: 0),
          get_in(receipt, ["final", "status"]),
          now
        ]
      )
    end)
  end

  def clear_receipts do
    with_conn(fn conn ->
      execute!(conn, "DELETE FROM receipts")
    end)
  end

  defp with_conn(fun) do
    case store_path() do
      nil ->
        {:error, :disabled}

      path ->
        File.mkdir_p!(Path.dirname(path))

        with {:ok, conn} <- Sqlite3.open(path) do
          try do
            unlock!(conn)
            migrate!(conn)
            {:ok, fun.(conn)}
          after
            Sqlite3.close(conn)
            secure_store_files(path)
          end
        end
    end
  end

  defp migrate!(conn) do
    execute!(conn, "PRAGMA journal_mode = WAL")
    execute!(conn, "PRAGMA foreign_keys = ON")

    execute!(conn, """
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version INTEGER PRIMARY KEY,
      applied_at TEXT NOT NULL
    )
    """)

    execute!(conn, """
    CREATE TABLE IF NOT EXISTS wardwright_models (
      model_id TEXT PRIMARY KEY,
      config_json TEXT NOT NULL,
      active INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """)

    execute!(conn, """
    CREATE TABLE IF NOT EXISTS model_api_keys (
      id TEXT PRIMARY KEY,
      model_id TEXT NOT NULL,
      label TEXT NOT NULL,
      prefix TEXT NOT NULL,
      key_hash TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
    """)

    execute!(conn, """
    CREATE TABLE IF NOT EXISTS receipts (
      receipt_id TEXT PRIMARY KEY,
      receipt_json TEXT NOT NULL,
      created_at TEXT,
      model_id TEXT,
      model_version TEXT,
      run_id TEXT,
      selected_model TEXT,
      selected_provider TEXT,
      session_id TEXT,
      simulation INTEGER NOT NULL DEFAULT 0,
      status TEXT,
      updated_at TEXT NOT NULL
    )
    """)

    execute!(conn, "CREATE INDEX IF NOT EXISTS receipts_created_at_idx ON receipts (created_at DESC, receipt_id DESC)")
    execute!(conn, "CREATE INDEX IF NOT EXISTS receipts_session_id_idx ON receipts (session_id)")
    execute!(conn, "CREATE INDEX IF NOT EXISTS receipts_model_id_idx ON receipts (model_id)")
    execute!(conn, "CREATE INDEX IF NOT EXISTS receipts_status_idx ON receipts (status)")

    exec!(
      conn,
      "INSERT OR IGNORE INTO schema_migrations (version, applied_at) VALUES (?, ?)",
      [@schema_version, DateTime.utc_now() |> DateTime.to_iso8601()]
    )
  end

  defp unlock!(conn) do
    case encryption_key() do
      nil ->
        :ok

      key ->
        execute!(conn, "PRAGMA key = #{quote_pragma_string(key)}")
        require_encryption_capable!(conn)
    end
  end

  defp require_encryption_capable!(conn) do
    case query_one(conn, "PRAGMA cipher_version") do
      {:row, [version]} when is_binary(version) and version != "" ->
        :ok

      _other ->
        raise """
        WARDWRIGHT_SQLITE_KEY or WARDWRIGHT_SQLITE_KEY_FNOX was set, but this exqlite build \
        does not expose SQLCipher. Rebuild exqlite against SQLCipher or unset the SQLite key.
        """
    end
  end

  defp encryption_key do
    Application.get_env(:wardwright, :sqlite_key)
    |> fallback_to_env("WARDWRIGHT_SQLITE_KEY")
    |> fallback_to_fnox()
    |> blank_to_nil()
  end

  defp fallback_to_env(nil, env), do: System.get_env(env)
  defp fallback_to_env(value, _env), do: value

  defp fallback_to_fnox(nil) do
    System.get_env("WARDWRIGHT_SQLITE_KEY_FNOX")
    |> blank_to_nil()
    |> case do
      nil ->
        nil

      key ->
        case System.cmd("fnox", ["get", key], stderr_to_stdout: false) do
          {value, 0} -> value
          {_output, _status} -> nil
        end
    end
  end

  defp fallback_to_fnox(value), do: value

  defp quote_pragma_string(value) do
    "'#{value |> to_string() |> String.replace("'", "''")}'"
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp transaction!(conn, fun) do
    execute!(conn, "BEGIN IMMEDIATE")

    try do
      result = fun.()
      execute!(conn, "COMMIT")
      result
    rescue
      exception ->
        execute!(conn, "ROLLBACK")
        reraise exception, __STACKTRACE__
    end
  end

  defp execute!(conn, sql) do
    case Sqlite3.execute(conn, sql) do
      :ok -> :ok
      {:error, reason} -> raise "sqlite execute failed: #{inspect(reason)}"
    end
  end

  defp exec!(conn, sql, params) do
    case Sqlite3.prepare(conn, sql) do
      {:ok, statement} ->
        try do
          :ok = Sqlite3.bind(statement, params)

          case Sqlite3.step(conn, statement) do
            :done -> :ok
            {:row, _row} -> :ok
            {:error, reason} -> raise "sqlite statement failed: #{inspect(reason)}"
          end
        after
          Sqlite3.release(conn, statement)
        end

      {:error, reason} ->
        raise "sqlite prepare failed: #{inspect(reason)}"
    end
  end

  defp query_one(conn, sql, params \\ []) do
    case Sqlite3.prepare(conn, sql) do
      {:ok, statement} ->
        try do
          :ok = Sqlite3.bind(statement, params)
          Sqlite3.step(conn, statement)
        after
          Sqlite3.release(conn, statement)
        end

      {:error, reason} ->
        raise "sqlite prepare failed: #{inspect(reason)}"
    end
  end

  defp query_all(conn, sql, params) do
    case Sqlite3.prepare(conn, sql) do
      {:ok, statement} ->
        try do
          :ok = Sqlite3.bind(statement, params)

          case Sqlite3.fetch_all(conn, statement) do
            {:ok, rows} -> rows
            {:error, reason} -> raise "sqlite query failed: #{inspect(reason)}"
          end
        after
          Sqlite3.release(conn, statement)
        end

      {:error, reason} ->
        raise "sqlite prepare failed: #{inspect(reason)}"
    end
  end

  defp key_record([id, model_id, label, prefix, key_hash, created_at]) do
    %{
      "created_at" => created_at,
      "id" => id,
      "key_hash" => key_hash,
      "label" => label,
      "model_id" => model_id,
      "prefix" => prefix
    }
  end

  defp decode_receipt_row([receipt_json]), do: List.wrap(decode_receipt(receipt_json))
  defp decode_receipt_row(_row), do: []

  defp decode_receipt(receipt_json) when is_binary(receipt_json) do
    case Jason.decode(receipt_json) do
      {:ok, receipt} when is_map(receipt) -> receipt
      _other -> nil
    end
  end

  defp decode_receipt(_receipt_json), do: nil

  defp sourced_value(receipt, path) do
    receipt
    |> get_in(path)
    |> case do
      %{"value" => value} -> value
      _ -> nil
    end
  end

  defp selected_provider(receipt) do
    get_in(receipt, ["decision", "selected_provider"]) ||
      get_in(receipt, ["decision", "selected_model"]) |> provider_from_model()
  end

  defp provider_from_model(model) when is_binary(model) do
    model |> String.split("/", parts: 2) |> List.first()
  end

  defp provider_from_model(_model), do: nil

  defp default_store_path do
    Wardwright.Paths.data_path("wardwright.sqlite3")
  end

  defp secure_store_files(path) when is_binary(path) do
    [path, "#{path}-wal", "#{path}-shm"]
    |> Enum.each(fn store_file ->
      if File.exists?(store_file) do
        File.chmod(store_file, 0o600)
      end
    end)
  end
end

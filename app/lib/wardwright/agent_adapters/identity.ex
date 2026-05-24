defmodule Wardwright.AgentAdapters.Identity do
  @moduledoc false

  @schema "wardwright.adapter_identity.v0"
  @default_ttl_seconds 86_400
  @key_adapter_id "adapter_id"
  @key_adapter_version "adapter_version"
  @key_expires_at "expires_at"
  @key_gateway_url "gateway_url"
  @key_issued_at "issued_at"
  @key_runtime "runtime"
  @key_schema "schema"
  @key_target "target"
  @key_token "token"
  @key_workspace_fingerprint "workspace_fingerprint"
  @token_fields [
    @key_schema,
    @key_adapter_id,
    @key_adapter_version,
    @key_target,
    @key_runtime,
    @key_workspace_fingerprint,
    @key_gateway_url,
    @key_issued_at,
    @key_expires_at
  ]

  def issue(attrs, opts \\ []) when is_map(attrs) do
    with {:ok, secret} <- signing_secret(opts),
         {:ok, claims} <- claims(attrs, opts) do
      payload = JSON.encode!(claims)
      payload_segment = Base.url_encode64(payload, padding: false)
      signature_segment = signature_segment(payload_segment, secret)
      token = Enum.join([payload_segment, signature_segment], ".")

      {:ok, Map.put(claims, @key_token, token)}
    end
  end

  def validate(identity, opts \\ [])

  def validate(identity, opts) when is_map(identity) do
    with {:ok, secret} <- signing_secret(opts),
         {:ok, token} <- string_field(identity, @key_token),
         {:ok, claims} <- verify_token(token, secret),
         :ok <- require_identity_matches_token(identity, claims),
         :ok <- require_expected(claims, @key_adapter_id, Keyword.get(opts, :adapter_id)),
         :ok <- require_expected(claims, @key_target, Keyword.get(opts, :target)),
         :ok <- require_expected(claims, @key_runtime, Keyword.get(opts, :runtime)),
         :ok <- require_workspace(claims, opts),
         :ok <- require_unexpired(claims, Keyword.get(opts, :now, DateTime.utc_now())) do
      {:ok, claims}
    end
  end

  def validate(_identity, _opts), do: {:error, :malformed}

  def workspace_fingerprint(workspace_root) when is_binary(workspace_root) do
    workspace_root
    |> Path.expand()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp claims(attrs, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    ttl_seconds = Keyword.get(opts, :ttl_seconds, @default_ttl_seconds)
    expires_at = DateTime.add(now, ttl_seconds, :second)

    with {:ok, adapter_id} <- string_field(attrs, @key_adapter_id),
         {:ok, adapter_version} <- string_field(attrs, @key_adapter_version),
         {:ok, target} <- string_field(attrs, @key_target),
         {:ok, runtime} <- string_field(attrs, @key_runtime),
         {:ok, gateway_url} <- string_field(attrs, @key_gateway_url),
         {:ok, workspace_fingerprint} <- workspace_fingerprint_field(attrs, opts) do
      {:ok,
       Map.new([
         {@key_adapter_id, adapter_id},
         {@key_adapter_version, adapter_version},
         {@key_expires_at, DateTime.to_iso8601(expires_at)},
         {@key_gateway_url, gateway_url},
         {@key_issued_at, DateTime.to_iso8601(now)},
         {@key_runtime, runtime},
         {@key_schema, @schema},
         {@key_target, target},
         {@key_workspace_fingerprint, workspace_fingerprint}
       ])}
    end
  end

  defp workspace_fingerprint_field(attrs, opts) do
    case Map.get(attrs, @key_workspace_fingerprint) do
      value when is_binary(value) and value != "" ->
        {:ok, value}

      _value ->
        case Keyword.get(opts, :workspace_root) do
          value when is_binary(value) -> {:ok, workspace_fingerprint(value)}
          _value -> {:error, :malformed}
        end
    end
  end

  defp verify_token(token, secret) do
    case String.split(token, ".", parts: 2) do
      [payload_segment, signature] ->
        expected_signature = signature_segment(payload_segment, secret)

        with true <- Plug.Crypto.secure_compare(signature, expected_signature),
             {:ok, payload} <- Base.url_decode64(payload_segment, padding: false),
             {:ok, claims} <- JSON.decode(payload),
             true <- is_map(claims),
             true <- Map.get(claims, @key_schema) == @schema do
          {:ok, claims}
        else
          false -> {:error, :invalid_signature}
          _value -> {:error, :malformed}
        end

      _parts ->
        {:error, :malformed}
    end
  end

  defp require_identity_matches_token(identity, claims) do
    if Enum.all?(@token_fields, &(Map.get(identity, &1) == Map.get(claims, &1))) do
      :ok
    else
      {:error, :malformed}
    end
  end

  defp require_expected(_claims, _key, nil), do: :ok

  defp require_expected(claims, key, expected) do
    if Map.get(claims, key) == expected do
      :ok
    else
      {:error, :malformed}
    end
  end

  defp require_workspace(claims, opts) do
    expected =
      Keyword.get(opts, :workspace_fingerprint) ||
        case Keyword.get(opts, :workspace_root) do
          value when is_binary(value) -> workspace_fingerprint(value)
          _value -> nil
        end

    if is_nil(expected) or Map.get(claims, @key_workspace_fingerprint) == expected do
      :ok
    else
      {:error, :wrong_workspace}
    end
  end

  defp require_unexpired(claims, now) do
    with {:ok, expires_at, _offset} <- DateTime.from_iso8601(Map.get(claims, @key_expires_at, "")),
         :gt <- DateTime.compare(expires_at, now) do
      :ok
    else
      :lt -> {:error, :expired}
      :eq -> {:error, :expired}
      {:error, _reason} -> {:error, :malformed}
    end
  end

  defp string_field(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, :malformed}
          trimmed -> {:ok, trimmed}
        end

      _value ->
        {:error, :malformed}
    end
  end

  defp signature_segment(payload_segment, secret) do
    :crypto.mac(:hmac, :sha256, secret, payload_segment)
    |> Base.url_encode64(padding: false)
  end

  defp signing_secret(opts) do
    secret =
      Keyword.get(opts, :secret) ||
        Application.get_env(:wardwright, :adapter_identity_secret) ||
        System.get_env("WARDWRIGHT_ADAPTER_IDENTITY_SECRET")

    case secret do
      value when is_binary(value) and byte_size(value) >= 16 -> {:ok, value}
      _value -> {:error, :missing_secret}
    end
  end
end

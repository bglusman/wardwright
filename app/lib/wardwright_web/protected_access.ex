defmodule WardwrightWeb.ProtectedAccess do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    cond do
      authorized?(conn) -> mark_authorized(conn)
      basic_auth_configured?() -> basic_auth_challenge(conn)
      true -> forbidden(conn)
    end
  end

  def authorized?(conn, opts \\ []) do
    authorized_peer_and_headers?(conn.remote_ip, conn.req_headers, opts)
  end

  def authorized_peer_and_headers?(peer_ip, headers, opts \\ []) do
    case basic_auth_password() do
      nil ->
        local_ip?(peer_ip) or admin_token_valid?(headers) or
          (Keyword.get(opts, :allow_prototype, false) and
             Application.get_env(:wardwright, :allow_prototype_access, false))

      password ->
        admin_token_valid?(headers) or basic_auth_valid?(headers, password)
    end
  end

  def authorized_session?(session) when is_map(session) do
    Map.get(session, "wardwright_protected_access") == true
  end

  def authorized_session?(_session), do: false

  def basic_auth_configured?, do: is_binary(basic_auth_password())

  defp local_ip?(peer_ip), do: peer_ip in [{127, 0, 0, 1}, {0, 0, 0, 0, 0, 0, 0, 1}]

  defp mark_authorized(%{private: private} = conn) do
    if Map.has_key?(private, :plug_session) do
      put_session(conn, :wardwright_protected_access, true)
    else
      conn
    end
  end

  defp forbidden(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      403,
      JSON.encode!(%{
        error: %{
          code: "protected_endpoint",
          message: "protected endpoint requires localhost or admin token",
          type: "forbidden"
        }
      })
    )
    |> halt()
  end

  defp basic_auth_valid?(headers, password) do
    case basic_credentials(headers) do
      {:ok, "admin", request_password} -> Plug.Crypto.secure_compare(password, request_password)
      _ -> false
    end
  rescue
    _error -> false
  end

  defp basic_credentials(headers) do
    headers
    |> header_values("authorization")
    |> List.first()
    |> case do
      "Basic " <> encoded -> decode_basic_credentials(encoded)
      _ -> :error
    end
  end

  defp decode_basic_credentials(encoded) do
    with {:ok, decoded} <- Base.decode64(encoded),
         [username, password] <- String.split(decoded, ":", parts: 2) do
      {:ok, username, password}
    else
      _ -> :error
    end
  end

  defp basic_auth_challenge(conn) do
    conn
    |> put_resp_header("www-authenticate", ~s(Basic realm="Wardwright", charset="UTF-8"))
    |> put_resp_content_type("text/plain")
    |> send_resp(401, "Wardwright requires basic authentication")
    |> halt()
  end

  defp admin_token_valid?(headers) do
    case {admin_token(), request_admin_token(headers)} do
      {token, request_token} when is_binary(token) and is_binary(request_token) ->
        Plug.Crypto.secure_compare(token, request_token)

      {_token, _request_token} ->
        false
    end
  rescue
    _error -> false
  end

  defp admin_token do
    Application.get_env(:wardwright, :admin_token)
    |> fallback_to_env()
    |> metadata_string()
    |> blank_to_nil()
  end

  defp fallback_to_env(nil), do: System.get_env("WARDWRIGHT_ADMIN_TOKEN")
  defp fallback_to_env(value), do: value

  defp basic_auth_password do
    Application.get_env(:wardwright, :basic_auth_password)
    |> fallback_to_basic_auth_env()
    |> metadata_string()
    |> blank_to_nil()
  end

  defp fallback_to_basic_auth_env(nil), do: System.get_env("BASIC_AUTH_PASSWORD")
  defp fallback_to_basic_auth_env(value), do: value

  defp request_admin_token(headers) do
    headers
    |> header_values("authorization")
    |> List.first()
    |> bearer_token()
    |> case do
      nil ->
        headers
        |> header_values("x-wardwright-admin-token")
        |> List.first()
        |> metadata_string()
        |> blank_to_nil()

      token ->
        token
    end
  end

  defp bearer_token("Bearer " <> token), do: token |> metadata_string() |> blank_to_nil()
  defp bearer_token(_value), do: nil

  defp header_values(headers, key) do
    normalized_key = String.downcase(key)

    headers
    |> normalize_headers()
    |> Enum.filter(fn {header_key, _value} ->
      header_key |> to_string() |> String.downcase() == normalized_key
    end)
    |> Enum.map(fn {_header_key, value} -> metadata_string(value) end)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_headers(headers) when is_list(headers), do: headers
  defp normalize_headers(headers) when is_map(headers), do: Map.to_list(headers)
  defp normalize_headers(_headers), do: []

  defp metadata_string(nil), do: nil
  defp metadata_string(value) when is_binary(value), do: String.trim(value)
  defp metadata_string(value) when is_atom(value), do: value |> Atom.to_string() |> String.trim()

  defp metadata_string(value) when is_integer(value), do: value |> Integer.to_string() |> String.trim()

  defp metadata_string(_value), do: nil

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end

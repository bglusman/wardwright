defmodule WardwrightWeb.ProtectedAccess do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    cond do
      authorized?(conn) -> conn
      basic_auth_configured?() -> basic_auth_challenge(conn)
      true -> forbidden(conn)
    end
  end

  def authorized?(conn, opts \\ []) do
    case basic_auth_password() do
      nil ->
        local_request?(conn) or admin_token_valid?(conn) or
          (Keyword.get(opts, :allow_prototype, false) and
             Application.get_env(:wardwright, :allow_prototype_access, false))

      password ->
        admin_token_valid?(conn) or basic_auth_valid?(conn, password)
    end
  end

  def basic_auth_configured?, do: is_binary(basic_auth_password())

  defp local_request?(conn), do: conn.remote_ip in [{127, 0, 0, 1}, {0, 0, 0, 0, 0, 0, 0, 1}]

  defp forbidden(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      403,
      Jason.encode!(%{
        error: %{
          code: "protected_endpoint",
          message: "protected endpoint requires localhost or admin token",
          type: "forbidden"
        }
      })
    )
    |> halt()
  end

  defp basic_auth_valid?(conn, password) do
    case basic_credentials(conn) do
      {:ok, "admin", request_password} -> Plug.Crypto.secure_compare(password, request_password)
      _ -> false
    end
  rescue
    _error -> false
  end

  defp basic_credentials(conn) do
    conn
    |> get_req_header("authorization")
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

  defp admin_token_valid?(conn) do
    case {admin_token(), request_admin_token(conn)} do
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

  defp request_admin_token(conn) do
    conn
    |> get_req_header("authorization")
    |> List.first()
    |> bearer_token()
    |> case do
      nil ->
        conn
        |> get_req_header("x-wardwright-admin-token")
        |> List.first()
        |> metadata_string()
        |> blank_to_nil()

      token ->
        token
    end
  end

  defp bearer_token("Bearer " <> token), do: token |> metadata_string() |> blank_to_nil()
  defp bearer_token(_value), do: nil

  defp metadata_string(nil), do: nil
  defp metadata_string(value) when is_binary(value), do: String.trim(value)
  defp metadata_string(value) when is_atom(value), do: value |> Atom.to_string() |> String.trim()

  defp metadata_string(value) when is_integer(value), do: value |> Integer.to_string() |> String.trim()

  defp metadata_string(_value), do: nil

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end

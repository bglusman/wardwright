defmodule Wardwright.AgentAdapters.GatewayPairing do
  @moduledoc false

  @key_error "error"
  @key_identity "identity"
  @key_message "message"

  def request(gateway_url, gateway_token, payload, opts \\ []) do
    request_fun = Keyword.get(opts, :request_fun, &:httpc.request/4)
    url = String.to_charlist(String.trim_trailing(gateway_url, "/") <> "/v1/agent-adapters/pair")

    headers = [
      {~c"authorization", String.to_charlist("Bearer " <> gateway_token)},
      {~c"content-type", ~c"application/json"}
    ]

    body = JSON.encode!(payload)

    case request_fun.(:post, {url, headers, ~c"application/json", body}, [{:timeout, 10_000}], body_format: :binary) do
      {:ok, {{_version, status, _reason}, _headers, response_body}} when status in 200..299 ->
        with {:ok, decoded} <- JSON.decode(response_body),
             identity when is_map(identity) <- Map.get(decoded, @key_identity) do
          {:ok, identity}
        else
          _value -> {:error, "gateway pairing response did not include an adapter identity"}
        end

      {:ok, {{_version, status, _reason}, _headers, response_body}} ->
        {:error, "gateway pairing failed with HTTP #{status}: #{error_message(response_body)}"}

      {:error, reason} ->
        {:error, "gateway pairing request failed: #{inspect(reason)}"}
    end
  end

  defp error_message(response_body) when is_binary(response_body) do
    case JSON.decode(response_body) do
      {:ok, decoded} when is_map(decoded) ->
        case Map.get(decoded, @key_error) do
          error when is_map(error) -> Map.get(error, @key_message, response_body)
          _error -> response_body
        end

      _result ->
        response_body
    end
  end
end

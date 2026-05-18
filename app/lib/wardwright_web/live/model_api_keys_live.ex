defmodule WardwrightWeb.ModelApiKeysLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_state(socket, nil)}
  end

  @impl true
  def handle_event("create-key", %{"key" => params}, socket) do
    model = Wardwright.current_config()["model_id"]

    case Wardwright.ModelApiKeyStore.create(model, Map.get(params, "label", "")) do
      {:ok, key} -> {:noreply, assign_state(socket, key)}
      _ -> {:noreply, assign_state(socket, nil)}
    end
  end

  @impl true
  def handle_event("revoke-key", %{"id" => id}, socket) do
    _ = Wardwright.ModelApiKeyStore.revoke(id)
    {:noreply, assign_state(socket, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="content">
      <header class="topbar">
        <div>
          <p class="eyebrow">Access control</p>
          <h1>Model API Keys</h1>
          <p>
            Generate and revoke keys for the active Wardwright model. Keys are shown once.
          </p>
        </div>
        <a class="button secondary" href="/policies">Workbench</a>
      </header>

      <section class="panel">
        <h2>Active Model</h2>
        <dl class="metrics">
          <div>
            <dt>Model</dt>
            <dd><%= @model %></dd>
          </div>
          <div>
            <dt>Mode</dt>
            <dd><%= if @requires_api_key, do: "API key required", else: "Unkeyed" %></dd>
          </div>
          <div>
            <dt>Unkeyed access</dt>
            <dd><%= @unkeyed_model_access %></dd>
          </div>
        </dl>
      </section>

      <%= if @created_key do %>
        <section class="panel success_panel">
          <h2>New Key</h2>
          <p>Copy this key now. Wardwright stores only a hash and will not show it again.</p>
          <pre><%= @created_key["key"] %></pre>
        </section>
      <% end %>

      <section class="panel">
        <h2>Create Key</h2>
        <form phx-submit="create-key" class="inline_form">
          <label>
            Label
            <input name="key[label]" placeholder="gateway-prod" />
          </label>
          <button class="button" type="submit">Create key</button>
        </form>
      </section>

      <section class="panel">
        <h2>Keys</h2>
        <table>
          <thead>
            <tr>
              <th>Label</th>
              <th>Prefix</th>
              <th>Created</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@keys == []}>
              <td colspan="4">No API keys have been created for this model.</td>
            </tr>
            <tr :for={key <- @keys}>
              <td><%= key["label"] %></td>
              <td><code><%= key["prefix"] %></code></td>
              <td><%= key["created_at"] %></td>
              <td>
                <button
                  class="button danger"
                  type="button"
                  phx-click="revoke-key"
                  phx-value-id={key["id"]}
                >
                  Revoke
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </section>
    </section>
    """
  end

  defp assign_state(socket, created_key) do
    config = Wardwright.current_config()
    model = config["model_id"]

    socket
    |> assign(:model, model)
    |> assign(:requires_api_key, Wardwright.model_requires_api_key?(config))
    |> assign(:unkeyed_model_access, Wardwright.unkeyed_model_access(config))
    |> assign(:keys, Wardwright.ModelApiKeyStore.list(model))
    |> assign(:created_key, created_key)
  end
end

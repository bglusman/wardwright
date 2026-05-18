defmodule WardwrightWeb.ModelApiKeysLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_state(socket)}
  end

  @impl true
  def handle_event("create-key", %{"key" => params}, socket) do
    model = Wardwright.current_config()["model_id"]

    case Wardwright.ModelApiKeyStore.create(model, Map.get(params, "label", "")) do
      {:ok, key} -> {:noreply, assign_state(socket, created_key: key)}
      _ -> {:noreply, assign_state(socket, error: "Could not create API key.")}
    end
  end

  @impl true
  def handle_event("revoke-key", %{"id" => id}, socket) do
    _ = Wardwright.ModelApiKeyStore.revoke(id)
    {:noreply, assign_state(socket, status: "API key revoked.")}
  end

  @impl true
  def handle_event("save-access", %{"access" => params}, socket) do
    config = Wardwright.current_config()

    updated_config =
      config
      |> Map.put("requires_api_key", Map.get(params, "requires_api_key") == "true")
      |> Map.put("auth", %{
        "unkeyed_model_access" => Map.get(params, "unkeyed_model_access", "public")
      })

    case Wardwright.put_config(updated_config) do
      {:ok, _config} -> {:noreply, assign_state(socket, status: "Model access saved.")}
      {:error, message} -> {:noreply, assign_state(socket, error: message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <aside class="sidebar">
      <div class="brand">
        <span class="mark">W</span>
        <div>
          <strong>Wardwright</strong>
          <span>Model access controls</span>
        </div>
      </div>

      <nav>
        <h2 class="nav_heading">Workbench</h2>
        <a href="/policies">
          <strong>Policy Workbench</strong>
          <span>Review policy definitions and model routing.</span>
        </a>
        <a class="active" href="/admin/model-api-keys">
          <strong>Model API Keys</strong>
          <span>Configure keyed and unkeyed model access.</span>
        </a>
      </nav>

      <div class="sidebar_footer">
        <span>Active model</span>
        <strong><%= @model %></strong>
        <span>Access</span>
        <code><%= if @requires_api_key, do: "keyed", else: @unkeyed_model_access %></code>
      </div>
    </aside>

    <section class="workspace model_key_workspace">
      <header class="topbar">
        <div>
          <p class="eyebrow">Access control</p>
          <h1>Model API Keys</h1>
          <p>
            Configure access for the active Wardwright model and manage its API keys.
          </p>
        </div>
        <div class="topbar_actions">
          <a class="button secondary" href="/policies">Workbench</a>
        </div>
      </header>

      <section :if={@status || @error} class={["notice_panel", if(@error, do: "error", else: "success")]}>
        <strong><%= @status || @error %></strong>
      </section>

      <%= if @created_key do %>
        <section class="panel success_panel">
          <h2>New Key</h2>
          <p>Copy this key now. Wardwright stores only a hash and will not show it again.</p>
          <pre><%= @created_key["key"] %></pre>
        </section>
      <% end %>

      <section class="model_key_grid">
        <article class="panel model_summary_panel">
          <div class="panel_header">
            <div>
              <h2>Active Model</h2>
              <p>
                <code><%= @model %></code> is the model id agents call through the
                OpenAI-compatible API.
              </p>
            </div>
            <span class="badge"><%= if @requires_api_key, do: "keyed", else: "unkeyed" %></span>
          </div>
          <dl class="metrics">
            <div>
              <dt>Mode</dt>
              <dd><%= if @requires_api_key, do: "API key required", else: "Unkeyed" %></dd>
            </div>
            <div>
              <dt>Unkeyed access</dt>
              <dd><%= @unkeyed_model_access %></dd>
            </div>
            <div>
              <dt>Keys</dt>
              <dd><%= length(@keys) %></dd>
            </div>
          </dl>
        </article>

        <article class="panel access_policy_editor">
          <h2>Access Policy</h2>
          <form id="model-access-form" phx-submit="save-access" class="stacked_form">
            <fieldset>
              <legend>Model calls</legend>
              <label class="radio_card">
                <input
                  type="radio"
                  name="access[requires_api_key]"
                  value="false"
                  checked={!@requires_api_key}
                />
                <span>
                  <strong>Unkeyed</strong>
                  <small>Allow calls without a Wardwright model API key.</small>
                </span>
              </label>
              <label class="radio_card">
                <input
                  type="radio"
                  name="access[requires_api_key]"
                  value="true"
                  checked={@requires_api_key}
                />
                <span>
                  <strong>Keyed</strong>
                  <small>Require a bearer key scoped to this model.</small>
                </span>
              </label>
            </fieldset>

            <fieldset>
              <legend>When unkeyed</legend>
              <label class="radio_card">
                <input
                  type="radio"
                  name="access[unkeyed_model_access]"
                  value="public"
                  checked={@unkeyed_model_access == "public"}
                />
                <span>
                  <strong>Public</strong>
                  <small>Show the model in discovery and allow direct unkeyed calls.</small>
                </span>
              </label>
              <label class="radio_card">
                <input
                  type="radio"
                  name="access[unkeyed_model_access]"
                  value="internal"
                  checked={@unkeyed_model_access == "internal"}
                />
                <span>
                  <strong>Composition only</strong>
                  <small>Hide unkeyed direct calls while keeping internal composition possible.</small>
                </span>
              </label>
            </fieldset>

            <button class="button" type="submit">Save access policy</button>
          </form>
        </article>

        <article class="panel">
          <h2>Create Key</h2>
          <form id="create-model-key-form" phx-submit="create-key" class="inline_form">
            <label>
              Label
              <input name="key[label]" placeholder="gateway-prod" />
            </label>
            <button class="button" type="submit">Create key</button>
          </form>
        </article>

        <article class="panel keys_panel">
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
        </article>
      </section>
    </section>
    """
  end

  defp assign_state(socket, opts \\ []) do
    config = Wardwright.current_config()
    model = config["model_id"]

    socket
    |> assign(:model, model)
    |> assign(:requires_api_key, Wardwright.model_requires_api_key?(config))
    |> assign(:unkeyed_model_access, Wardwright.unkeyed_model_access(config))
    |> assign(:keys, Wardwright.ModelApiKeyStore.list(model))
    |> assign(:created_key, Keyword.get(opts, :created_key))
    |> assign(:status, Keyword.get(opts, :status))
    |> assign(:error, Keyword.get(opts, :error))
  end
end

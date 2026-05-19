defmodule WardwrightWeb.ModelApiKeysLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(params, _session, socket) do
    {:ok, assign_state(socket, selected_model: requested_model(params))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign_state(socket, selected_model: requested_model(params))}
  end

  @impl true
  def handle_event("create-key", %{"key" => params}, socket) do
    model = socket.assigns.model

    case Wardwright.ModelApiKeyStore.create(model, Map.get(params, "label", "")) do
      {:ok, key} ->
        {:noreply, assign_state(socket, selected_model: model, created_key: key)}

      _ ->
        {:noreply, assign_state(socket, selected_model: model, error: "Could not create API key.")}
    end
  end

  @impl true
  def handle_event("revoke-key", %{"id" => id}, socket) do
    _ = Wardwright.ModelApiKeyStore.revoke(id)

    {:noreply, assign_state(socket, selected_model: socket.assigns.model, status: "API key revoked.")}
  end

  @impl true
  def handle_event("select-model", %{"model" => model}, socket) do
    {:noreply, push_patch(socket, to: "/admin/model-api-keys?model=#{URI.encode_www_form(model)}")}
  end

  @impl true
  def handle_event("save-access", %{"access" => params}, socket) do
    config = socket.assigns.config
    unkeyed_model_access = Map.get(params, "unkeyed_model_access", Wardwright.unkeyed_model_access(config))

    updated_config =
      config
      |> Map.put("requires_api_key", Map.get(params, "requires_api_key") == "true")
      |> Map.put("auth", %{
        "unkeyed_model_access" => unkeyed_model_access
      })

    case Wardwright.put_model_config(updated_config) do
      {:ok, _config} ->
        {:noreply, assign_state(socket, selected_model: socket.assigns.model, status: "Model access saved.")}

      {:error, message} ->
        {:noreply, assign_state(socket, selected_model: socket.assigns.model, error: message)}
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
        <a href="/workbench">
          <strong>Workbench</strong>
          <span>Run and inspect registered models.</span>
        </a>
        <a href="/policies">
          <strong>Legacy Workbench</strong>
          <span>Use the previous policy projection view.</span>
        </a>
        <a class="active" href="/admin/model-api-keys">
          <strong>Model Access</strong>
          <span>Configure keyed and unkeyed model access.</span>
        </a>
      </nav>

      <div class="sidebar_footer">
        <span>Selected model</span>
        <strong><%= @model %></strong>
        <span>Access</span>
        <code><%= if @requires_api_key, do: "keyed", else: @unkeyed_model_access %></code>
      </div>
    </aside>

    <section class="workspace model_key_workspace">
      <header class="topbar">
        <div>
          <p class="eyebrow">Access control</p>
          <h1>Model Access</h1>
          <p>
            Choose a Wardwright model, then configure API-key requirements and unkeyed access.
          </p>
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
              <h2>Selected Model</h2>
              <p>
                <code><%= @model %></code> is the model id agents call through the
                OpenAI-compatible API.
              </p>
            </div>
            <span class="badge"><%= if @requires_api_key, do: "keyed", else: "unkeyed" %></span>
          </div>
          <form id="model-selector-form" phx-change="select-model" class="stacked_form">
            <label>
              Model to edit
              <select name="model">
                <option :for={model <- @models} value={model["id"]} selected={model["id"] == @model}>
                  <%= model["id"] %>
                </option>
              </select>
            </label>
          </form>
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
              <div class="radio_card access_mode_card">
                <label class="radio_card_main">
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
                <div class="nested_radio_group">
                  <span>Unkeyed access</span>
                  <label class="radio_card compact">
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
                  <label class="radio_card compact">
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
                </div>
              </div>
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

  defp assign_state(socket, opts) do
    models = Wardwright.model_summaries()
    config = selected_config(Keyword.get(opts, :selected_model))
    model = config["model_id"]

    socket
    |> assign(:config, config)
    |> assign(:models, models)
    |> assign(:model, model)
    |> assign(:requires_api_key, Wardwright.model_requires_api_key?(config))
    |> assign(:unkeyed_model_access, Wardwright.unkeyed_model_access(config))
    |> assign(:keys, Wardwright.ModelApiKeyStore.list(model))
    |> assign(:created_key, Keyword.get(opts, :created_key))
    |> assign(:status, Keyword.get(opts, :status))
    |> assign(:error, Keyword.get(opts, :error))
  end

  defp requested_model(%{"model" => model}) when is_binary(model), do: model
  defp requested_model(_params), do: nil

  defp selected_config(model) when is_binary(model) do
    case Wardwright.model_config(model) do
      {:ok, config} -> config
      {:error, _message} -> Wardwright.current_config()
    end
  end

  defp selected_config(_model), do: Wardwright.current_config()
end

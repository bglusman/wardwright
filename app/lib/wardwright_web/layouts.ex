defmodule WardwrightWeb.Layouts do
  @moduledoc false

  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Wardwright</title>
      </head>
      <body>
        <main class="shell">
          <%= @inner_content %>
        </main>
      </body>
    </html>
    """
  end
end

defmodule WebWeb.LiveDashboardCarbonStyle do
  @moduledoc false

  import Phoenix.Component

  alias Phoenix.LiveDashboard.PageBuilder

  def on_mount(:default, _params, _session, socket) do
    {:cont, PageBuilder.register_before_closing_head_tag(socket, &carbon_head_tags/1)}
  end

  defp carbon_head_tags(assigns) do
    ~H"""
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link
      rel="stylesheet"
      href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@300;400;600&display=swap"
    />
    <style nonce={@csp_nonces[:style]}>
      <%= Phoenix.HTML.raw(carbon_css()) %>
    </style>
    """
  end

  defp carbon_css do
    """
    :root {
      --carbon-blue: #0f62fe;
      --carbon-blue-hover: #0050e6;
      --carbon-blue-80: #002d9c;
      --carbon-ink: #161616;
      --carbon-muted: #525252;
      --carbon-subtle: #8c8c8c;
      --carbon-canvas: #ffffff;
      --carbon-surface: #f4f4f4;
      --carbon-line: #e0e0e0;
      --carbon-line-strong: #161616;
      --carbon-inverse: #262626;
      --carbon-inverse-muted: #c6c6c6;
    }

    html,
    body {
      background: var(--carbon-canvas);
      color: var(--carbon-ink);
      font-family: "IBM Plex Sans", "Helvetica Neue", Arial, sans-serif;
      font-size: 16px;
      font-weight: 400;
      letter-spacing: 0.16px;
    }

    body,
    .layout-wrapper {
      min-height: 100vh;
      background: var(--carbon-canvas);
    }

    a {
      color: var(--carbon-blue);
      text-decoration: none;
    }

    a:hover,
    a:focus {
      color: var(--carbon-blue-hover);
      text-decoration: underline;
    }

    header.d-flex {
      min-height: 0;
      background: var(--carbon-canvas);
      border-bottom: 1px solid var(--carbon-line);
      box-shadow: none;
    }

    #menu.container {
      width: 100%;
      max-width: none;
      min-height: 0;
      padding: 0 32px;
      display: grid !important;
      grid-template-columns: minmax(180px, 1fr) auto;
      grid-template-areas:
        "title controls"
        "nav nav";
      align-items: center;
      column-gap: 24px;
    }

    #menu h1 {
      grid-area: title;
      min-height: 48px;
      margin: 0;
      display: flex;
      align-items: center;
      color: var(--carbon-ink);
      font-size: 14px;
      font-weight: 600;
      line-height: 1.29;
      letter-spacing: 0.16px;
    }

    #nav-dropdowns {
      grid-area: controls;
      min-height: 48px;
      display: flex;
      align-items: flex-end;
      justify-content: flex-end;
      flex-wrap: wrap;
      gap: 24px;
      padding: 8px 0;
      border-top: 0;
    }

    #nav-dropdowns form {
      margin: 0;
      min-width: 160px;
    }

    #nav-dropdowns label,
    label {
      margin: 0 0 4px;
      color: var(--carbon-muted);
      font-size: 12px;
      font-weight: 400;
      line-height: 1.33;
      letter-spacing: 0.32px;
    }

    select,
    .custom-select,
    .form-control,
    input,
    textarea {
      min-height: 40px;
      border: 0;
      border-bottom: 1px solid var(--carbon-subtle);
      border-radius: 0;
      background-color: var(--carbon-surface);
      color: var(--carbon-ink);
      box-shadow: none;
      font-family: inherit;
      font-size: 14px;
      line-height: 1.29;
      max-width: 100%;
    }

    select:focus,
    .custom-select:focus,
    .form-control:focus,
    input:focus,
    textarea:focus {
      border-color: var(--carbon-blue);
      box-shadow: inset 0 -1px 0 var(--carbon-blue);
      outline: 2px solid var(--carbon-blue);
      outline-offset: -2px;
    }

    #menu-bar {
      grid-area: nav;
      min-height: 48px;
      display: flex;
      align-items: stretch;
      flex-wrap: nowrap;
      gap: 0;
      margin: 0;
      overflow-x: auto;
      overflow-y: hidden;
      scrollbar-width: thin;
      border-top: 1px solid var(--carbon-line);
    }

    #menu-bar .menu-item {
      min-height: 48px;
      flex: 0 0 auto;
      margin: 0;
      padding: 0 16px;
      display: inline-flex;
      align-items: center;
      white-space: nowrap;
      border: 0;
      border-bottom: 3px solid transparent;
      border-radius: 0;
      background: var(--carbon-canvas);
      color: var(--carbon-muted);
      font-size: 14px;
      font-weight: 400;
      line-height: 1.29;
      text-decoration: none;
    }

    #menu-bar .menu-item:hover {
      background: var(--carbon-surface);
      color: var(--carbon-ink);
      text-decoration: none;
    }

    #menu-bar .menu-item.active {
      border-bottom-color: var(--carbon-blue);
      color: var(--carbon-ink);
      font-weight: 600;
    }

    #menu-bar .menu-item-disabled {
      color: var(--carbon-subtle);
    }

    #main.container {
      width: 100%;
      max-width: none;
      padding: clamp(16px, 3vw, 32px);
      background: var(--carbon-canvas);
      overflow-x: hidden;
    }

    .container {
      max-width: none;
    }

    h1,
    h2,
    h3,
    h4,
    h5,
    h6 {
      color: var(--carbon-ink);
      font-family: inherit;
      font-weight: 400;
      letter-spacing: 0;
    }

    h2 {
      font-size: 32px;
      line-height: 1.25;
    }

    h3,
    .card-title {
      font-size: 24px;
      line-height: 1.33;
    }

    .nav,
    .nav-pills,
    .nav-bar {
      border-bottom: 1px solid var(--carbon-line);
      gap: 0;
      flex-wrap: nowrap;
      overflow-x: auto;
      overflow-y: hidden;
      scrollbar-width: thin;
    }

    .nav .nav-item {
      margin: 0;
    }

    .nav .nav-link {
      min-height: 48px;
      white-space: nowrap;
      padding: 14px 16px 11px;
      border: 0;
      border-bottom: 3px solid transparent;
      border-radius: 0;
      background: var(--carbon-canvas);
      color: var(--carbon-muted);
      font-size: 14px;
      font-weight: 400;
      line-height: 1.29;
    }

    .nav .nav-link:hover {
      background: var(--carbon-surface);
      color: var(--carbon-ink);
      text-decoration: none;
    }

    .nav .nav-link.active {
      border-bottom-color: var(--carbon-blue);
      background: var(--carbon-canvas);
      color: var(--carbon-ink);
      font-weight: 600;
    }

    .phx-dashboard-metrics-grid.row {
      display: grid !important;
      grid-template-columns: repeat(auto-fit, minmax(min(100%, 340px), 1fr));
      gap: 16px;
      margin: 0;
    }

    .charts-col {
      width: auto !important;
      max-width: none !important;
      min-width: 0;
      margin: 0;
      padding: 0;
      flex: initial !important;
    }

    .card {
      min-width: 0;
      border: 1px solid var(--carbon-line);
      border-radius: 0;
      background: var(--carbon-canvas);
      box-shadow: none;
    }

    .card-body {
      min-width: 0;
      padding: 24px;
      overflow: hidden;
    }

    .chart {
      width: 100%;
      min-width: 0;
      min-height: 256px;
      overflow: hidden;
    }

    .charts-col .card {
      height: 100%;
    }

    .charts-col .card .uplot {
      max-width: 100% !important;
    }

    .uplot,
    .u-title,
    .u-legend,
    .u-label,
    .u-value {
      color: var(--carbon-ink);
      font-family: "IBM Plex Sans", "Helvetica Neue", Arial, sans-serif;
    }

    .u-title {
      font-size: 14px;
      font-weight: 600;
      line-height: 1.29;
    }

    .u-legend {
      font-size: 12px;
      letter-spacing: 0.32px;
    }

    .table,
    table {
      width: 100%;
      border-collapse: collapse;
      border: 1px solid var(--carbon-line);
      color: var(--carbon-ink);
      font-size: 14px;
    }

    .tabular-card,
    .card:has(table) {
      overflow-x: auto;
    }

    .table th,
    table th {
      border-bottom: 1px solid var(--carbon-line);
      background: var(--carbon-surface);
      color: var(--carbon-muted);
      font-size: 12px;
      font-weight: 600;
      letter-spacing: 0.32px;
    }

    .table td,
    table td {
      border-bottom: 1px solid var(--carbon-line);
      color: var(--carbon-ink);
      font-size: 14px;
    }

    .btn {
      min-height: 40px;
      padding: 11px 16px;
      border-radius: 0;
      box-shadow: none;
      font-family: inherit;
      font-size: 14px;
      font-weight: 400;
      line-height: 1.29;
    }

    .btn-primary {
      border-color: var(--carbon-blue);
      background: var(--carbon-blue);
      color: #ffffff;
    }

    .btn-primary:hover,
    .btn-primary:focus {
      border-color: var(--carbon-blue-hover);
      background: var(--carbon-blue-hover);
      color: #ffffff;
    }

    .btn-secondary,
    .btn-outline-secondary {
      border-color: var(--carbon-ink);
      background: var(--carbon-ink);
      color: #ffffff;
    }

    .badge,
    .alert,
    .modal-content,
    .dropdown-menu,
    .popover {
      border-radius: 0;
      box-shadow: none;
    }

    .alert,
    .modal-content,
    .dropdown-menu,
    .popover {
      border: 1px solid var(--carbon-line);
    }

    .progress {
      height: 4px;
      border-radius: 0;
      background: var(--carbon-line);
    }

    .progress-bar {
      background-color: var(--carbon-blue) !important;
    }

    footer.flex-shrink-0 {
      padding: 24px 32px;
      border-top: 0;
      background: var(--carbon-ink);
      color: var(--carbon-inverse-muted);
      font-size: 12px;
      line-height: 1.33;
    }

    footer.flex-shrink-0 a {
      color: #ffffff;
    }

    @media (max-width: 991.98px) {
      #menu.container {
        grid-template-columns: 1fr;
        grid-template-areas:
          "title"
          "controls"
          "nav";
        row-gap: 0;
      }

      #nav-dropdowns {
        justify-content: flex-start;
        border-top: 1px solid var(--carbon-line);
      }
    }

    @media (max-width: 768px) {
      #menu.container,
      #main.container {
        padding-right: 16px;
        padding-left: 16px;
      }

      #nav-dropdowns {
        align-items: stretch;
        flex-direction: column;
        gap: 12px;
      }

      #menu-bar {
        overflow-x: auto;
      }

      .card-body {
        padding: 16px;
      }

      .chart {
        min-height: 220px;
      }
    }

    @media (max-width: 575.98px) {
      #nav-dropdowns form,
      #nav-dropdowns select,
      #nav-dropdowns .custom-select {
        width: 100%;
      }

      .phx-dashboard-metrics-grid.row {
        grid-template-columns: 1fr;
      }
    }
    """
  end
end

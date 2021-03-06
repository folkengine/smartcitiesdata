defmodule TelemetryEvent.Helper.TelemetryEventHelper do
  @moduledoc false
  alias TelemetryEvent.Helper.MetricsEvent

  def metrics_config(app_name) do
    [
      port: metrics_port(),
      metrics: MetricsEvent.metrics(),
      name: app_name
    ]
  end

  def tags_and_values(event_tags_and_values) do
    event_tags_and_values
    |> Map.new(fn {k, v} -> {k, replace_nil(v)} end)
  end

  defp metrics_port() do
    case Application.get_env(:telemetry_event, :metrics_port) do
      nil -> create_port_no()
      port_no -> port_no
    end
  end

  defp replace_nil(value) when is_nil(value) or value == "", do: "UNKNOWN"

  defp replace_nil(value), do: value

  defp create_port_no() do
    1_000..9_999
    |> Enum.random()
    |> verify_port_no()
  end

  defp verify_port_no(port_no) do
    case :gen_tcp.listen(port_no, []) do
      {:ok, port} ->
        Port.close(port)
        Application.put_env(:telemetry_event, :metrics_port, port_no)
        port_no

      {:error, :eaddrinuse} ->
        create_port_no()
    end
  end
end

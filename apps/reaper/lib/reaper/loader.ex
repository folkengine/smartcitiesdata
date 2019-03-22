defmodule Reaper.Loader do
  @moduledoc false
  alias Kaffe.Producer
  alias SmartCity.Data

  def load(payloads, reaper_config, start_time) do
    payloads
    |> Enum.map(
      &send_to_kafka(
        &1,
        partition_key(
          &1,
          "Elixir.Reaper.Partitioners." <>
            ((reaper_config.partitioner.type == nil && "Hash") || reaper_config.partitioner.type) <>
            "Partitioner",
          reaper_config.partitioner.query
        ),
        reaper_config,
        start_time
      )
    )
  end

  defp send_to_kafka(payload, key, reaper_config, start_time) do
    message = convert_to_message(payload, reaper_config.dataset_id, start_time)
    {Producer.produce_sync(key, message), payload}
  end

  defp partition_key(payload, partitioner, query) do
    apply(String.to_existing_atom(partitioner), :partition, [payload, query])
  end

  defp convert_to_message(payload, dataset_id, start) do
    start = format_date(start)
    stop = format_date(DateTime.utc_now())

    with {:ok, message} <-
           Data.new(%{
             dataset_id: dataset_id,
             operational: %{timing: [%{app: "reaper", label: "sus", start_time: start, end_time: stop}]},
             payload: payload,
             _metadata: %{}
           }),
         {:ok, value_part} <- Jason.encode(message) do
      value_part
    end
  end

  def format_date(some_date) do
    DateTime.to_iso8601(some_date)
  end
end

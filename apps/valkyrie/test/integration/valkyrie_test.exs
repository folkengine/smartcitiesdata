defmodule ValkyrieTest do
  use ExUnit.Case
  use Divo
  alias SmartCity.TestDataGenerator, as: TDG
  import SmartCity.TestHelper
  import SmartCity.Event, only: [data_ingest_start: 0]
  alias TelemetryEvent.Helper.TelemetryEventHelper

  @endpoints Application.get_env(:valkyrie, :elsa_brokers)
  @dlq_topic Application.get_env(:dead_letter, :driver) |> get_in([:init_args, :topic])
  @input_topic_prefix Application.get_env(:valkyrie, :input_topic_prefix)
  @output_topic_prefix Application.get_env(:valkyrie, :output_topic_prefix)
  @instance Valkyrie.Application.instance()

  setup_all do
    dataset =
      TDG.create_dataset(%{
        id: "pirates",
        technical: %{
          sourceType: "ingest",
          schema: [
            %{name: "name", type: "string"},
            %{name: "alignment", type: "string"},
            %{name: "age", type: "string"}
          ]
        }
      })

    pid = start_telemetry()

    on_exit(fn ->
      stop_telemetry(pid)
    end)

    invalid_message =
      TestHelpers.create_data(%{
        payload: %{"name" => "Blackbeard", "alignment" => %{"invalid" => "string"}, "age" => "thirty-two"},
        dataset_id: dataset.id
      })

    messages = [
      TestHelpers.create_data(%{
        payload: %{"name" => "Jack Sparrow", "alignment" => "chaotic", "age" => "32"},
        dataset_id: dataset.id
      }),
      invalid_message,
      TestHelpers.create_data(%{
        payload: %{"name" => "Will Turner", "alignment" => "good", "age" => "25"},
        dataset_id: dataset.id
      }),
      TestHelpers.create_data(%{
        payload: %{"name" => "Barbosa", "alignment" => "evil", "age" => "100"},
        dataset_id: dataset.id
      })
    ]

    input_topic = "#{@input_topic_prefix}-#{dataset.id}"
    output_topic = "#{@output_topic_prefix}-#{dataset.id}"

    Brook.Event.send(@instance, data_ingest_start(), :valkyrie, dataset)
    TestHelpers.wait_for_topic(@endpoints, input_topic)

    TestHelpers.produce_messages(messages, input_topic, @endpoints)

    {:ok, %{output_topic: output_topic, messages: messages, invalid_message: invalid_message}}
  end

  test "valkyrie updates the operational struct", %{output_topic: output_topic} do
    eventually fn ->
      messages = TestHelpers.get_data_messages_from_kafka_with_timing(output_topic, @endpoints)

      assert [%{operational: %{timing: [%{app: "valkyrie"} | _]}} | _] = messages
    end
  end

  test "valkyrie rejects unparseable messages and passes the rest through", %{
    output_topic: output_topic,
    messages: messages,
    invalid_message: invalid_message
  } do
    eventually fn ->
      output_messages = TestHelpers.get_data_messages_from_kafka(output_topic, @endpoints)

      assert messages -- [invalid_message] == output_messages
    end
  end

  test "valkyrie sends invalid data messages to the dlq", %{invalid_message: invalid_message} do
    encoded_og_message = invalid_message |> Jason.encode!()

    metrics_port = Application.get_env(:telemetry_event, :metrics_port)

    eventually fn ->
      messages = TestHelpers.get_dlq_messages_from_kafka(@dlq_topic, @endpoints)

      assert :ok =
               [
                 dataset_id: "dataset_id",
                 reason: "reason"
               ]
               |> TelemetryEvent.add_event_metrics([:dead_letters_handled])

      response = HTTPoison.get!("http://localhost:#{metrics_port}/metrics")

      assert true ==
               String.contains?(
                 response.body,
                 "dead_letters_handled_count{dataset_id=\"dataset_id\",reason=\"reason\"}"
               )

      assert true ==
               String.contains?(
                 response.body,
                 "dead_letters_handled_count{dataset_id=\"pirates\",reason=\"%{\\\"alignment\\\" => :invalid_string}\"}"
               )

      assert [%{app: "Valkyrie", original_message: ^encoded_og_message}] = messages
    end
  end

  defp start_telemetry() do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Valkyrie.Dynamic.Supervisor,
        {TelemetryMetricsPrometheus, TelemetryEventHelper.metrics_config(@instance)}
      )

    pid
  end

  defp stop_telemetry(pid) do
    case pid do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(Valkyrie.Dynamic.Supervisor, pid)
    end
  end
end

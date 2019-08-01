defmodule AndiWeb.DatasetControllerTest do
  use AndiWeb.ConnCase
  use Placebo

  @route "/api/v1/dataset"
  @get_datasets_route "/api/v1/datasets"
  alias SmartCity.Dataset
  alias SmartCity.TestDataGenerator, as: TDG

  setup do
    example_dataset_1 = TDG.create_dataset(%{})

    example_dataset_1 =
      example_dataset_1
      |> Jason.encode!()
      |> Jason.decode!()

    example_dataset_2 = TDG.create_dataset(%{})

    example_dataset_2 =
      example_dataset_2
      |> Jason.encode!()
      |> Jason.decode!()

    example_datasets = [example_dataset_1, example_dataset_2]
    allow(Dataset.write(any()), return: {:ok, "id"}, meck_options: [:passthrough])

    allow(Brook.get_all(any()),
      return: {:ok, %{example_dataset_1["id"] => example_dataset_1, example_dataset_2["id"] => example_dataset_2}},
      meck_options: [:passthrough]
    )

    allow(Brook.send_event(any(), any()), return: :ok, meck_options: [:passthrough])

    uuid = Faker.UUID.v4()

    request = %{
      "id" => uuid,
      "technical" => %{
        "dataName" => "dataset",
        "orgId" => "org-123-456",
        "orgName" => "org",
        "stream" => false,
        "sourceUrl" => "https://example.com",
        "sourceType" => "stream",
        "sourceFormat" => "gtfs",
        "cadence" => 9000,
        "schema" => [],
        "private" => false,
        "headers" => %{
          "accepts" => "application/foobar"
        },
        "sourceQueryParams" => %{
          "apiKey" => "foobar"
        },
        "systemName" => "org__dataset",
        "transformations" => [],
        "validations" => []
      },
      "business" => %{
        "dataTitle" => "dataset title",
        "description" => "description",
        "modifiedDate" => "date",
        "orgTitle" => "org title",
        "contactName" => "contact name",
        "contactEmail" => "contact@email.com",
        "license" => "license",
        "rights" => "rights information",
        "homepage" => "",
        "keywords" => []
      },
      "_metadata" => %{
        "intendedUse" => ["use 1", "use 2", "use 3"],
        "expectedBenefit" => []
      }
    }

    message =
      request
      |> SmartCity.Helpers.to_atom_keys()
      |> TDG.create_dataset()
      |> Jason.encode!()
      |> Jason.decode!()

    {:ok, request: request, message: message, example_datasets: example_datasets}
  end

  describe "PUT /api/ without systemName" do
    setup %{conn: conn, request: request} do
      allow Brook.get_all!(any()), return: %{}
      {_, request} = pop_in(request, ["technical", "systemName"])
      [conn: put(conn, @route, request)]
    end

    test "return a 201", %{conn: conn} do
      system_name =
        conn
        |> json_response(201)
        |> get_in(["technical", "systemName"])

      assert system_name == "org__dataset"
    end

    # This test marked for deletion once Dataset Registry is retired
    test "writes data to registry", %{message: message} do
      {:ok, struct} = Dataset.new(message)

      assert_called(Dataset.write(struct), once())
    end

    test "writes data to event stream", %{message: message} do
      {:ok, _struct} = Dataset.new(message)

      assert_called(Brook.send_event(any(), any()), once())
    end
  end

  test "put returns 400 when systemName matches existing systemName", %{conn: conn, request: request} do
    org_name = request["technical"]["orgName"]
    data_name = request["technical"]["dataName"]

    existing_dataset =
      TDG.create_dataset(
        id: "existing-ds1",
        technical: %{dataName: data_name, orgName: org_name, systemName: "#{org_name}__#{data_name}"}
      )

    allow Brook.get_all!(any()), return: %{existing_dataset => existing_dataset}

    response =
      conn
      |> put(@route, request)
      |> json_response(400)

    assert %{"reason" => "Existing dataset has the same orgName and dataName"} == response
  end

  describe "PUT /api/ with systemName" do
    setup %{conn: conn, request: request} do
      allow Brook.get_all!(any()), return: %{}
      req = put_in(request, ["technical", "systemName"], "org__dataset_akdjbas")
      [conn: put(conn, @route, req)]
    end

    test "return 201", %{conn: conn} do
      system_name =
        conn
        |> json_response(201)
        |> get_in(["technical", "systemName"])

      assert system_name == "org__dataset"
    end

    # This test marked for deletion once Dataset Registry is retired
    test "writes to dataset registry", %{message: message} do
      {:ok, struct} = Dataset.new(message)
      assert_called(Dataset.write(struct), once())
    end

    test "writes to event stream", %{message: message} do
      {:ok, struct} = Dataset.new(message)
      assert_called(Brook.send_event(any(), struct), once())
    end
  end

  @tag capture_log: true
  test "PUT /api/ without data returns 500", %{conn: conn} do
    conn = put(conn, @route)
    assert json_response(conn, 500) =~ "Unable to process your request"
  end

  @tag capture_log: true
  test "PUT /api/ with improperly shaped data returns 500", %{conn: conn} do
    conn = put(conn, @route, %{"id" => 5, "operational" => 2})
    assert json_response(conn, 500) =~ "Unable to process your request"
  end

  describe "GET dataset definitions from /api/dataset/" do
    setup %{conn: conn, request: request} do
      [conn: get(conn, @get_datasets_route, request)]
    end

    @tag capture_log: true
    test "returns a 200", %{conn: conn, example_datasets: example_datasets} do
      actual_datasets =
        conn
        |> json_response(200)

      assert MapSet.new(example_datasets) == MapSet.new(actual_datasets)
    end
  end

  test "PUT /api/ dataset passed without UUID generates UUID for dataset", %{conn: conn, request: request} do
    allow Brook.get_all!(any()), return: %{}

    {_, request} = pop_in(request, ["id"])
    conn = put(conn, @route, request)

    uuid =
      conn
      |> json_response(201)
      |> get_in(["id"])

    assert uuid != nil
  end
end

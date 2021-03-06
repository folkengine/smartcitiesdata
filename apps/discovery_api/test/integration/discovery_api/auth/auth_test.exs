defmodule DiscoveryApi.Auth.AuthTest do
  use ExUnit.Case
  use DiscoveryApi.DataCase

  import ExUnit.CaptureLog
  import SmartCity.TestHelper, only: [eventually: 3]

  alias DiscoveryApi.Test.Helper
  alias DiscoveryApi.Test.AuthHelper
  alias DiscoveryApi.Schemas.Users
  alias DiscoveryApi.Schemas.Visualizations
  alias DiscoveryApi.Repo

  @organization_1_name "organization_one"
  @organization_2_name "organization_two"

  setup_all do
    organization_1 = Helper.create_persisted_organization(%{orgName: @organization_1_name})
    organization_2 = Helper.create_persisted_organization(%{orgName: @organization_2_name})

    private_model_that_belongs_to_org_1 =
      Helper.sample_model(%{
        private: true,
        organization: @organization_1_name,
        organizationDetails: organization_1,
        keywords: ["dataset", "facet1"]
      })

    private_model_that_belongs_to_org_2 =
      Helper.sample_model(%{
        private: true,
        organization: @organization_2_name,
        organizationDetails: organization_2,
        keywords: ["dataset", "facet2"]
      })

    public_model_that_belongs_to_org_1 =
      Helper.sample_model(%{
        private: false,
        organization: @organization_1_name,
        organizationDetails: organization_1,
        keywords: ["dataset", "public_facet"]
      })

    Helper.clear_saved_models()
    Helper.save_model(private_model_that_belongs_to_org_1)
    Helper.save_model(private_model_that_belongs_to_org_2)
    Helper.save_model(public_model_that_belongs_to_org_1)

    {:ok,
     %{
       private_model_that_belongs_to_org_1: private_model_that_belongs_to_org_1,
       private_model_that_belongs_to_org_2: private_model_that_belongs_to_org_2,
       public_model_that_belongs_to_org_1: public_model_that_belongs_to_org_1
     }}
  end

  describe "GET /dataset/:dataset_id with auth0 auth provider" do
    setup %{private_model_that_belongs_to_org_1: model} do
      AuthHelper.auth0_setup()
      |> on_exit()

      user = Helper.create_persisted_user(AuthHelper.valid_jwt_sub())
      Helper.associate_user_with_organization(user.id, model.organizationDetails.id)
    end

    @moduletag capture_log: true
    test "is able to access a restricted dataset with a valid token", setup_map do
      %{status_code: status_code, body: body} =
        get_with_authentication(
          "http://localhost:4000/api/v1/dataset/#{setup_map[:private_model_that_belongs_to_org_1].id}/",
          AuthHelper.valid_jwt()
        )

      assert 200 == status_code
      assert body.id == setup_map[:private_model_that_belongs_to_org_1].id
    end

    @moduletag capture_log: true
    test "is not able to access a restricted dataset with a bad token", setup_map do
      %{status_code: status_code, body: body} =
        get_with_authentication(
          "http://localhost:4000/api/v1/dataset/#{setup_map[:private_model_that_belongs_to_org_1].id}/",
          "sdfsadfasdasdfas"
        )

      assert status_code == 401
      assert body.message == "Unauthorized"
    end
  end

  describe "POST /logged-in" do
    setup do
      AuthHelper.auth0_setup()
      |> on_exit()
    end

    test "returns 'OK' when token is valid" do
      %{status_code: status_code} =
        "localhost:4000/api/v1/logged-in"
        |> HTTPoison.post!("",
          Authorization: "Bearer #{AuthHelper.valid_jwt()}"
        )

      assert status_code == 200
    end

    test "login is IDEMpotent" do
      assert %{status_code: 200} =
               HTTPoison.post!(
                 "localhost:4000/api/v1/logged-in",
                 "",
                 Authorization: "Bearer #{AuthHelper.valid_jwt()}"
               )

      assert %{status_code: 200} =
               HTTPoison.post!(
                 "localhost:4000/api/v1/logged-in",
                 "",
                 Authorization: "Bearer #{AuthHelper.valid_jwt()}"
               )
    end

    test "saves logged in user" do
      subject_id = AuthHelper.valid_jwt_sub()

      eventually(
        fn ->
          assert {:ok, _} =
                   HTTPoison.post(
                     "localhost:4000/api/v1/logged-in",
                     "",
                     Authorization: "Bearer #{AuthHelper.valid_jwt()}"
                   )

          assert {:ok, actual} = Users.get_user(subject_id, :subject_id)

          assert subject_id == actual.subject_id
          assert "x@y.z" == actual.email
          assert actual.id != nil
        end,
        2000,
        10
      )
    end

    test "returns 'unauthorized' when token is invalid" do
      %{status_code: status_code} =
        "localhost:4000/api/v1/logged-in"
        |> HTTPoison.post!(
          "",
          Authorization: "Bearer !NOPE!"
        )

      assert status_code == 401
    end
  end

  describe "POST /logged-out" do
    setup do
      AuthHelper.auth0_setup()
      |> on_exit()
    end

    test "logout is not idempotent" do
      subject = AuthHelper.revocable_jwt_sub()

      {_, token, 200} = AuthHelper.login(subject, AuthHelper.revocable_jwt())

      assert %{status_code: 200} =
               "localhost:4000/api/v1/logged-out"
               |> HTTPoison.post!(
                 "",
                 Authorization: "Bearer " <> token
               )

      assert %{status_code: 401} =
               "localhost:4000/api/v1/logged-out"
               |> HTTPoison.post!(
                 "",
                 Authorization: "Bearer " <> token
               )

      assert {_, _, 401} = AuthHelper.login(subject, token)
    end

    test "when user is logged-out, they can't use their token to access protected resources, even when they attempt to login",
         %{private_model_that_belongs_to_org_1: model} do
      subject = AuthHelper.revocable_jwt_sub()
      model_id = model.id

      {user, token, 200} = AuthHelper.login(subject, AuthHelper.revocable_jwt())

      Helper.associate_user_with_organization(
        user.id,
        model.organizationDetails.id
      )

      assert %{status_code: 200, body: %{id: ^model_id}} =
               get_with_authentication(
                 "http://localhost:4000/api/v1/dataset/#{model.id}/",
                 token
               )

      assert %{status_code: 200} =
               HTTPoison.post!(
                 "localhost:4000/api/v1/logged-out",
                 "",
                 Authorization: "Bearer " <> token
               )

      assert %{status_code: 401, body: %{message: "Unauthorized"}} =
               get_with_authentication(
                 "http://localhost:4000/api/v1/dataset/#{model.id}/",
                 token
               )

      assert {_, _, 401} = AuthHelper.login(subject, token)

      assert %{status_code: 401, body: %{message: "Unauthorized"}} =
               get_with_authentication(
                 "http://localhost:4000/api/v1/dataset/#{model.id}/",
                 token
               )
    end

    test "when user is logged-out, it doesn't affect other users", %{private_model_that_belongs_to_org_1: model} do
      subject = AuthHelper.revocable_jwt_sub()
      other_subject = AuthHelper.valid_jwt_sub()
      other_subject_token = AuthHelper.valid_jwt()
      model_id = model.id

      {user, token, 200} = AuthHelper.login(subject, AuthHelper.revocable_jwt())

      Helper.associate_user_with_organization(
        user.id,
        model.organizationDetails.id
      )

      other_user = Helper.create_persisted_user(other_subject)

      Helper.associate_user_with_organization(
        other_user.id,
        model.organizationDetails.id
      )

      assert %{status_code: 200} =
               HTTPoison.post!(
                 "localhost:4000/api/v1/logged-out",
                 "",
                 Authorization: "Bearer " <> token
               )

      assert %{status_code: 401, body: %{message: "Unauthorized"}} =
               get_with_authentication(
                 "http://localhost:4000/api/v1/dataset/#{model.id}/",
                 token
               )

      assert %{status_code: 200, body: %{id: ^model_id}} =
               get_with_authentication(
                 "http://localhost:4000/api/v1/dataset/#{model.id}/",
                 other_subject_token
               )
    end
  end

  describe "POST /visualization" do
    setup do
      AuthHelper.auth0_setup()
      |> on_exit()
    end

    test "adds owner data to the newly created visualization" do
      user = Helper.create_persisted_user(AuthHelper.valid_jwt_sub())

      %{status_code: status_code, body: body} =
        post_with_authentication(
          "localhost:4000/api/v1/visualization",
          ~s({"query": "select * from tarps", "title": "My favorite title", "chart": {"data": "hello"}}),
          AuthHelper.valid_jwt()
        )

      assert status_code == 201

      visualization = Visualizations.get_visualization_by_id(body.id) |> elem(1) |> Repo.preload(:owner)

      assert visualization.owner.subject_id == user.subject_id
    end

    test "returns 'unauthorized' when token is invalid" do
      %{status_code: status_code, body: body} =
        post_with_authentication(
          "localhost:4000/api/v1/visualization",
          ~s({"query": "select * from tarps", "title": "My favorite title"}),
          "!WRONG!"
        )

      assert status_code == 401
      assert body.message == "Unauthorized"
    end
  end

  describe "GET /visualization/:id" do
    setup do
      AuthHelper.auth0_setup()
      |> on_exit()
    end

    test "returns visualization for public table when user is anonymous",
         %{
           public_model_that_belongs_to_org_1: model
         } do
      capture_log(fn ->
        DiscoveryApi.prestige_opts()
        |> Prestige.new_session()
        |> Prestige.query(~s|create table if not exists "#{model.systemName}" (id integer, name varchar)|)
      end)

      visualization = create_visualization(model.systemName)

      %{status_code: status_code} =
        HTTPoison.get!(
          "localhost:4000/api/v1/visualization/#{visualization.public_id}",
          "Content-Type": "application/json"
        )

      assert status_code == 200
    end

    test "returns visualization for private table when user has access", %{
      private_model_that_belongs_to_org_1: model
    } do
      user = Helper.create_persisted_user(AuthHelper.valid_jwt_sub())
      Helper.associate_user_with_organization(user.id, model.organizationDetails.id)

      capture_log(fn ->
        DiscoveryApi.prestige_opts()
        |> Prestige.new_session()
        |> Prestige.query(~s|create table if not exists "#{model.systemName}" (id integer, name varchar)|)
      end)

      visualization = create_visualization(model.systemName)

      %{status_code: status_code} =
        get_with_authentication(
          "localhost:4000/api/v1/visualization/#{visualization.public_id}",
          AuthHelper.valid_jwt()
        )

      assert status_code == 200
    end

    test "returns not found for private table when user is anonymous", %{
      private_model_that_belongs_to_org_1: model
    } do
      capture_log(fn ->
        DiscoveryApi.prestige_opts()
        |> Prestige.new_session()
        |> Prestige.query(~s|create table if not exists "#{model.systemName}" (id integer, name varchar)|)
      end)

      DiscoveryApi.prestige_opts() |> Prestige.new_session() |> Prestige.query!("describe #{model.systemName}") |> Prestige.Result.as_maps()

      visualization = create_visualization(model.systemName)

      %{status_code: status_code} =
        HTTPoison.get!(
          "localhost:4000/api/v1/visualization/#{visualization.public_id}",
          "Content-Type": "application/json"
        )

      assert status_code == 404
    end
  end

  defp create_visualization(table_name) do
    owner = Helper.create_persisted_user("me|you")
    {:ok, owner_with_orgs} = Users.get_user_with_organizations(owner.id)

    {:ok, visualization} =
      Visualizations.create_visualization(%{
        query: "select * from #{table_name}",
        title: "My first visualization",
        owner: owner_with_orgs
      })

    visualization
  end

  defp post_with_authentication(url, body, bearer_token) do
    %{
      status_code: status_code,
      body: body_json
    } =
      HTTPoison.post!(
        url,
        body,
        Authorization: "Bearer #{bearer_token}",
        "Content-Type": "application/json"
      )

    %{status_code: status_code, body: Jason.decode!(body_json, keys: :atoms)}
  end

  defp get_with_authentication(url, bearer_token) do
    %{
      status_code: status_code,
      body: body_json
    } =
      HTTPoison.get!(
        url,
        Authorization: "Bearer #{bearer_token}",
        "Content-Type": "application/json"
      )

    %{status_code: status_code, body: Jason.decode!(body_json, keys: :atoms)}
  end
end

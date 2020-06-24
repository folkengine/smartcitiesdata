defmodule DiscoveryApi.Repo.Migrations.AddDatasetsField do
  use Ecto.Migration

  def change do
    alter table(:visualizations) do
      add(:datasets, {:array, :string}, null: true)
    end
  end
end

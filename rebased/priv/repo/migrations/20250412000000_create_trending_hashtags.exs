defmodule Pleroma.Repo.Migrations.CreateTrendingHashtags do
  use Ecto.Migration

  def change do
    create table(:trending_hashtags) do
      add :name, :string, null: false
      add :url, :string, null: false
      add :count, :integer, null: false
      add :account_count, :integer
      add :score, :float, null: false
      add :history, {:array, :map}, default: []

      timestamps()
    end

    create unique_index(:trending_hashtags, [:name])
  end
end
defmodule Pleroma.Repo.Migrations.CreateHashtagsTable do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:hashtags, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :count, :integer
      add :account_count, :integer
      add :history, :map

      timestamps()
    end

    create_if_not_exists index(:hashtags, [:name], unique: true)
  end
end
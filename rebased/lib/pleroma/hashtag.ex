# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Hashtag do
  @moduledoc """
  Schema per memorizzare gli hashtag di tendenza.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @derive {Jason.Encoder, only: [:id, :name, :count, :account_count, :history]}
  schema "hashtags" do
    field(:name, :string)
    field(:count, :integer)
    field(:account_count, :integer)
    field(:history, :map)

    timestamps()
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:name, :count, :account_count, :history])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end

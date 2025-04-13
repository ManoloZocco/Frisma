defmodule Pleroma.TrendingHashtag do
  use Ecto.Schema
  import Ecto.Changeset
  
  schema "trending_hashtags" do
    field :name, :string
    field :url, :string
    field :count, :integer
    field :account_count, :integer
    field :score, :float
    field :history, {:array, :map}, default: []
    
    timestamps()
  end
  
  def changeset(trending_hashtag, attrs) do
    trending_hashtag
    |> cast(attrs, [:name, :url, :count, :account_count, :score, :history])
    |> validate_required([:name, :url, :count, :score])
    |> unique_constraint(:name)
  end
  
  @doc """
  Salva i trending hashtags nel database
  """
  def store_trending_hashtags(hashtags) do
    Enum.each(hashtags, fn hashtag ->
      case Pleroma.Repo.get_by(__MODULE__, name: hashtag.name) do
        nil ->
          %__MODULE__{}
          |> changeset(hashtag)
          |> Pleroma.Repo.insert!()
          
        existing ->
          existing
          |> changeset(hashtag)
          |> Pleroma.Repo.update!()
      end
    end)
  end
  
  @doc """
  Recupera i trending hashtags dal database
  """
  def get_trending_hashtags(limit \\ 10) do
    Pleroma.Repo.all(
      from t in __MODULE__,
      order_by: [desc: t.score],
      limit: ^limit,
      select: %{
        name: t.name,
        url: t.url,
        count: t.count,
        account_count: t.account_count,
        score: t.score,
        history: t.history
      }
    )
  end
end
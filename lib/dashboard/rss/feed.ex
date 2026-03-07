defmodule Dashboard.RSS.Feed do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "feed" do
    field :title, :string
    field :description, :string
    field :author, :string
    field :url, :string
    field :link, :string
    field :last_modified, :string
    field :etag, :string
    field :next_fetch, :naive_datetime
    field :favicon, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(feed, attrs) do
    feed
    |> cast(attrs, [
      :title,
      :description,
      :author,
      :url,
      :link,
      :last_modified,
      :etag,
      :next_fetch,
      :favicon
    ])
    |> validate_required([:title, :url])
    |> unique_constraint(:url)
  end
end

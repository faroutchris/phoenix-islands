defmodule Dashboard.RSS.Feed do
  use Ecto.Schema
  import Ecto.Changeset

  alias Dashboard.RSS.FeedEntry

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
    field :next_fetch, :utc_datetime
    field :favicon, :string

    # Polling state
    field :canonical_url, :string
    field :content_hash, :string
    field :status, Ecto.Enum, values: [:active, :dormant, :suspended], default: :active
    field :suspension_reason, :string
    field :last_http_status, :integer
    field :last_fetched_at, :utc_datetime
    field :last_new_item_at, :utc_datetime
    field :miss_count, :integer, default: 0
    field :error_count, :integer, default: 0
    field :observed_interval, :integer
    field :ttl, :integer

    has_many :entries, FeedEntry

    timestamps(type: :utc_datetime)
  end

  @cast_fields [
    :title,
    :description,
    :author,
    :url,
    :link,
    :last_modified,
    :etag,
    :next_fetch,
    :favicon,
    :canonical_url,
    :content_hash,
    :status,
    :suspension_reason,
    :last_http_status,
    :last_fetched_at,
    :last_new_item_at,
    :miss_count,
    :error_count,
    :observed_interval,
    :ttl
  ]

  @polling_fields [
    :next_fetch,
    :last_modified,
    :etag,
    :canonical_url,
    :content_hash,
    :status,
    :suspension_reason,
    :last_http_status,
    :last_fetched_at,
    :last_new_item_at,
    :miss_count,
    :error_count,
    :observed_interval,
    :ttl
  ]

  @doc false
  def changeset(feed, attrs) do
    feed
    |> cast(attrs, @cast_fields)
    |> validate_required([:title, :url])
    |> unique_constraint(:url)
  end

  @doc """
  Changeset for polling/scheduling updates only.
  Skips :title/:url validation so we can update scheduling
  fields without requiring content fields.
  """
  def polling_changeset(feed, attrs) do
    feed
    |> cast(attrs, @polling_fields)
  end
end

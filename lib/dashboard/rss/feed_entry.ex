defmodule Dashboard.RSS.FeedEntry do
  use Ecto.Schema
  import Ecto.Changeset

  alias Dashboard.RSS.Feed
  alias Dashboard.RSS.FeedEntryEnclosure

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "feed_entry" do
    field :identity_key, :string
    field :identity_hash, :string
    field :identity_source, :string
    field :guid, :string
    field :link, :string
    field :title, :string
    field :author, :string
    field :summary, :string
    field :content, :string
    field :published_at, :utc_datetime
    field :updated_at_feed, :utc_datetime
    field :first_seen_at, :utc_datetime
    field :last_seen_at, :utc_datetime

    belongs_to :feed, Feed
    has_many :enclosures, FeedEntryEnclosure

    timestamps(type: :utc_datetime)
  end

  @cast_fields [
    :feed_id,
    :identity_key,
    :identity_hash,
    :identity_source,
    :guid,
    :link,
    :title,
    :author,
    :summary,
    :content,
    :published_at,
    :updated_at_feed,
    :first_seen_at,
    :last_seen_at
  ]

  @required_fields [
    :feed_id,
    :identity_key,
    :identity_hash,
    :identity_source,
    :first_seen_at,
    :last_seen_at
  ]

  def changeset(feed_entry, attrs) do
    feed_entry
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> assoc_constraint(:feed)
    |> unique_constraint(:identity_hash, name: :feed_entry_feed_id_identity_hash_index)
  end
end

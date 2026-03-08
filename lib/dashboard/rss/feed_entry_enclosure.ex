defmodule Dashboard.RSS.FeedEntryEnclosure do
  use Ecto.Schema
  import Ecto.Changeset

  alias Dashboard.RSS.FeedEntry

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "feed_entry_enclosure" do
    field :url, :string
    field :media_type, :string
    field :length_bytes, :integer

    belongs_to :feed_entry, FeedEntry

    timestamps(type: :utc_datetime)
  end

  @cast_fields [:feed_entry_id, :url, :media_type, :length_bytes]
  @required_fields [:feed_entry_id, :url]

  def changeset(enclosure, attrs) do
    enclosure
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> assoc_constraint(:feed_entry)
    |> unique_constraint(:url, name: :feed_entry_enclosure_feed_entry_id_url_index)
  end
end

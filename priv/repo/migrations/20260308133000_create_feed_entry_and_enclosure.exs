defmodule Dashboard.Repo.Migrations.CreateFeedEntryAndEnclosure do
  use Ecto.Migration

  def change do
    create table(:feed_entry, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :feed_id, references(:feed, type: :binary_id, on_delete: :delete_all), null: false
      add :identity_key, :string, null: false
      add :identity_hash, :string, null: false
      add :identity_source, :string, null: false
      add :guid, :string
      add :link, :string
      add :title, :string
      add :author, :string
      add :summary, :string
      add :content, :string
      add :published_at, :utc_datetime
      add :updated_at_feed, :utc_datetime
      add :first_seen_at, :utc_datetime, null: false
      add :last_seen_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:feed_entry, [:feed_id, :identity_hash])
    create index(:feed_entry, [:published_at])
    create index(:feed_entry, [:last_seen_at])

    create table(:feed_entry_enclosure, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :feed_entry_id, references(:feed_entry, type: :binary_id, on_delete: :delete_all),
        null: false

      add :url, :string, null: false
      add :media_type, :string
      add :length_bytes, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:feed_entry_enclosure, [:feed_entry_id, :url])
    create index(:feed_entry_enclosure, [:media_type])
  end
end

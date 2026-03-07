defmodule Dashboard.Repo.Migrations.CreateFeed do
  use Ecto.Migration

  def change do
    create table(:feed, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :description, :string
      add :link, :string
      add :author, :string
      add :url, :string
      add :last_modified, :string
      add :etag, :string
      add :next_fetch, :naive_datetime
      add :favicon, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:feed, [:url])
  end
end

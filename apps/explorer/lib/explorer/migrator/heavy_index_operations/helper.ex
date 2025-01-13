defmodule Explorer.Migrator.HeavyIndexOperation.Helper do
  @moduledoc """
  Common functions for Explorer.Migrator.HeavyIndexOperation.* modules
  """

  require Logger

  alias Ecto.Adapters.SQL
  alias Explorer.Repo

  @doc """
  Checks the progress of DB index creation
  """
  @spec check_index_creation_progress(String.t()) ::
          :finished_or_not_started | :finished | :unknown | {:in_progress, String.t()}
  def check_index_creation_progress(index_name) do
    check_index_creation_progress = """
    SELECT
      now()::TIME(0),
      a.query,
      p.phase,
      round(p.blocks_done / p.blocks_total::numeric * 100, 2) AS "% done",
      p.blocks_total,
      p.blocks_done,
      p.tuples_total,
      p.tuples_done,
      ai.schemaname,
      ai.relname,
      ai.indexrelname
    FROM pg_stat_progress_create_index p
    JOIN pg_stat_activity a ON p.pid = a.pid
    LEFT JOIN pg_stat_all_indexes ai on ai.relid = p.relid AND ai.indexrelid = p.index_relid
    WHERE ai.relname = '#{index_name}';
    """

    case SQL.query(Repo, check_index_creation_progress, []) do
      {:ok, %Postgrex.Result{rows: []}} ->
        :finished_or_not_started

      {:ok, %Postgrex.Result{command: :select, columns: ["% done"], rows: [[percentage]]}} = result ->
        Logger.info("DB heavy index '#{index_name}' creation progress #{percentage}%")

        if percentage < 100 do
          {:in_progress, "#{percentage} %"}
        else
          :finished
        end

      {:error, error} ->
        Logger.error("Failed to check index '#{index_name}' creation progress: #{inspect(error)}")
        :unknown
    end
  end

  @doc """
  Checks index with the given name exists in the DB
  """
  @spec index_exists?(String.t()) :: boolean()

  def index_exists?(index_name) do
    check_index_exists_query = """
    SELECT EXISTS( SELECT 1
    FROM pg_class c
    WHERE c.relname = '#{index_name}'
    AND c.relkind = 'i');
    """

    case SQL.query(Repo, check_index_exists_query, []) do
      {:ok, %Postgrex.Result{columns: ["exists"], rows: [[true]]}} ->
        true

      {:ok, %Postgrex.Result{columns: ["exists"], rows: [[false]]}} ->
        false

      {:error, error} ->
        Logger.error("Failed to check index '#{index_name}' existence: #{inspect(error)}")
        :unknown
    end
  end
end

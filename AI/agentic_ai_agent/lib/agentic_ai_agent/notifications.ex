defmodule AgenticAiAgent.Notifications do
  @moduledoc """
  Operator-facing notification log + PubSub fanout.

  Autonomous components (today: `AgenticAiAgent.Improver.Scheduler`) call
  `emit/2` to record what they did. The `/notifications` LiveView lists
  them and lets the operator mark items read.

  Subscribe to `pubsub_topic/0` to receive `{:notification, :new,
  notification}` events for live UI updates.
  """

  import Ecto.Query

  alias AgenticAiAgent.Repo
  alias AgenticAiAgent.Notifications.Notification

  @topic "notifications"

  def pubsub_topic, do: @topic

  # ----- Write -----

  @doc """
  Persist a notification. `kind` and `subject` are required; `opts` may
  include any of `:body`, `:proposal_id`, `:run_id`, `:card_slug`.

  Broadcasts `{:notification, :new, notification}` on the `"notifications"`
  topic on success.
  """
  @spec emit(String.t(), keyword()) :: {:ok, Notification.t()} | {:error, Ecto.Changeset.t()}
  def emit(kind, opts) when is_binary(kind) and is_list(opts) do
    attrs =
      opts
      |> Map.new()
      |> Map.put(:kind, kind)
      |> Map.put_new(:subject, Keyword.get(opts, :subject, kind))

    result =
      %Notification{}
      |> Notification.changeset(attrs)
      |> Repo.insert()

    with {:ok, notif} <- result do
      Phoenix.PubSub.broadcast(AgenticAiAgent.PubSub, @topic, {:notification, :new, notif})
    end

    result
  rescue
    e -> {:error, Exception.message(e)}
  end

  # ----- Read -----

  @spec list(keyword()) :: [Notification.t()]
  def list(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    unread_only? = Keyword.get(opts, :unread_only, false)

    Notification
    |> maybe_unread(unread_only?)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_unread(q, false), do: q
  defp maybe_unread(q, true), do: where(q, [n], is_nil(n.read_at))

  def get!(id), do: Repo.get!(Notification, id)

  def unread_count do
    from(n in Notification, where: is_nil(n.read_at))
    |> Repo.aggregate(:count, :id)
  end

  # ----- Mark read -----

  def mark_read!(%Notification{read_at: nil} = n) do
    n
    |> Notification.changeset(%{read_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update!()
  end

  def mark_read!(%Notification{} = n), do: n

  def mark_all_read! do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {n, _} =
      Notification
      |> where([n], is_nil(n.read_at))
      |> Repo.update_all(set: [read_at: now])

    n
  end
end

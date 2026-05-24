defmodule AgenticAiAgent.NotificationsTest do
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.Notifications

  describe "emit/2" do
    test "persists kind/subject and defaults body to nil" do
      assert {:ok, n} = Notifications.emit("auto_promote", subject: "Promoted default")
      assert n.kind == "auto_promote"
      assert n.subject == "Promoted default"
      assert n.body == nil
      assert n.read_at == nil
    end

    test "broadcasts {:notification, :new, _} on the topic" do
      Phoenix.PubSub.subscribe(AgenticAiAgent.PubSub, Notifications.pubsub_topic())

      {:ok, _} = Notifications.emit("dry_run", subject: "test", body: "would do X")

      assert_receive {:notification, :new, %{kind: "dry_run", subject: "test"}}, 500
    end

    test "stores optional refs" do
      {:ok, n} =
        Notifications.emit("auto_rollback",
          subject: "Reverted",
          body: "Reason X",
          proposal_id: "abc",
          card_slug: "default",
          run_id: "r1"
        )

      assert n.proposal_id == "abc"
      assert n.card_slug == "default"
      assert n.run_id == "r1"
    end
  end

  describe "list / unread_count / mark_read" do
    test "list filters by unread_only" do
      {:ok, n1} = Notifications.emit("dry_run", subject: "1")
      {:ok, _n2} = Notifications.emit("dry_run", subject: "2")

      assert length(Notifications.list()) == 2
      assert Notifications.unread_count() == 2

      _ = Notifications.mark_read!(n1)

      assert Notifications.unread_count() == 1
      assert length(Notifications.list(unread_only: true)) == 1
    end

    test "mark_all_read! flips every unread row and returns the count" do
      {:ok, _} = Notifications.emit("dry_run", subject: "a")
      {:ok, _} = Notifications.emit("dry_run", subject: "b")
      {:ok, _} = Notifications.emit("dry_run", subject: "c")

      assert Notifications.unread_count() == 3
      assert 3 = Notifications.mark_all_read!()
      assert Notifications.unread_count() == 0
    end

    test "mark_read! is idempotent for already-read rows" do
      {:ok, n} = Notifications.emit("dry_run", subject: "x")
      read_once = Notifications.mark_read!(n)
      read_twice = Notifications.mark_read!(read_once)
      # Same row, same read_at — the second call is a no-op pass-through.
      assert read_once.id == read_twice.id
      assert read_once.read_at == read_twice.read_at
    end
  end
end

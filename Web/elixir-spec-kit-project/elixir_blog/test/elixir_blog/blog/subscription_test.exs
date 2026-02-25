defmodule ElixirBlog.Blog.SubscriptionTest do
  use ElixirBlog.DataCase

  alias ElixirBlog.Blog.Subscription

  @valid_attrs %{
    email: "test@example.com"
  }

  @invalid_attrs %{}

  describe "changeset/2" do
    test "valid changeset with valid email" do
      changeset = Subscription.changeset(%Subscription{}, @valid_attrs)
      assert changeset.valid?
    end

    test "invalid changeset when email is missing" do
      changeset = Subscription.changeset(%Subscription{}, @invalid_attrs)
      refute changeset.valid?
      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email format rejects invalid format" do
      invalid_emails = [
        "invalid",
        "invalid@",
        "@example.com",
        "invalid@example",
        "invalid @example.com",
        "invalid@example .com"
      ]

      for invalid_email <- invalid_emails do
        changeset = Subscription.changeset(%Subscription{}, %{email: invalid_email})
        refute changeset.valid?, "Expected #{invalid_email} to be invalid"
        assert %{email: ["has invalid format"]} = errors_on(changeset)
      end
    end

    test "validates email format accepts valid emails" do
      valid_emails = [
        "user@example.com",
        "user.name@example.com",
        "user+tag@example.co.kr",
        "user123@subdomain.example.com"
      ]

      for valid_email <- valid_emails do
        changeset = Subscription.changeset(%Subscription{}, %{email: valid_email})
        assert changeset.valid?, "Expected #{valid_email} to be valid"
      end
    end

    test "validates email length maximum" do
      long_email = String.duplicate("a", 245) <> "@example.com"
      changeset = Subscription.changeset(%Subscription{}, %{email: long_email})
      refute changeset.valid?
      assert %{email: ["should be at most 255 character(s)"]} = errors_on(changeset)
    end

    test "automatically sets subscribed_at when not provided" do
      changeset = Subscription.changeset(%Subscription{}, @valid_attrs)
      assert changeset.valid?
      assert get_change(changeset, :subscribed_at) != nil
    end

    test "sets subscribed_at to a recent time" do
      before_time = DateTime.utc_now()
      changeset = Subscription.changeset(%Subscription{}, @valid_attrs)
      after_time = DateTime.utc_now()

      subscribed_at = get_change(changeset, :subscribed_at)
      assert DateTime.compare(subscribed_at, before_time) in [:gt, :eq]
      assert DateTime.compare(subscribed_at, after_time) in [:lt, :eq]
    end

    test "subscribed_at is a UTC datetime" do
      changeset = Subscription.changeset(%Subscription{}, @valid_attrs)
      subscribed_at = get_change(changeset, :subscribed_at)
      assert %DateTime{} = subscribed_at
    end
  end
end

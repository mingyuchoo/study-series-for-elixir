defmodule AgenticAiAgent.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  alias AgenticAiAgentWeb.AgentProfiles
  alias AgenticAiAgentWeb.Locale

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @themes ~w(system light dark)
  @avatar_upload_prefix "/uploads/profiles/"
  @avatar_upload_extensions ~w(.gif .jpeg .jpg .png .webp)

  schema "users" do
    field :email, :string
    field :display_name, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true
    field :avatar_path, :string
    field :preferred_locale, :string, default: "en"
    field :preferred_theme, :string, default: "system"

    timestamps(type: :utc_datetime)
  end

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :email,
      :display_name,
      :password,
      :avatar_path,
      :preferred_locale,
      :preferred_theme
    ])
    |> normalize_email()
    |> default_display_name()
    |> default_avatar_path()
    |> default_preferences()
    |> validate_required([
      :email,
      :display_name,
      :password,
      :avatar_path,
      :preferred_locale,
      :preferred_theme
    ])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> validate_length(:email, max: 160)
    |> validate_length(:display_name, min: 2, max: 80)
    |> validate_length(:password, min: 8, max: 72)
    |> validate_avatar_path()
    |> validate_preferences()
    |> unique_constraint(:email)
    |> put_password_hash()
  end

  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name, :avatar_path, :preferred_locale, :preferred_theme])
    |> default_avatar_path()
    |> default_preferences()
    |> validate_required([:display_name, :avatar_path, :preferred_locale, :preferred_theme])
    |> validate_length(:display_name, min: 2, max: 80)
    |> validate_avatar_path()
    |> validate_preferences()
  end

  def preferences_changeset(user, attrs) do
    user
    |> cast(attrs, [:preferred_locale, :preferred_theme])
    |> default_preferences()
    |> validate_required([:preferred_locale, :preferred_theme])
    |> validate_preferences()
  end

  defp normalize_email(changeset) do
    update_change(changeset, :email, fn email ->
      email |> String.trim() |> String.downcase()
    end)
  end

  defp default_display_name(changeset) do
    case get_field(changeset, :display_name) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          default_display_name_from_email(changeset)
        else
          update_change(changeset, :display_name, &String.trim/1)
        end

      _ ->
        default_display_name_from_email(changeset)
    end
  end

  defp default_display_name_from_email(changeset) do
    case get_field(changeset, :email) do
      email when is_binary(email) -> put_change(changeset, :display_name, email_name(email))
      _ -> changeset
    end
  end

  defp default_avatar_path(changeset) do
    case get_field(changeset, :avatar_path) do
      path when is_binary(path) and path != "" -> changeset
      _ -> put_change(changeset, :avatar_path, AgentProfiles.paths() |> List.first())
    end
  end

  defp default_preferences(changeset) do
    changeset
    |> default_preference(:preferred_locale, Locale.default())
    |> default_preference(:preferred_theme, "system")
  end

  defp default_preference(changeset, field, default) do
    case get_field(changeset, field) do
      value when is_binary(value) and value != "" -> changeset
      _ -> put_change(changeset, field, default)
    end
  end

  defp validate_avatar_path(changeset) do
    validate_change(changeset, :avatar_path, fn :avatar_path, path ->
      if AgentProfiles.valid_path?(path) or valid_uploaded_avatar_path?(path) do
        []
      else
        [avatar_path: "is not an available profile image"]
      end
    end)
  end

  defp valid_uploaded_avatar_path?(path) when is_binary(path) do
    filename = String.replace_prefix(path, @avatar_upload_prefix, "")

    String.starts_with?(path, @avatar_upload_prefix) and
      filename == Path.basename(filename) and
      String.downcase(Path.extname(filename)) in @avatar_upload_extensions
  end

  defp valid_uploaded_avatar_path?(_), do: false

  defp validate_preferences(changeset) do
    changeset
    |> validate_inclusion(:preferred_locale, Locale.supported())
    |> validate_inclusion(:preferred_theme, @themes)
  end

  defp put_password_hash(changeset) do
    case get_change(changeset, :password) do
      password when is_binary(password) ->
        put_change(changeset, :password_hash, AgenticAiAgent.Accounts.hash_password(password))

      _ ->
        changeset
    end
  end

  defp email_name(email), do: email |> String.split("@") |> List.first()
end

---
title: "파일 업로드 및 처리"
author: "윤서연"
tags: ["file-handling", "web-dev", "storage"]
thumbnail: "/images/thumbnails/file-handling.jpg"
summary: "Phoenix에서 파일 업로드, 검증, 저장을 안전하게 처리하는 방법을 배웁니다."
published_at: 2024-06-15T11:30:00Z
is_popular: true
---

파일 처리는 웹 애플리케이션의 중요한 기능입니다. 안전하고 효율적인 파일 처리를 알아봅시다.

## 파일 업로드 폼

```elixir
# lib/myapp_web/live/upload_live.ex
defmodule MyappWeb.UploadLive do
  use MyappWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:uploaded_files, [])
     |> allow_upload(:avatar,
       accept: ~w(.jpg .jpeg .png),
       max_entries: 3,
       max_file_size: 9_000_000
     )}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("save", _params, socket) do
    uploaded_files =
      consume_uploaded_entries(socket, :avatar, fn %{path: path}, _entry ->
        case File.read(path) do
          {:ok, file_content} ->
            {:ok, url} = store_file(file_content)
            url
          {:error, _} ->
            {:error, "Failed to read file"}
        end
      end)

    {:noreply, assign(socket, :uploaded_files, uploaded_files)}
  end

  defp store_file(file_content) do
    filename = UUID.uuid4() <> ".jpg"
    path = "priv/static/uploads/#{filename}"
    File.write(path, file_content)
    {:ok, "/uploads/#{filename}"}
  end

  def render(assigns) do
    ~H"""
    <form phx-change="validate" phx-submit="save">
      <.live_file_input upload={@uploads.avatar} />
      <button type="submit">Upload</button>
    </form>

    <div>
      <%= for file <- @uploaded_files do %>
        <img src={file} />
      <% end %>
    </div>
    """
  end
end
```

## S3 통합

```elixir
# lib/myapp/storage/s3.ex
defmodule Myapp.Storage.S3 do
  def upload_file(file_path, destination_key) do
    case File.read(file_path) do
      {:ok, file_content} ->
        upload_to_s3(file_content, destination_key)
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp upload_to_s3(file_content, destination_key) do
    bucket = Application.get_env(:myapp, :s3_bucket)

    case ExAws.S3.put_object(bucket, destination_key, file_content)
         |> ExAws.request() do
      {:ok, _} -> {:ok, "https://#{bucket}.s3.amazonaws.com/#{destination_key}"}
      {:error, reason} -> {:error, reason}
    end
  end

  def delete_file(destination_key) do
    bucket = Application.get_env(:myapp, :s3_bucket)

    ExAws.S3.delete_object(bucket, destination_key)
    |> ExAws.request()
  end

  def get_signed_url(destination_key, expires_in \\ 3600) do
    bucket = Application.get_env(:myapp, :s3_bucket)

    ExAws.S3.presigned_url(:get, bucket, destination_key, expires_in: expires_in)
  end
end
```

## 파일 검증

```elixir
defmodule FileValidator do
  @allowed_types %{
    image: ["image/jpeg", "image/png", "image/gif"],
    document: ["application/pdf", "application/msword"],
    video: ["video/mp4", "video/quicktime"]
  }

  @max_sizes %{
    image: 10_000_000,      # 10MB
    document: 50_000_000,   # 50MB
    video: 500_000_000      # 500MB
  }

  def validate_image(file_path) do
    with {:ok, mime_type} <- get_mime_type(file_path),
         true <- mime_type in @allowed_types.image,
         {:ok, size} <- get_file_size(file_path),
         true <- size <= @max_sizes.image do
      :ok
    else
      false -> {:error, "Invalid file type or size"}
      {:error, reason} -> {:error, reason}
    end
  end

  def validate_document(file_path) do
    with {:ok, mime_type} <- get_mime_type(file_path),
         true <- mime_type in @allowed_types.document,
         {:ok, size} <- get_file_size(file_path),
         true <- size <= @max_sizes.document do
      :ok
    else
      false -> {:error, "Invalid file type or size"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_mime_type(file_path) do
    case File.stat(file_path) do
      {:ok, _} -> {:ok, MIME.from_path(file_path)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_file_size(file_path) do
    case File.stat(file_path) do
      {:ok, %{size: size}} -> {:ok, size}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

## 이미지 처리

```elixir
defmodule ImageProcessor do
  def resize_image(input_path, output_path, width, height) do
    case Mogrify.open(input_path)
         |> Mogrify.resize("#{width}x#{height}")
         |> Mogrify.save(path: output_path) do
      %Mogrify.Image{} -> {:ok, output_path}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_thumbnail(input_path, output_path) do
    resize_image(input_path, output_path, 200, 200)
  end

  def optimize_image(input_path) do
    case Mogrify.open(input_path)
         |> Mogrify.quality(85)
         |> Mogrify.save(in_place: true) do
      %Mogrify.Image{} -> {:ok, input_path}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

## 파일 다운로드

```elixir
defmodule MyappWeb.FileController do
  def download(conn, %{"id" => id}) do
    file = Repo.get!(File, id)

    case get_file_path(file) do
      {:ok, path} ->
        conn
        |> put_resp_header("content-type", file.mime_type)
        |> put_resp_header(
          "content-disposition",
          "attachment; filename=\"#{file.name}\""
        )
        |> send_file(200, path)
      {:error, _reason} ->
        send_resp(conn, 404, "File not found")
    end
  end

  defp get_file_path(file) do
    path = "priv/files/#{file.storage_key}"

    case File.exists?(path) do
      true -> {:ok, path}
      false -> {:error, "File not found"}
    end
  end
end
```

## 결론

안전한 파일 처리는 애플리케이션의 보안과 사용자 경험을 보장합니다. 파일 검증, 저장소 관리, 접근 제어를 통해 안정적인 파일 처리 시스템을 구축할 수 있습니다.
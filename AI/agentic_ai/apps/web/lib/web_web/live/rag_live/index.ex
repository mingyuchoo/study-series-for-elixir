defmodule WebWeb.RagLive.Index do
  use WebWeb, :live_view

  alias Core.Contexts.VectorRags
  alias Core.Schema.VectorRag

  @max_upload_size 20_000_000
  @accepted_extensions ~w(.txt .md .json .csv .log .pdf .docx)

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_rags()
      |> assign(:form, to_form(VectorRags.change_vector_rag(%VectorRag{})))
      |> assign(:uploading, false)
      |> allow_upload(:document,
        accept: @accepted_extensions,
        max_entries: 1,
        max_file_size: @max_upload_size
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"vector_rag" => params}, socket) do
    changeset =
      %VectorRag{}
      |> VectorRags.change_vector_rag(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :document, ref)}
  end

  @impl true
  def handle_event("save", %{"vector_rag" => params}, socket) do
    entries = socket.assigns.uploads.document.entries

    if Enum.empty?(entries) do
      {:noreply, put_flash(socket, :error, "업로드할 문서를 선택하세요.")}
    else
      [entry | _] = entries

      result =
        consume_uploaded_entries(socket, :document, fn %{path: path}, consumed_entry ->
          source = %{path: path, client_name: consumed_entry.client_name}
          {:ok, VectorRags.create_vector_rag(params, source)}
        end)
        |> List.first()

      case result do
        {:ok, _rag} ->
          {:noreply,
           socket
           |> assign_rags()
           |> assign(:form, to_form(VectorRags.change_vector_rag(%VectorRag{})))
           |> put_flash(:info, "#{entry.client_name} 문서로 Vector RAG를 생성했습니다.")}

        {:error, :empty_document} ->
          {:noreply, put_flash(socket, :error, "문서에서 인덱싱할 텍스트를 찾지 못했습니다.")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset))}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Vector RAG 생성 실패: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    rag = VectorRags.get_vector_rag!(id)
    {:ok, _} = VectorRags.delete_vector_rag(rag)

    {:noreply,
     socket
     |> assign_rags()
     |> put_flash(:info, "Vector RAG가 삭제되었습니다.")}
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    rag = VectorRags.get_vector_rag!(id)
    {:ok, _} = VectorRags.update_vector_rag(rag, %{enabled: !rag.enabled})
    {:noreply, assign_rags(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-full bg-base-100">
      <section class="border-b border-base-300 bg-base-100">
        <div class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
          <div class="max-w-3xl">
            <p class="text-sm text-base-content/60">Admin / RAG</p>
            <h1 class="mt-3 text-4xl font-light leading-tight text-base-content">
              Vector RAG 관리
            </h1>
            <p class="mt-3 text-sm leading-6 text-base-content/70">
              문서를 업로드하면 텍스트 청크를 만들고 HNSWLib 인덱스로 검색 가능한 지식을 구성합니다.
            </p>
          </div>
        </div>
      </section>

      <section class="mx-auto grid max-w-7xl gap-6 px-4 py-6 sm:px-6 lg:grid-cols-[420px_1fr] lg:px-8">
        <div class="border border-base-300 bg-base-100 p-5">
          <h2 class="text-lg font-normal">새 Vector RAG</h2>

          <.form
            for={@form}
            class="mt-5 space-y-4"
            phx-change="validate"
            phx-submit="save"
          >
            <.input
              field={@form[:name]}
              type="text"
              label="이름"
              placeholder="예: product_docs"
              required
            />

            <.input
              field={@form[:description]}
              type="textarea"
              label="설명"
              rows="3"
              class="w-full textarea"
            />

            <.input field={@form[:enabled]} type="checkbox" label="활성화" />

            <div>
              <label class="block text-sm font-medium mb-2">문서</label>
              <.live_file_input
                upload={@uploads.document}
                class="file-input file-input-bordered w-full"
              />
              <div class="mt-2 space-y-2">
                <div :for={entry <- @uploads.document.entries} class="border border-base-300 p-3">
                  <div class="flex items-start justify-between gap-3">
                    <div class="min-w-0">
                      <div class="truncate text-sm font-medium">{entry.client_name}</div>
                      <div class="text-xs text-base-content/60">
                        {format_bytes(entry.client_size)}
                      </div>
                    </div>
                    <button
                      type="button"
                      class="btn btn-ghost btn-xs text-error"
                      phx-click="cancel_upload"
                      phx-value-ref={entry.ref}
                    >
                      취소
                    </button>
                  </div>
                  <progress
                    class="progress progress-primary mt-2 w-full"
                    value={entry.progress}
                    max="100"
                  >
                    {entry.progress}%
                  </progress>
                  <p
                    :for={err <- upload_errors(@uploads.document, entry)}
                    class="mt-1 text-xs text-error"
                  >
                    {upload_error(err)}
                  </p>
                </div>
              </div>
              <p :for={err <- upload_errors(@uploads.document)} class="mt-2 text-xs text-error">
                {upload_error(err)}
              </p>
            </div>

            <button type="submit" phx-disable-with="생성 중..." class="btn btn-primary w-full">
              Vector RAG 생성
            </button>
          </.form>
        </div>

        <div>
          <div class="grid gap-px border border-base-300 bg-base-300 sm:grid-cols-3">
            <.summary_tile label="전체 지식" value={@summary.total} />
            <.summary_tile label="활성" value={@summary.enabled} />
            <.summary_tile label="총 청크" value={@summary.chunks} />
          </div>

          <div class="mt-6 hidden border border-base-300 bg-base-100 md:block">
            <table class="table table-fixed w-full">
              <thead>
                <tr>
                  <th class="w-[22%] text-xs font-semibold uppercase text-base-content/60">이름</th>
                  <th class="w-[26%] text-xs font-semibold uppercase text-base-content/60">문서</th>
                  <th class="w-[12%] text-xs font-semibold uppercase text-base-content/60">청크</th>
                  <th class="w-[14%] text-xs font-semibold uppercase text-base-content/60">상태</th>
                  <th class="w-[10%] text-xs font-semibold uppercase text-base-content/60">활성화</th>
                  <th class="w-[16%] text-xs font-semibold uppercase text-base-content/60">작업</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={rag <- @rags} class="border-t border-base-300">
                  <td class="align-top">
                    <div class="break-words text-xs font-semibold">{rag.name}</div>
                    <div :if={rag.description} class="mt-1 break-words text-xs text-base-content/60">
                      {rag.description}
                    </div>
                  </td>
                  <td class="align-top text-xs break-words text-base-content/70">
                    {rag.source_filename || "-"}
                  </td>
                  <td class="align-top text-xs">{rag.chunk_count}</td>
                  <td class="align-top">
                    <span class={[
                      "badge badge-sm gap-1 h-auto min-h-5 text-xs font-normal",
                      status_badge(rag.status)
                    ]}>
                      <span class={["status", status_dot(rag.status)]} />
                      {status_label(rag.status)}
                    </span>
                  </td>
                  <td class="align-top">
                    <input
                      type="checkbox"
                      class="toggle toggle-sm"
                      checked={rag.enabled}
                      phx-click="toggle"
                      phx-value-id={rag.id}
                      aria-label="Vector RAG 활성화"
                    />
                  </td>
                  <td class="align-top">
                    <button
                      phx-click="delete"
                      phx-value-id={rag.id}
                      data-confirm="삭제하시겠습니까?"
                      class="btn btn-ghost btn-xs text-error"
                    >
                      삭제
                    </button>
                  </td>
                </tr>
                <tr :if={@rags == []}>
                  <td colspan="6" class="py-10 text-center text-xs text-base-content/50">
                    등록된 Vector RAG가 없습니다.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div class="mt-6 space-y-3 md:hidden">
            <div :for={rag <- @rags} class="border border-base-300 bg-base-100 p-4">
              <div class="flex items-start justify-between gap-3">
                <div class="min-w-0">
                  <div class="break-words text-xs font-semibold">{rag.name}</div>
                  <div class="mt-1 break-words text-xs text-base-content/60">
                    {rag.source_filename || "-"} · {rag.chunk_count} chunks
                  </div>
                </div>
                <input
                  type="checkbox"
                  class="toggle toggle-sm shrink-0"
                  checked={rag.enabled}
                  phx-click="toggle"
                  phx-value-id={rag.id}
                  aria-label="Vector RAG 활성화"
                />
              </div>
              <div class="mt-3 flex items-center justify-between gap-3">
                <span class={[
                  "badge badge-sm gap-1 h-auto min-h-5 text-xs font-normal",
                  status_badge(rag.status)
                ]}>
                  <span class={["status", status_dot(rag.status)]} />
                  {status_label(rag.status)}
                </span>
                <button
                  phx-click="delete"
                  phx-value-id={rag.id}
                  data-confirm="삭제하시겠습니까?"
                  class="btn btn-ghost btn-xs text-error"
                >
                  삭제
                </button>
              </div>
            </div>

            <div
              :if={@rags == []}
              class="border border-base-300 bg-base-100 py-10 text-center text-xs text-base-content/50"
            >
              등록된 Vector RAG가 없습니다.
            </div>
          </div>
        </div>
      </section>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp summary_tile(assigns) do
    ~H"""
    <div class="bg-base-100 p-4">
      <div class="text-xs text-base-content/60">{@label}</div>
      <div class="mt-4 text-4xl font-light leading-none">{@value}</div>
    </div>
    """
  end

  defp assign_rags(socket) do
    rags = VectorRags.list_vector_rags_with_status()

    socket
    |> assign(:rags, rags)
    |> assign(:summary, %{
      total: length(rags),
      enabled: Enum.count(rags, & &1.enabled),
      chunks: Enum.reduce(rags, 0, &(&1.chunk_count + &2))
    })
  end

  defp status_badge(:ready), do: "badge-success"
  defp status_badge(:missing_index), do: "badge-error"
  defp status_badge(:disabled), do: "badge-ghost"
  defp status_badge(_), do: "badge-ghost"

  defp status_dot(:ready), do: "status-success"
  defp status_dot(:missing_index), do: "status-error"
  defp status_dot(:disabled), do: "status-neutral"
  defp status_dot(_), do: "status-neutral"

  defp status_label(:ready), do: "사용 가능"
  defp status_label(:missing_index), do: "인덱스 없음"
  defp status_label(:disabled), do: "비활성"
  defp status_label(_), do: "비어 있음"

  defp format_bytes(nil), do: "?"
  defp format_bytes(b) when b < 1024, do: "#{b} B"
  defp format_bytes(b) when b < 1_048_576, do: "#{Float.round(b / 1024, 1)} KB"
  defp format_bytes(b), do: "#{Float.round(b / 1_048_576, 1)} MB"

  defp upload_error(:too_large), do: "파일이 너무 큽니다."
  defp upload_error(:too_many_files), do: "파일은 1개만 업로드할 수 있습니다."
  defp upload_error(:not_accepted), do: "지원하지 않는 파일 형식입니다."
  defp upload_error(error), do: inspect(error)
end

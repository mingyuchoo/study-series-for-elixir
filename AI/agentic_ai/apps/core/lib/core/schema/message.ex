defmodule Core.Schema.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messages" do
    field(:role, Ecto.Enum, values: [:system, :user, :assistant, :tool])
    field(:content, :string)
    field(:tool_calls, {:array, :map}, default: [])
    field(:tool_call_id, :string)
    field(:tokens_used, :integer)
    field(:attachments, {:array, :map}, default: [])

    # 메시지 가시성:
    #   :user_facing — 사용자 메시지. 화면에 보이고 LLM 컨텍스트에 포함됨.
    #   :debate_turn — 그룹 채팅 중 모더레이터 결정 또는 워커 발화.
    #                   화면에 보이지만 다음 턴 LLM 컨텍스트에선 제외 (노이즈 방지).
    #   :final       — 최종 답변. 화면에 보이고 다음 턴 LLM 컨텍스트에 포함됨.
    field(:visibility, Ecto.Enum,
      values: [:user_facing, :debate_turn, :final],
      default: :user_facing
    )

    belongs_to(:conversation, Core.Schema.Conversation)
    belongs_to(:agent, Core.Schema.Agent)
    belongs_to(:agent_task, Core.Schema.AgentTask)

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :role,
      :content,
      :tool_calls,
      :tool_call_id,
      :tokens_used,
      :attachments,
      :visibility,
      :conversation_id,
      :agent_id,
      :agent_task_id
    ])
    |> validate_required([:role, :content, :conversation_id, :visibility])
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:agent_task_id)
  end
end

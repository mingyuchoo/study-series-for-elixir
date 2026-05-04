defmodule Core.Repo.Migrations.RenameEmojiWorkerToSystemWorker do
  use Ecto.Migration

  def up do
    old_name = "emoji" <> "_worker"
    new_name = "system_worker"
    new_display_name = "System Worker"
    new_description = "최종 답변이 시스템 지침, 안전 기준, 표현 일관성을 준수하도록 점검하고 다듬는 Worker"
    new_markdown_path = "config/agents/worker_system.md"

    new_config =
      ~s({"enforce_system_guidelines":true,"preserve_worker_facts":true,"max_review_notes":3})

    execute("""
    UPDATE agents
    SET name = '#{new_name}',
        display_name = '#{new_display_name}',
        description = '#{new_description}',
        temperature = 0.4,
        config = '#{new_config}',
        markdown_path = '#{new_markdown_path}'
    WHERE name = '#{old_name}'
      AND NOT EXISTS (SELECT 1 FROM agents WHERE name = '#{new_name}')
    """)
  end

  def down do
    old_name = "emoji" <> "_worker"
    new_name = "system_worker"
    old_display_name = "Emoji" <> " Worker"
    old_description = "답변에 적절한 이모" <> "지를 추가하여 가독성과 친근감을 높이는 Worker"
    old_markdown_path = "config/agents/worker_" <> "emoji.md"

    old_config =
      "{" <>
        ~s("emoji) <>
        ~s(_density":"moderate",) <>
        ~s("prefer_unicode_) <>
        ~s(emoji":true,) <>
        ~s("max_) <>
        ~s(emoji) <>
        ~s(_per_paragraph":3) <>
        "}"

    execute("""
    UPDATE agents
    SET name = '#{old_name}',
        display_name = '#{old_display_name}',
        description = '#{old_description}',
        temperature = 0.8,
        config = '#{old_config}',
        markdown_path = '#{old_markdown_path}'
    WHERE name = '#{new_name}'
      AND NOT EXISTS (SELECT 1 FROM agents WHERE name = '#{old_name}')
    """)
  end
end

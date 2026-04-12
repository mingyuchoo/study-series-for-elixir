---
title: "데이터 마이그레이션 전략"
author: "박민수"
tags: ["database", "migration", "devops"]
thumbnail: "/images/thumbnails/data-migration.jpg"
summary: "안전한 데이터 마이그레이션과 스키마 변경을 관리하는 방법을 배웁니다."
published_at: 2024-07-15T13:00:00Z
is_popular: true
---

데이터 마이그레이션은 주의 깊게 계획하고 실행해야 합니다. 안전한 마이그레이션 전략을 알아봅시다.

## Ecto 마이그레이션

```elixir
# priv/repo/migrations/20240715_add_status_to_posts.exs
defmodule MyApp.Repo.Migrations.AddStatusToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :status, :string, default: "draft"
    end

    create index(:posts, [:status])
  end
end

# 롤백
defmodule MyApp.Repo.Migrations.RemoveStatusFromPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      remove :status
    end
  end
end
```

## 데이터 변환 마이그레이션

```elixir
# priv/repo/migrations/20240715_migrate_user_types.exs
defmodule MyApp.Repo.Migrations.MigrateUserTypes do
  use Ecto.Migration

  def change do
    # 새 컬럼 추가
    alter table(:users) do
      add :role_new, :string
    end

    execute &copy_role_data/0, &drop_role/0
  end

  defp copy_role_data do
    "UPDATE users SET role_new = CASE
      WHEN is_admin THEN 'admin'
      WHEN is_moderator THEN 'moderator'
      ELSE 'user'
    END"
  end

  defp drop_role do
    # 롤백 시 실행
    "UPDATE users SET role_new = NULL"
  end
end

# 커스텀 마이그레이션
defmodule MyApp.Repo.Migrations.UpdateLegacyData do
  use Ecto.Migration

  def up do
    alter table(:posts) do
      add :slug, :string
    end

    execute(&populate_slugs/0)
  end

  def down do
    alter table(:posts) do
      remove :slug
    end
  end

  defp populate_slugs do
    "UPDATE posts SET slug = lower(replace(title, ' ', '-'))"
  end
end
```

## 안전한 마이그레이션 패턴

```elixir
# 단계별 마이그레이션
defmodule MyApp.Repo.Migrations.SafeRename do
  use Ecto.Migration

  def change do
    # 1단계: 새 컬럼 추가
    alter table(:users) do
      add :email_new, :string
    end

    # 2단계: 데이터 복사 (애플리케이션에서 수행)
    # 3단계: 이전 컬럼 삭제
    # 4단계: 새 컬럼 이름 변경
  end
end

# 애플리케이션 코드
defmodule DataMigration do
  def migrate_emails do
    MyApp.Repo.stream(User)
    |> Stream.each(fn user ->
      changeset = User.changeset(user, %{email_new: user.email})
      MyApp.Repo.update(changeset)
    end)
    |> Stream.run()

    :ok
  end
end
```

## 대량 데이터 처리

```elixir
defmodule BulkMigration do
  def migrate_in_batches(batch_size \\ 1000) do
    total = MyApp.Repo.aggregate(Post, :count)

    Enum.each(0..div(total, batch_size), fn offset ->
      posts = from(p in Post,
        offset: ^(offset * batch_size),
        limit: ^batch_size
      ) |> MyApp.Repo.all()

      MyApp.Repo.transaction(fn ->
        Enum.each(posts, &process_post/1)
      end)
    end)
  end

  defp process_post(post) do
    changeset = Post.changeset(post, %{
      slug: slugify(post.title)
    })

    MyApp.Repo.update(changeset)
  end

  defp slugify(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]/, "")
    |> String.replace(~r/[\s_-]+/, "-")
    |> String.trim("-")
  end
end
```

## 마이그레이션 검증

```elixir
defmodule MigrationValidator do
  def validate_migration do
    with :ok <- check_data_integrity(),
         :ok <- check_null_constraints(),
         :ok <- check_foreign_keys() do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_data_integrity do
    invalid_emails = MyApp.Repo.all(
      from u in User,
      where: is_nil(u.email) or u.email == ""
    )

    if Enum.empty?(invalid_emails) do
      :ok
    else
      {:error, "Found invalid emails"}
    end
  end

  defp check_null_constraints do
    orphaned = MyApp.Repo.all(
      from p in Post,
      left_join: u in User, on: p.user_id == u.id,
      where: is_nil(u.id)
    )

    if Enum.empty?(orphaned) do
      :ok
    else
      {:error, "Found orphaned posts"}
    end
  end

  defp check_foreign_keys do
    # 외래키 무결성 검사
    :ok
  end
end
```

## 롤백 계획

```elixir
defmodule RollbackPlan do
  def prepare_rollback do
    # 마이그레이션 전 백업
    create_backup()

    # 롤백 스크립트 준비
    prepare_rollback_script()
  end

  defp create_backup do
    # 데이터베이스 백업
    System.cmd("pg_dump", [
      "-h", "localhost",
      "-U", "postgres",
      "myapp_prod",
      "-F", "c",
      "-f", "backup_#{Date.today()}.dump"
    ])
  end

  defp prepare_rollback_script do
    """
    -- 롤백 스크립트
    BEGIN;

    -- 이전 데이터 복원
    UPDATE posts SET slug = NULL;
    ALTER TABLE posts DROP COLUMN slug;

    COMMIT;
    """
  end
end
```

## 결론

안전한 데이터 마이그레이션은 신중한 계획과 검증을 필요로 합니다. 단계별 마이그레이션, 데이터 검증, 롤백 계획을 통해 운영 중인 시스템의 안정성을 유지할 수 있습니다.
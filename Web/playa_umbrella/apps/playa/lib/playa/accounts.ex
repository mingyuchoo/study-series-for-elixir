defmodule Playa.Accounts do
  @moduledoc """
  The Accounts context.

  이 모듈은 계정 관련 기능에 대한 공개 API를 제공하는 facade입니다.
  실제 구현은 다음 하위 모듈에 위임됩니다:

  - `Playa.Accounts.Users` - 사용자 관리
  - `Playa.Accounts.Sessions` - 세션 및 인증 토큰
  - `Playa.Accounts.Roles` - 역할 관리
  - `Playa.Accounts.RoleAssignments` - 역할-사용자 관계
  """

  alias Playa.Accounts.{Users, Sessions, Roles, RoleAssignments}

  # ---------------------------------------------------------------------------
  # Users - 사용자 관리
  # ---------------------------------------------------------------------------

  @doc "이메일로 사용자 조회"
  defdelegate get_user_by_email(email), to: Users, as: :get_by_email

  @doc "이메일과 비밀번호로 사용자 인증"
  defdelegate get_user_by_email_and_password(email, password),
    to: Users,
    as: :get_by_email_and_password

  @doc "ID로 사용자 조회"
  defdelegate get_user!(id), to: Users, as: :get!

  @doc "모든 사용자 목록"
  defdelegate list_users(), to: Users, as: :list

  @doc "특정 역할의 사용자 목록"
  defdelegate list_users_by_role_id(role_id), to: Users, as: :list_by_role_id

  @doc "사용자 등록"
  defdelegate register_user(attrs), to: Users, as: :register

  @doc "사용자 생성"
  defdelegate create_user(attrs \\ %{}), to: Users, as: :create

  @doc "사용자 정보 업데이트"
  defdelegate update_user(user, attrs), to: Users, as: :update

  @doc "사용자 닉네임 업데이트"
  defdelegate update_user_nickname(user, attrs), to: Users, as: :update_nickname

  @doc "사용자 이메일 변경"
  defdelegate apply_user_email(user, password, attrs), to: Users, as: :apply_email_change

  @doc "사용자 삭제"
  defdelegate delete_user(user), to: Users, as: :delete

  @doc "사용자가 관리자인지 확인"
  defdelegate is_admin?(user), to: Users, as: :admin?

  @doc "사용자 등록 changeset"
  defdelegate change_user_registration(user, attrs \\ %{}), to: Users, as: :change_registration

  @doc "사용자 이메일 changeset"
  defdelegate change_user_email(user, attrs \\ %{}), to: Users, as: :change_email

  @doc "사용자 닉네임 changeset"
  defdelegate change_user_nickname(user, attrs \\ %{}), to: Users, as: :change_nickname

  @doc "사용자 changeset"
  defdelegate change_user(user, attrs \\ %{}), to: Users, as: :change

  # ---------------------------------------------------------------------------
  # Sessions - 세션 및 인증
  # ---------------------------------------------------------------------------

  @doc "세션 토큰 생성"
  defdelegate generate_user_session_token(user), to: Sessions, as: :generate_token

  @doc "세션 토큰으로 사용자 조회"
  defdelegate get_user_by_session_token(token), to: Sessions, as: :get_user_by_token

  @doc "세션 토큰 삭제"
  defdelegate delete_user_session_token(token), to: Sessions, as: :delete_token

  @doc "이메일 확인 지시사항 전송"
  defdelegate deliver_user_confirmation_instructions(user, confirmation_url_fun),
    to: Sessions,
    as: :deliver_confirmation_instructions

  @doc "사용자 확인"
  defdelegate confirm_user(token), to: Sessions

  @doc "이메일 업데이트 지시사항 전송"
  defdelegate deliver_user_update_email_instructions(user, current_email, update_email_url_fun),
    to: Sessions,
    as: :deliver_update_email_instructions

  @doc "사용자 이메일 업데이트"
  defdelegate update_user_email(user, token), to: Sessions

  @doc "비밀번호 재설정 지시사항 전송"
  defdelegate deliver_user_reset_password_instructions(user, reset_password_url_fun),
    to: Sessions,
    as: :deliver_reset_password_instructions

  @doc "비밀번호 재설정 토큰으로 사용자 조회"
  defdelegate get_user_by_reset_password_token(token), to: Sessions

  @doc "비밀번호 재설정"
  defdelegate reset_user_password(user, attrs), to: Sessions

  @doc "비밀번호 changeset"
  defdelegate change_user_password(user, attrs \\ %{}), to: Sessions, as: :change_password

  @doc "비밀번호 업데이트"
  defdelegate update_user_password(user, password, attrs), to: Sessions

  # ---------------------------------------------------------------------------
  # Roles - 역할 관리
  # ---------------------------------------------------------------------------

  @doc "모든 역할 목록"
  defdelegate list_roles(), to: Roles, as: :list

  @doc "특정 사용자의 역할 목록"
  defdelegate list_roles_by_user_id(user_id), to: Roles, as: :list_by_user_id

  @doc "특정 사용자가 가지지 않은 역할 목록"
  defdelegate list_remain_roles_by_user_id(user_id), to: Roles, as: :list_remaining_by_user_id

  @doc "ID로 역할 조회"
  defdelegate get_role!(id), to: Roles, as: :get!

  @doc "기본 역할 조회"
  defdelegate get_default_role(role_name), to: Roles, as: :get_default

  @doc "역할 생성"
  defdelegate create_role(attrs \\ %{}), to: Roles, as: :create

  @doc "역할 업데이트"
  defdelegate update_role(role, attrs), to: Roles, as: :update

  @doc "역할 삭제"
  defdelegate delete_role(role), to: Roles, as: :delete

  @doc "역할 changeset"
  defdelegate change_role(role, attrs \\ %{}), to: Roles, as: :change

  @doc "역할의 사용자 카운트 증가"
  defdelegate increase_user_count(role), to: Roles

  @doc "역할의 사용자 카운트 감소"
  defdelegate decrease_user_count(role), to: Roles

  # ---------------------------------------------------------------------------
  # RoleAssignments - 역할-사용자 관계
  # ---------------------------------------------------------------------------

  @doc "모든 역할-사용자 관계 목록"
  defdelegate list_role_user(), to: RoleAssignments, as: :list

  @doc "특정 사용자의 역할 할당 목록"
  defdelegate list_role_user_by_user_id(user_id), to: RoleAssignments, as: :list_by_user_id

  @doc "특정 사용자가 할당받지 않은 역할 목록"
  defdelegate list_role_user_not_user_id(user_id), to: RoleAssignments, as: :list_unassigned_roles

  @doc "역할-사용자 관계 조회 (예외 발생)"
  defdelegate get_role_user!(role_id, user_id), to: RoleAssignments, as: :get!

  @doc "역할-사용자 관계 조회"
  defdelegate get_role_user(role_id, user_id), to: RoleAssignments, as: :get

  @doc "역할-사용자 관계 생성"
  defdelegate create_role_user(attrs \\ %{}), to: RoleAssignments, as: :create

  @doc "역할-사용자 관계 업데이트"
  defdelegate update_role_user(role_user, attrs), to: RoleAssignments, as: :update

  @doc "역할-사용자 관계 삭제"
  defdelegate delete_role_user(role_user), to: RoleAssignments, as: :delete

  @doc "역할-사용자 changeset"
  defdelegate change_role_user(role_user, attrs \\ %{}), to: RoleAssignments, as: :change
end

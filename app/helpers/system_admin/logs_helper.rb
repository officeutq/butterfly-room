# frozen_string_literal: true

module SystemAdmin::LogsHelper
  def application_log_title(kind)
    kind == :errors ? "エラーログ" : "更新ログ"
  end

  def application_log_index_path(kind, options = {})
    kind == :errors ? system_admin_error_logs_path(options) : system_admin_change_logs_path(options)
  end

  def application_log_path(entry)
    entry.is_a?(ErrorLog) ? system_admin_error_log_path(entry) : system_admin_change_log_path(entry)
  end

  def application_log_actor(entry)
    return "自動処理・未特定" unless entry.actor_user_id

    name = entry.actor_user&.display_name.presence
    name ? "#{name}（ID: #{entry.actor_user_id}）" : "ユーザー ID: #{entry.actor_user_id}"
  end

  def application_log_time(time)
    time&.in_time_zone("Asia/Tokyo")&.strftime("%Y-%m-%d %H:%M:%S") || "—"
  end

  def application_log_value(value)
    return "未設定" if value.nil?
    return "秘匿（変更の事実のみ記録）" if value == Logs::Sanitizer::FILTERED
    return value ? "はい" : "いいえ" if value == true || value == false

    value.is_a?(Hash) ? value.to_json : value.to_s
  end

  def application_log_action(action)
    { "created" => "作成", "updated" => "更新" }.fetch(action, action)
  end
end

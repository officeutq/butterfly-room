#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "psych"

class BuildIssueCli
  APP_BUILD_PATH = File.expand_path("../config/app_build.yml", __dir__)
  BUILD_MAP_PATH = File.expand_path("../build_map.yml", __dir__)
  ENVIRONMENTS = %w[development test production].freeze

  def self.start(argv)
    new(argv).start
  end

  def initialize(argv)
    @argv = argv.dup
  end

  def start
    command = @argv.shift

    case command
    when "add-issue"
      issue_number_arg = @argv.shift
      ensure_no_extra_args!
      add_issue(issue_number_arg)
    when "bump-build"
      ensure_no_extra_args!
      bump_build
    else
      abort_with_usage("不明なコマンドです: #{command.inspect}")
    end
  end

  private

  def add_issue(issue_number_arg)
    issue_number = parse_issue_number!(issue_number_arg)

    app_build = load_yaml_file!(APP_BUILD_PATH)
    build_number = current_build_number_from!(app_build)
    build_key = build_number.to_s

    build_map = load_yaml_file!(BUILD_MAP_PATH)
    builds = ensure_builds_hash!(build_map, BUILD_MAP_PATH)
    entry = ensure_build_entry!(builds, build_key)

    issues = entry["issues"]
    unless issues.is_a?(Array)
      abort "ERROR: #{BUILD_MAP_PATH} の builds.#{build_key}.issues は配列である必要があります"
    end

    issues.each do |value|
      unless value.is_a?(Integer)
        abort "ERROR: #{BUILD_MAP_PATH} の builds.#{build_key}.issues には整数のみを保存してください"
      end
    end

    updated = (issues | [ issue_number ]).sort
    entry["issues"] = updated

    write_yaml_file!(BUILD_MAP_PATH, build_map)

    if updated.include?(issue_number) && issues != updated
      puts "Added issue ##{issue_number} to build #{build_key}"
    else
      puts "Issue ##{issue_number} is already registered in build #{build_key}"
    end
  end

  def bump_build
    app_build = load_yaml_file!(APP_BUILD_PATH)
    current_build = current_build_number_from!(app_build)
    new_build = current_build + 1
    new_build_key = new_build.to_s

    ENVIRONMENTS.each do |env_name|
      env_config = app_build[env_name]
      unless env_config.is_a?(Hash)
        abort "ERROR: #{APP_BUILD_PATH} の #{env_name} セクションが不正です"
      end

      env_config["build_number"] = new_build
    end

    if app_build["default"].is_a?(Hash)
      app_build["default"]["build_number"] = new_build
    end

    build_map = load_yaml_file!(BUILD_MAP_PATH)
    builds = ensure_builds_hash!(build_map, BUILD_MAP_PATH)
    ensure_build_entry!(builds, new_build_key)

    write_app_build_yaml!(APP_BUILD_PATH, new_build)
    write_yaml_file!(BUILD_MAP_PATH, build_map)

    puts "Bumped build from #{current_build} to #{new_build}"
  end

  def parse_issue_number!(value)
    abort_with_usage("Issue番号を指定してください") if value.nil? || value.strip.empty?
    abort "ERROR: Issue番号は整数のみ受け付けます" unless value.match?(/\A\d+\z/)

    value.to_i
  end

  def current_build_number_from!(app_build)
    ENVIRONMENTS.map do |env_name|
      env_config = app_build[env_name]
      unless env_config.is_a?(Hash)
        abort "ERROR: #{APP_BUILD_PATH} の #{env_name} セクションが不正です"
      end

      build_number = env_config["build_number"]
      unless build_number.is_a?(Integer)
        abort "ERROR: #{APP_BUILD_PATH} の #{env_name}.build_number は整数である必要があります"
      end

      build_number
    end.uniq.then do |numbers|
      if numbers.size != 1
        abort "ERROR: #{APP_BUILD_PATH} の build_number が環境ごとに不一致です"
      end

      numbers.first
    end
  end

  def ensure_builds_hash!(yaml, path)
    builds = yaml["builds"]
    unless builds.is_a?(Hash)
      abort "ERROR: #{path} の builds はハッシュである必要があります"
    end

    builds
  end

  def ensure_build_entry!(builds, build_key)
    entry = builds[build_key]

    if entry.nil?
      builds[build_key] = { "issues" => [] }
      entry = builds[build_key]
    end

    unless entry.is_a?(Hash)
      abort "ERROR: build #{build_key} のエントリが不正です"
    end

    entry["issues"] ||= []

    entry
  end

  def load_yaml_file!(path)
    begin
      content = File.read(path)
    rescue Errno::ENOENT
      abort "ERROR: ファイルが存在しません: #{path}"
    rescue StandardError => e
      abort "ERROR: ファイルの読み込みに失敗しました: #{path} (#{e.class}: #{e.message})"
    end

    begin
      data = Psych.safe_load(content, aliases: true)
    rescue Psych::SyntaxError => e
      abort "ERROR: YAMLの読み込みに失敗しました: #{path} (#{e.message})"
    end

    unless data.is_a?(Hash)
      abort "ERROR: YAMLのトップレベルはハッシュである必要があります: #{path}"
    end

    data
  end

  def write_app_build_yaml!(path, build_number)
    content = <<~YAML
      default: &default
        build_number: #{build_number}

      development:
        <<: *default

      test:
        <<: *default

      production:
        <<: *default
    YAML

    File.write(path, content)
  rescue StandardError => e
    abort "ERROR: ファイルの書き込みに失敗しました: #{path} (#{e.class}: #{e.message})"
  end

  def write_yaml_file!(path, data)
    yaml = YAML.dump(data)
    yaml.sub!(/\A---\s*\n/, "")

    File.write(path, yaml)
  rescue StandardError => e
    abort "ERROR: ファイルの書き込みに失敗しました: #{path} (#{e.class}: #{e.message})"
  end

  def ensure_no_extra_args!
    return if @argv.empty?

    abort_with_usage("引数が多すぎます: #{@argv.join(' ')}")
  end

  def abort_with_usage(message)
    abort <<~TEXT
      ERROR: #{message}

      Usage:
        ruby script/build_issue.rb add-issue ISSUE_NUMBER
        ruby script/build_issue.rb bump-build
    TEXT
  end
end

BuildIssueCli.start(ARGV)

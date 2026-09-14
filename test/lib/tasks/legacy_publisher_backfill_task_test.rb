require "test_helper"
require "rake"
require "tmpdir"
require_relative "../../support/legacy_publisher_backfill_test_support"

load Rails.root.join("lib/tasks/legacy_publisher_backfill.rake") unless defined?(LegacyPublisherBackfillTask)

class LegacyPublisherBackfillTaskTest < ActiveSupport::TestCase
  include LegacyPublisherBackfillTestSupport
  self.use_transactional_tests = false

  setup { build_backfill_fixture }
  teardown { cleanup_backfill_fixture }

  test "default plan requires a new file and explicit apply and restore use that same manifest" do
    Dir.mktmpdir("publisher-backfill") do |directory|
      path = File.join(directory, "manifest.json")
      env = { "PUBLISHER_BACKFILL_MANIFEST" => path, "PUBLISHER_BACKFILL_GIT_COMMIT" => @git_commit }
      output, = capture_io { LegacyPublisherBackfillTask.call(env) }
      manifest = JSON.parse(File.read(path))
      assert_equal manifest.fetch("sha256"), JSON.parse(output).fetch("sha256")
      assert_nil @session.reload.actual_publisher_user_id
      bytes = File.binread(path)
      assert_raises(Errno::EEXIST) { LegacyPublisherBackfillTask.call(env) }
      assert_equal bytes, File.binread(path)
      assert_raises(KeyError) { LegacyPublisherBackfillTask.call(env.merge("PUBLISHER_BACKFILL_MODE" => "apply")) }
      assert_nil @session.reload.actual_publisher_user_id
      env["PUBLISHER_BACKFILL_CONFIRM_SHA256"] = manifest.fetch("sha256")
      output, = capture_io { LegacyPublisherBackfillTask.call(env.merge("PUBLISHER_BACKFILL_MODE" => "apply")) }
      assert_equal "applied", JSON.parse(output.lines.first).fetch("status")
      assert_equal @creator.id, @session.reload.actual_publisher_user_id
      assert_equal bytes, File.binread(path)
      capture_io { LegacyPublisherBackfillTask.call(env.merge("PUBLISHER_BACKFILL_MODE" => "restore")) }
      assert_nil @session.reload.actual_publisher_user_id
      assert_equal bytes, File.binread(path)
    end
  end
end

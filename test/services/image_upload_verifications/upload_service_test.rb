require "test_helper"
require_relative "../../support/image_upload_verification_helpers"

class ImageUploadVerifications::UploadServiceTest < ActiveSupport::TestCase
  include ImageUploadVerificationHelpers
  Service = ImageUploadVerifications::UploadService
  Invalid = ImageUploadVerifications::ImageValidator::Invalid

  setup do
    @user = User.create!(email: "upload-service@example.com", password: "password", role: :system_admin)
    @service = Service.new(user: @user)
    @upload = jpeg_upload
    @bytes = File.binread(@upload.path)
    ActiveStorage::Current.url_options = { host: "example.test", protocol: "http" }
  end

  teardown do
    ImageUploadVerificationRun.where(user: @user).update_all(cleanup_after: 1.hour.ago)
    ImageUploadVerifications::CleanupService.new.call
    close_verification_files
    ActiveStorage::Current.reset
  end

  test "multipart preserves both JPEGs and stores crop data without production attachments" do
    run = create_run
    assert_no_difference("ActiveStorage::Attachment.count") do
      report = @service.multipart(id: run.id, uploads: { "source" => @upload, "display" => @upload })
      assert_equal @bytes.bytesize * 2, report[:total_bytes]
      assert_equal "complete", report[:state]
      assert_equal Digest::SHA256.hexdigest(@bytes), report[:images]["source"][:sha256]
    end
    run.reload
    assert_equal "complete", run.state
    assert_equal crop_data, run.crop_data
    assert_not_equal run.source_blob_id, run.display_blob_id
    assert_equal @bytes, run.source_blob.download
    assert_equal @bytes, run.display_blob.download
  end

  test "direct verifies the real bytes and binds the pair to one run and owner" do
    run, ids = direct_pair
    report = @service.complete(id: run.id, signed_ids: ids)
    assert_equal "complete", report[:state]
    assert_equal "direct", report[:transport]
    assert_equal @bytes.bytesize * 2, report[:total_bytes]
    assert_raises(Service::Conflict) { @service.complete(id: run.id, signed_ids: ids) }
  end

  test "another owner cannot issue urls finish or cancel even with valid signed ids" do
    run, ids = direct_pair
    other = User.create!(email: "other-upload@example.com", password: "password", role: :system_admin)
    service = Service.new(user: other)
    assert_raises(ActiveRecord::RecordNotFound) { service.complete(id: run.id, signed_ids: ids) }
    assert_raises(ActiveRecord::RecordNotFound) { service.cancel(id: run.id) }
    assert_raises(ActiveRecord::RecordNotFound) { service.direct_upload(id: run.id, role: "source", attributes: attributes) }
    assert_equal "pending", run.reload.state
  end

  test "signed ids from another run or swapped roles are refused" do
    run, ids = direct_pair
    other_run, other_ids = direct_pair
    assert_raises(Invalid) { @service.complete(id: run.id, signed_ids: other_ids) }
    assert_raises(Invalid) { @service.complete(id: run.id, signed_ids: ids.merge("source" => ids["display"])) }
    assert_raises(Invalid) { @service.complete(id: run.id, signed_ids: ids.merge("source" => "forged")) }
    assert_equal "pending", other_run.reload.state
  end

  test "invalid crop metadata and declarations are refused without blobs" do
    assert_no_difference("ActiveStorage::Blob.count") do
      [ crop_data.merge("schemaVersion" => 2), crop_data.merge("zoom" => 3),
        crop_data.deep_merge("crop" => { "x" => -1 }), crop_data.deep_merge("source" => { "width" => 9000 }),
        crop_data.deep_merge("output" => { "width" => 50 }), crop_data.merge("extra" => "a" * 4096) ].each do |data|
        assert_raises(Invalid) { @service.create(transport: "direct", crop_data: data) }
      end
      run = create_run("direct")
      [ attributes.merge("byte_size" => 21.megabytes), attributes.merge("checksum" => "bad"),
        attributes.merge("content_type" => "image/png"), attributes.merge("byte_size" => -1) ].each do |values|
        assert_raises(Invalid) { @service.direct_upload(id: run.id, role: "source", attributes: values) }
      end
      assert_raises(Invalid) { @service.direct_upload(id: run.id, role: "avatar", attributes: attributes) }
    end
  end

  test "multipart rejects incorrect dimensions forged JPEG corrupt JPEG missing pair and excessive bytes" do
    wrong = jpeg_upload(1024, 1024)
    bad = ActionDispatch::Http::UploadedFile.new(tempfile: File.open(Rails.root.join("test/fixtures/files/sample.png")), filename: "fake.jpg", type: "image/jpeg")
    [ wrong, bad, nil ].each do |upload|
      run = create_run
      assert_no_difference("ActiveStorage::Blob.count") do
        assert_raises(Invalid) { @service.multipart(id: run.id, uploads: { "source" => upload, "display" => @upload }) }
      end
      assert_equal "failed", run.reload.state
    end
    bad.tempfile.close
    File.truncate(@upload.path, 40)
    assert_raises(Invalid) { @service.multipart(id: create_run.id, uploads: { "source" => @upload, "display" => @upload }) }
    File.truncate(@upload.path, 21.megabytes)
    assert_raises(Invalid) { @service.multipart(id: create_run.id, uploads: { "source" => @upload, "display" => @upload }) }
  end

  test "direct rejects missing corrupted and misdeclared stored files" do
    run, ids = direct_pair
    run.reload.source_blob.service.delete(run.source_blob.key)
    assert_raises(Service::StorageError) { @service.complete(id: run.id, signed_ids: ids) }
    assert_equal "failed", run.reload.state

    run, ids = direct_pair
    blob = run.reload.source_blob
    blob.service.upload(blob.key, StringIO.new(@bytes + "excess"))
    assert_raises(Invalid) { @service.complete(id: run.id, signed_ids: ids) }

    run, ids = direct_pair
    blob = run.reload.source_blob
    blob.service.upload(blob.key, StringIO.new("x" * blob.byte_size))
    assert_raises(Invalid) { @service.complete(id: run.id, signed_ids: ids) }
  end

  test "a partial storage failure keeps tracked blobs for delayed cleanup and allows a new run" do
    run = create_run
    original = ActiveStorage::Blob.service.method(:upload)
    count = 0
    failing_upload = ->(*args, **kwargs) do
      count += 1
      raise IOError, "simulated" if count == 2
      original.call(*args, **kwargs)
    end
    with_method(ActiveStorage::Blob.service, :upload, failing_upload) do
      assert_raises(Service::StorageError) { @service.multipart(id: run.id, uploads: { "source" => @upload, "display" => @upload }) }
    end
    assert_equal "failed", run.reload.state
    assert run.source_blob_id
    assert run.display_blob_id
    assert_equal "complete", @service.multipart(id: create_run.id, uploads: { "source" => @upload, "display" => @upload })[:state]
  end

  test "cancel expiration and duplicate slot do not permit completion or reuse" do
    run, ids = direct_pair
    assert_raises(Service::Conflict) { @service.direct_upload(id: run.id, role: "source", attributes: attributes) }
    @service.cancel(id: run.id)
    assert_raises(Service::Conflict) { @service.complete(id: run.id, signed_ids: ids) }
    assert run.reload.source_blob.service.exist?(run.source_blob.key), "cancel must wait for late PUTs"
    run = create_run
    travel_to 16.minutes.from_now do
      assert_raises(Service::Conflict) { @service.multipart(id: run.id, uploads: { "source" => @upload, "display" => @upload }) }
    end
  end

  test "cancel during server verification cannot become complete" do
    run, ids = direct_pair
    @service.define_singleton_method(:verify_pair) do |record|
      cancel(id: record.id)
      { "source" => { bytes: 1 }, "display" => { bytes: 1 } }
    end
    assert_raises(Service::Conflict) { @service.complete(id: run.id, signed_ids: ids) }
    assert_equal "canceled", run.reload.state
  end

  test "DB completion failure leaves tracked files and no partial successful report" do
    run, ids = direct_pair
    run.define_singleton_method(:update!) do |attrs|
      raise ActiveRecord::RecordInvalid, self if attrs[:state] == "complete"
      super(attrs)
    end
    with_method(@service, :owned_run, ->(*) { run }) do
      assert_raises(Service::StorageError) { @service.complete(id: run.id, signed_ids: ids) }
    end
    assert_equal "failed", run.reload.state
    assert_equal({}, run.report)
    assert run.source_blob_id
    assert run.display_blob_id
  end

  test "cleanup ignores unexpired and unrelated blobs and retries after storage failure even when flag is off" do
    run, = direct_pair
    unrelated = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(@bytes), filename: "unrelated.jpg", content_type: "image/jpeg")
    cleanup = ImageUploadVerifications::CleanupService.new
    assert_no_difference("ActiveStorage::Blob.count") { cleanup.call }
    run.update!(cleanup_after: 1.minute.ago)
    with_method(ActiveStorage::Blob.service, :delete, ->(*) { raise IOError }) { cleanup.call }
    assert ImageUploadVerificationRun.exists?(run.id)
    assert run.reload.source_blob_id
    with_env("IMAGE_UPLOAD_VERIFICATION_ENABLED" => nil) { cleanup.call }
    assert_not ImageUploadVerificationRun.exists?(run.id)
    assert unrelated.service.exist?(unrelated.key)
  ensure
    unrelated&.purge
  end

  test "cleanup refuses a key that is not owned by the run" do
    run, = direct_pair
    blob = run.reload.source_blob
    original_key = blob.key
    blob.update!(key: "production-image")
    run.update!(cleanup_after: 1.minute.ago)
    ImageUploadVerifications::CleanupService.new.call
    assert ImageUploadVerificationRun.exists?(run.id)
    blob.update!(key: original_key)
  end

  test "quota bounds retained run count" do
    Service::MAX_RETAINED_RUNS.times { create_run }
    assert_raises(Service::CapacityExceeded) { create_run }
  end

  private

  def with_method(object, name, implementation)
    object.define_singleton_method(name, implementation)
    yield
  ensure
    object.singleton_class.remove_method(name)
  end

  def create_run(transport = "multipart")
    @service.create(transport: transport, crop_data: crop_data)
  end

  def attributes
    { "byte_size" => @bytes.bytesize, "checksum" => Digest::MD5.base64digest(@bytes), "content_type" => "image/jpeg" }
  end

  def direct_pair
    run = create_run("direct")
    ids = Service::ROLES.to_h do |role|
      response = @service.direct_upload(id: run.id, role: role, attributes: attributes)
      blob = ActiveStorage::Blob.find_signed!(response["signed_id"])
      blob.service.upload(blob.key, StringIO.new(@bytes), checksum: blob.checksum)
      [ role, response["signed_id"] ]
    end
    [ run, ids ]
  end
end

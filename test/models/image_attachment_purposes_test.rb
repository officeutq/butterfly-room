# frozen_string_literal: true

require "test_helper"

class ImageAttachmentPurposesTest < ActiveSupport::TestCase
  EXPECTED_PURPOSES = {
    User => {
      avatar: [ :avatar_source, :avatar, :avatar_crop_data, "square", 1024, 1024 ],
      cover: [ :cover_image_source, :cover_image, :cover_image_crop_data, "social", 1200, 630 ]
    },
    Store => {
      thumbnail: [ :thumbnail_source, :thumbnail, :thumbnail_crop_data, "social", 1200, 630 ]
    },
    Booth => {
      thumbnail: [ :thumbnail_image_source, :thumbnail_image, :thumbnail_image_crop_data, "social", 1200, 630 ]
    }
  }.freeze

  test "each model exposes its image attachment purpose contract" do
    EXPECTED_PURPOSES.each do |model, expected_purposes|
      assert_equal expected_purposes.keys, model.image_attachment_purposes.keys

      expected_purposes.each do |purpose_name, expected|
        configuration = model.image_attachment_purpose_for(purpose_name)

        assert_equal expected, [
          configuration.source_attachment,
          configuration.display_attachment,
          configuration.crop_attribute,
          configuration.ratio_key,
          configuration.output_width,
          configuration.output_height
        ]
        assert model.attachment_reflections.key?(configuration.source_attachment.to_s)
        assert model.attachment_reflections.key?(configuration.display_attachment.to_s)
      end
    end
  end

  test "crop data defaults to an empty hash and persists independently" do
    user = User.create!(email: "image-purpose@example.com", password: "password", role: :customer)
    store = Store.create!(name: "Image purpose store")
    booth = Booth.create!(name: "Image purpose booth", store:)

    assert_equal({}, user.avatar_crop_data)
    assert_equal({}, user.cover_image_crop_data)
    assert_equal({}, store.thumbnail_crop_data)
    assert_equal({}, booth.thumbnail_image_crop_data)

    user.update!(avatar_crop_data: { "schemaVersion" => 1 })

    assert_equal({ "schemaVersion" => 1 }, user.reload.avatar_crop_data)
    assert_equal({}, user.cover_image_crop_data)
  end

  test "configured source and display attachments persist independently" do
    store = Store.create!(name: "Attachment purpose store")
    records = {
      User => User.create!(email: "attachment-purpose@example.com", password: "password", role: :customer),
      Store => store,
      Booth => Booth.create!(name: "Attachment purpose booth", store:)
    }
    blobs = []

    EXPECTED_PURPOSES.each do |model, expected_purposes|
      expected_purposes.each_key do |purpose_name|
        configuration = model.image_attachment_purpose_for(purpose_name)
        source_blob = create_blob("#{model.name}-#{purpose_name}-source.jpg")
        display_blob = create_blob("#{model.name}-#{purpose_name}-display.jpg")
        blobs.concat([ source_blob, display_blob ])

        records.fetch(model).public_send(configuration.source_attachment).attach(source_blob)
        records.fetch(model).public_send(configuration.display_attachment).attach(display_blob)

        reloaded_record = model.find(records.fetch(model).id)
        assert_equal source_blob.id, reloaded_record.public_send(configuration.source_attachment).blob.id
        assert_equal display_blob.id, reloaded_record.public_send(configuration.display_attachment).blob.id
        assert_not_equal source_blob.id, display_blob.id
      end
    end
  ensure
    blobs&.each { |blob| blob.purge if blob.persisted? }
  end

  test "an instance resolves the same purpose configuration as its model" do
    user = User.new

    assert_same User.image_attachment_purpose_for(:avatar), user.image_attachment_purpose_for(:avatar)
    assert_raises(ArgumentError) { user.image_attachment_purpose_for(:unknown) }
  end

  private

  def create_blob(filename)
    ActiveStorage::Blob.create_and_upload!(
      io: File.open(file_fixture("sample.jpg")),
      filename:,
      content_type: "image/jpeg",
      identify: false
    )
  end
end

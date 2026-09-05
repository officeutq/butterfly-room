# frozen_string_literal: true

require "test_helper"

class ImageAttachmentEditorPartialTest < ActionDispatch::IntegrationTest
  test "square editor renders the multipart contract and accessible controls" do
    html = render_editor(
      param_root: :avatar_image,
      ratio_key: :square,
      label: "アバター画像",
      expected: {
        source_attachment_id: 11,
        source_blob_id: 12,
        display_attachment_id: 13,
        display_blob_id: 14
      }
    )
    document = Nokogiri::HTML.fragment(html)
    section = document.at_css("section[data-controller='image-attachment-editor']")

    assert_equal "square", section["data-image-attachment-editor-ratio-key-value"]
    assert_match(/image_attachments\/heic_worker/, section["data-image-attachment-editor-heic-worker-url-value"])
    assert_match(/libheif-without-unsafe-eval/, section["data-image-attachment-editor-heic-decoder-url-value"])
    assert_equal "turbo:before-cache@document->image-attachment-editor#beforeCache", section["data-action"]
    assert_equal "アバター画像", document.at_css("h2").text
    assert_match(/1:1（1024×1024）/, document.at_css(".form-text").text)

    picker = document.at_css("input[data-image-attachment-editor-target='fileInput']")
    assert_nil picker["name"]
    assert_equal ".jpg,.jpeg,.png,.webp,.heic,.heif,image/jpeg,image/png,image/webp,image/heic,image/heif", picker["accept"]
    assert_equal "/licenses/heic-verification.txt", document.at_css("a[href*='licenses']")["href"]
    assert_equal picker["id"], document.at_css("label.form-label")["for"]

    assert_payload_input(document, "avatar_image[operation]", "hidden")
    assert_payload_input(document, "avatar_image[source]", "file")
    assert_payload_input(document, "avatar_image[display]", "file")
    assert_payload_input(document, "avatar_image[crop_data]", "hidden")
    assert_equal %w[11 12 13 14], ImageAttachments::MultipartPayload::EXPECTED_ID_KEYS.map { |key|
      document.at_css("input[name='avatar_image[expected][#{key}]']")["value"]
    }

    editor = document.at_css("[data-image-attachment-editor-target='editor']")
    assert_equal "0", editor["tabindex"]
    assert_equal "group", editor["role"]
    assert_match(/keydown->image-attachment-editor#moveWithKeyboard/, editor["data-action"])
    assert_equal "polite", document.at_css("[data-image-attachment-editor-target='status']")["aria-live"]
  end

  test "social editor exposes current source state without naming the raw picker" do
    crop_data = {
      schemaVersion: 1,
      ratioKey: "social",
      sourceBlobId: 22,
      source: { width: 1421, height: 800 },
      crop: { x: 100, y: 100, width: 1200, height: 630 },
      zoom: 1.1842,
      output: { width: 1200, height: 630, mimeType: "image/jpeg", quality: 0.9 }
    }
    html = render_editor(
      param_root: "hero_image",
      ratio_key: "social",
      label: "ヒーロー画像",
      current_source_url: "/rails/active_storage/source",
      current_display_url: "/rails/active_storage/display",
      current_crop_data: crop_data,
      expected: {
        source_attachment_id: 21,
        source_blob_id: 22,
        display_attachment_id: 23,
        display_blob_id: 24
      }
    )
    document = Nokogiri::HTML.fragment(html)
    section = document.at_css("section")

    assert_equal "/rails/active_storage/source", section["data-image-attachment-editor-current-source-url-value"]
    assert_equal "/rails/active_storage/display", section["data-image-attachment-editor-current-display-url-value"]
    assert_equal "22", section["data-image-attachment-editor-current-source-blob-id-value"]
    assert_equal crop_data.deep_stringify_keys, JSON.parse(section["data-image-attachment-editor-current-crop-data-value"])
    assert_match(/40:21（1200×630）/, document.at_css(".form-text").text)
    assert_nil document.at_css("input[data-image-attachment-editor-target='fileInput']")["name"]
    assert_equal 1, document.css("button[data-action='image-attachment-editor#editExisting']").size
    assert_equal 1, document.css("button[data-action='image-attachment-editor#removeImage']").size
  end

  test "unknown ratio is rejected while rendering" do
    error = assert_raises(ActionView::Template::Error) do
      render_editor(param_root: :image, ratio_key: :wide, label: "不正な画像")
    end
    assert_instance_of KeyError, error.cause
  end

  private

  def render_editor(**locals)
    ApplicationController.render(partial: "shared/image_attachment_editor", locals:)
  end

  def assert_payload_input(document, name, type)
    input = document.at_css("input[name='#{name}']")

    assert input, "#{name} input should exist"
    assert_equal type, input["type"]
  end
end

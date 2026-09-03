require "tempfile"
require "mini_magick"

module ImageUploadVerificationHelpers
  def crop_data(ratio = "social")
    width, height = ratio == "square" ? [ 1024, 1024 ] : [ 1200, 630 ]
    { "schemaVersion" => 1, "ratioKey" => ratio, "source" => { "width" => width, "height" => height },
      "crop" => { "x" => 0, "y" => 0, "width" => width, "height" => height }, "zoom" => 1,
      "output" => { "width" => width, "height" => height, "mimeType" => "image/jpeg", "quality" => 0.9 } }
  end

  def jpeg_upload(width = 1200, height = 630)
    file = Tempfile.new([ "verification-test", ".jpg" ])
    @verification_tempfiles ||= []
    @verification_tempfiles << file
    MiniMagick.convert do |command|
      command.size("#{width}x#{height}")
      command << "gradient:red-blue"
      command << "JPEG:#{file.path}"
    end
    file.binmode
    file.rewind
    ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: "test.jpg", type: "image/jpeg")
  end

  def close_verification_files
    @verification_tempfiles&.each(&:close!)
  end
end

#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint watermark_kit.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_watermark_kit'
  s.version          = '1.0.0'
  s.summary          = 'High-performance iOS watermarking for Flutter.'
  s.description      = <<-DESC
Compose text or image watermarks over images and videos using Core Image with a Metal-backed CIContext. No FFmpeg dependency.
  DESC
  s.homepage         = 'https://github.com/tttocklll/watermark_kit'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'tttocklll' => 'https://github.com/tttocklll' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_watermark_kit/Sources/flutter_watermark_kit/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  s.resource_bundles = {'flutter_watermark_kit_privacy' => ['flutter_watermark_kit/Sources/flutter_watermark_kit/PrivacyInfo.xcprivacy']}
end

# Local iOS native-library wrapper for Accessibilibili.
# Keep this layout compatible with the bgg media-kit fork used by the app.
Pod::Spec.new do |s|
  prepared = Dir.chdir(__dir__) { system("make", "all") }
  unless prepared
    raise "Failed to prepare patched libmpv iOS frameworks"
  end

  mpv_framework = File.join(__dir__, "Frameworks", "Mpv.xcframework")
  unless File.directory?(mpv_framework)
    raise "Patched libmpv setup completed without Mpv.xcframework: #{mpv_framework}"
  end

  s.name             = 'media_kit_libs_ios_video'
  s.version          = '1.1.4'
  s.summary          = 'iOS dependency package for package:media_kit'
  s.description      = 'Accessibilibili-compatible iOS libmpv package with shared AVAudioSession support.'
  s.homepage         = 'https://github.com/Wentsy/Accessibilibili'
  s.license          = { :type => 'MIT' }
  s.author           = { 'media-kit contributors' => 'https://github.com/media-kit/media-kit' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'

  s.vendored_frameworks = 'Frameworks/*.xcframework'

  s.platform = :ios, '9.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.0'
end

#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'native_video_player'
  s.version          = '1.0.0'
  s.summary          = 'A high-performance native video player for Flutter.'
  s.description      = <<-DESC
A high-performance native video player for Flutter with multi-instance support,
HLS/DASH streaming, quality switching, and more.
                       DESC
  s.homepage         = 'https://github.com/yourusername/native_video_player'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Name' => 'your@email.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end

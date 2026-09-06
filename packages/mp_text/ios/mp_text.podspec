Pod::Spec.new do |s|
  s.name             = 'mp_text'
  s.version          = '0.0.1'
  s.summary          = 'Flutter bridge for MediaPipe text tasks.'
  s.description      = 'Android and iOS backends for MediaPipe Text Proofreader and Text Summarizer.'
  s.homepage         = 'https://github.com/ifiokjr/mediapipe'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Ifiok Jr.' => 'ifiokjr@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'MediaPipeTasksText', '1.0.0'
  # MediaPipeTasksCommon 1.0.0 references Metal types but omits Metal from its
  # CocoaPods framework list. Link it here until the upstream pod adds it.
  s.frameworks = 'Metal'
  s.platform = :ios, '15.0'
  s.static_framework = true
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.9'
end

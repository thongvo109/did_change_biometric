#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint did_change_authlocal.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'did_change_authlocal'
  s.version          = '1.0.0'
  s.summary          = 'Detect biometric data changes on iOS and Android.'
  s.description      = <<-DESC
A Flutter plugin that detects when biometric data (Face ID, Touch ID) has been
changed on the device. Helps protect against unauthorized biometric enrollment.
                       DESC
  s.homepage         = 'https://thongvo109.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Thong Vo' => 'thongvo109@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'did_change_authlocal/Sources/did_change_authlocal/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end

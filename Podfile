# BLANK TV — CocoaPods (MobileVLCKit for universal IPTV playback)
platform :ios, '17.0'

target 'BlankTV' do
  use_frameworks!
  # Stable production VLC engine — plays HLS/m3u8/TS/MKV/AVI and all IPTV formats
  pod 'MobileVLCKit', '~> 3.6.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
      config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'arm64'
    end
  end
end

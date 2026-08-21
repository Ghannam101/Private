# BLANK TV — CocoaPods (MobileVLCKit for universal IPTV playback)
platform :ios, '17.0'

target 'BlankTV' do
  use_frameworks!
  # Stable production VLC engine — plays HLS/m3u8/TS/MKV/AVI and all IPTV formats
  pod 'MobileVLCKit', '~> 3.6.0'
  # Local SQLite catalog store (GRDB) — instant paged lists + FTS5 search for
  # 20k–50k-channel catalogs instead of an eager in-memory parse. Pinned to 6.x
  # (GRDB 7 is SPM-only, not on the CocoaPods trunk); the classic Column("x")
  # query API used by CatalogDB is identical on 6 and 7.
  pod 'GRDB.swift', '~> 6.24'

  # Unit tests. `inherit! :search_paths` is the correct mode for a HOSTED test
  # bundle: the app already links MobileVLCKit and GRDB, and the test bundle loads
  # into that app. Linking them a second time here would put two copies of each
  # library in one process — duplicate Objective-C classes, and a linker that picks
  # one at random. The tests need the HEADERS to compile `@testable import BlankTV`,
  # which is exactly what search_paths gives and nothing more.
  target 'BlankTVTests' do
    inherit! :search_paths
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
      config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'arm64'
    end
  end
end

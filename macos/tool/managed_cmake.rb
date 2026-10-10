require 'digest'
require 'fileutils'

# Provides a project-managed CMake fallback for flutter_soloud 4.1.7.
#
# Flutter 3.41.9 cannot resolve flutter_soloud 5.x because the Flutter SDK pins
# package:meta to 1.17.0 while native_toolchain_c used by flutter_soloud 5.x
# requires meta ^1.19.0. flutter_soloud 4.1.7 therefore remains pinned, but its
# CocoaPods build phase requires a `cmake` executable on PATH.
#
# We prefer an existing system CMake. If none is available, a SHA-256 pinned
# official Kitware universal macOS archive is downloaded into the user's cache.
module LyricForgeManagedCMake
  VERSION = '4.4.4'.freeze
  ARCHIVE_NAME = "cmake-#{VERSION}-macos10.10-universal.tar.gz".freeze
  DOWNLOAD_URL =
    "https://github.com/Kitware/CMake/releases/download/v#{VERSION}/#{ARCHIVE_NAME}".freeze
  ARCHIVE_SHA256 =
    'd6a8fe92599160bba0c76910ceaf8c8e38c7dcc00cc08d5a29d59da93283a558'.freeze

  module_function

  def ensure!
    unless force_managed?
      existing = existing_cmake
      if existing
        puts "LyricForge: using existing CMake at #{existing}"
        return File.dirname(existing)
      end
    end

    managed = managed_cmake
    if File.file?(managed) && File.executable?(managed)
      puts "LyricForge: using cached managed CMake #{VERSION} at #{managed}"
      return File.dirname(managed)
    end

    install_managed_cmake!
    unless File.file?(managed) && File.executable?(managed)
      raise "LyricForge managed CMake installation completed without #{managed}"
    end

    puts "LyricForge: installed managed CMake #{VERSION} at #{managed}"
    File.dirname(managed)
  rescue StandardError => error
    raise <<~MESSAGE
      LyricForge could not prepare CMake required by flutter_soloud 4.1.7.
      #{error}

      Check the network connection and retry `flutter run -d macos`.
      As a manual fallback you can install CMake with `brew install cmake`.
    MESSAGE
  end

  def force_managed?
    ENV['LYRIC_FORGE_FORCE_MANAGED_CMAKE'] == '1'
  end

  def existing_cmake
    explicit = ENV['CMAKE_EXECUTABLE']&.strip
    candidates = []
    candidates << explicit unless explicit.nil? || explicit.empty?

    ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |directory|
      next if directory.nil? || directory.empty?
      candidates << File.join(directory, 'cmake')
    end

    candidates.concat([
      '/opt/homebrew/bin/cmake',
      '/usr/local/bin/cmake',
      '/Applications/CMake.app/Contents/bin/cmake',
    ])

    candidates.find { |path| File.file?(path) && File.executable?(path) }
  end

  def cache_root
    override = ENV['LYRIC_FORGE_CMAKE_CACHE_ROOT']&.strip
    return File.expand_path(override) unless override.nil? || override.empty?

    File.expand_path("~/Library/Caches/LyricForge/tooling/cmake-#{VERSION}")
  end

  def managed_cmake
    File.join(cache_root, 'CMake.app', 'Contents', 'bin', 'cmake')
  end

  def install_managed_cmake!
    parent = File.dirname(cache_root)
    FileUtils.mkdir_p(parent)

    archive = File.join(parent, "#{ARCHIVE_NAME}.part")
    staging = "#{cache_root}.staging-#{Process.pid}"

    FileUtils.rm_f(archive)
    FileUtils.rm_rf(staging)
    FileUtils.mkdir_p(staging)

    puts "LyricForge: CMake was not found; downloading managed CMake #{VERSION}..."
    downloaded = system(
      'curl',
      '--fail',
      '--location',
      '--retry', '3',
      '--retry-delay', '2',
      '--connect-timeout', '20',
      '--output', archive,
      DOWNLOAD_URL,
    )
    raise "download failed from #{DOWNLOAD_URL}" unless downloaded

    actual_sha256 = Digest::SHA256.file(archive).hexdigest
    unless actual_sha256 == ARCHIVE_SHA256
      raise "CMake archive checksum mismatch: expected #{ARCHIVE_SHA256}, got #{actual_sha256}"
    end

    extracted = system(
      'tar',
      '-xzf', archive,
      '-C', staging,
      '--strip-components=1',
    )
    raise 'failed to extract the managed CMake archive' unless extracted

    staged_cmake = File.join(staging, 'CMake.app', 'Contents', 'bin', 'cmake')
    unless File.file?(staged_cmake) && File.executable?(staged_cmake)
      raise "managed CMake archive did not contain #{staged_cmake}"
    end

    FileUtils.rm_rf(cache_root)
    FileUtils.mv(staging, cache_root)
  ensure
    FileUtils.rm_f(archive) if defined?(archive) && archive
    if defined?(staging) && staging && File.directory?(staging)
      FileUtils.rm_rf(staging)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  puts LyricForgeManagedCMake.ensure!
end

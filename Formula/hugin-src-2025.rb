class HuginSrc2025 < Formula
  desc "Panorama photo stitcher 2025.0.1 built from source (Apple Silicon)"
  homepage "https://hugin.sourceforge.net"
  # AIDEV-NOTE: Use downloads.sourceforge.net directly — avoids /download suffix warning
  # and the SourceForge webpage redirect that the base URL returns.
  url "https://downloads.sourceforge.net/project/hugin/hugin/hugin-2025.0/hugin-2025.0.1.tar.bz2"
  sha256 "7cf8eb33a6a8848cc7f816faf4bc88389228883d5513136dccb5cb243912ab79"
  license "GPL-2.0-or-later"

  depends_on :macos => :catalina  # std::filesystem requires 10.15+
  depends_on "cmake"      => :build
  depends_on "pkg-config" => :build
  depends_on "boost"
  depends_on "exiftool"
  depends_on "exiv2"
  depends_on "fftw"
  depends_on "glew"
  depends_on "gsl"
  depends_on "jpeg-turbo"
  depends_on "libepoxy"
  depends_on "libomp"
  depends_on "libpano"
  depends_on "openexr"
  depends_on "libpng"
  depends_on "libtiff"
  depends_on "little-cms2"
  depends_on "wxwidgets"

  # VIGRA — required image processing library, not in Homebrew
  resource "vigra" do
    url "https://github.com/ukoethe/vigra/archive/de98f930b66d461360a2d5dc8f9adfa84bb01058.tar.gz"
    sha256 "46f679837a270c3822ce2e3a1929679cbd18bffec9131cef044291f08f22957f"
  end

  # enblend/enfuse — multi-band blending tools, not in Homebrew
  resource "enblend" do
    url "https://github.com/jackmitch/enblend-enfuse/archive/1b7746445aac94432bc8b795b034f759138a5aed.tar.gz"
    sha256 "8b7105cf77cf60afb6c065824d2da2ca7fcb91b4ae8a71c95289947b92dad13d"
  end

  def install
    # AIDEV-NOTE: `patch :DATA` uses `patch -g 0 -f -p1` without -l, which fails on
    # Hugin source because it has trailing spaces. We read __END__ section from
    # __FILE__ directly and apply with -l (whitespace-tolerant) instead.
    # NOTE: DATA constant is not set when Homebrew loads formulae via require/eval.
    patch_content = ::File.read(__FILE__, encoding: "UTF-8").split("\n__END__\n", 2).last
    patch_file = buildpath/"hugin-macos.patch"
    patch_file.write(patch_content)
    system "patch", "-p1", "-l", "--input", patch_file.to_s

    # ── Build VIGRA ────────────────────────────────────────────────────────────
    vigra_prefix = buildpath/"vigra-install"
    resource("vigra").stage do
      system "cmake", "-S", ".", "-B", "build",
        "-DCMAKE_BUILD_TYPE=Release",
        "-DCMAKE_INSTALL_PREFIX=#{vigra_prefix}",
        "-DWITH_OPENEXR=OFF",
        "-DWITH_HDF5=OFF",
        "-DWITH_VIGRANUMPY=OFF",
        "-DDOCINSTALL=OFF"
      system "cmake", "--build", "build", "-j#{ENV.make_jobs}"
      system "cmake", "--install", "build"
    end

    # ── Build enblend/enfuse ───────────────────────────────────────────────────
    enblend_prefix = buildpath/"enblend-install"
    resource("enblend").stage do
      system "cmake", "-S", ".", "-B", "build",
        "-DCMAKE_BUILD_TYPE=Release",
        "-DCMAKE_PREFIX_PATH=#{HOMEBREW_PREFIX}",
        "-DCMAKE_OSX_DEPLOYMENT_TARGET=10.15",
        "-DENABLE_OPENCL=OFF",
        "-DENABLE_OPENMP=OFF",
        "-DDOC=OFF",
        "-DCMAKE_INSTALL_PREFIX=#{enblend_prefix}"
      system "cmake", "--build", "build", "-j#{ENV.make_jobs}", "--target", "enblend"
      system "cmake", "--build", "build", "-j#{ENV.make_jobs}", "--target", "enfuse"
      system "cmake", "--install", "build"
    end

    # ── Build Hugin ────────────────────────────────────────────────────────────
    system "cmake", "-S", ".", "-B", "build",
      "-DCMAKE_BUILD_TYPE=Release",
      "-DCMAKE_PREFIX_PATH=#{HOMEBREW_PREFIX};#{vigra_prefix}",
      "-DMAC_SELF_CONTAINED_BUNDLE=ON",
      "-DCMAKE_OSX_DEPLOYMENT_TARGET=10.15"

    %w[Hugin PTBatcherGUI HuginStitchProject calibrate_lens_gui].each do |target|
      system "cmake", "--build", "build", "-j#{ENV.make_jobs}", "--target", target
    end

    # ── Assemble Hugin.app bundle ──────────────────────────────────────────────
    app = buildpath/"build/src/hugin1/hugin/Hugin.app"
    macos_dir = app/"Contents/MacOS"

    # Core tools not auto-copied by cmake
    %w[nona hugin_hdrmerge verdandi].each do |t|
      cp buildpath/"build/src/tools/#{t}", macos_dir/t
      chmod 0755, macos_dir/t
    end

    # enblend / enfuse (Mach-O binaries)
    cp enblend_prefix/"bin/enblend", macos_dir/"enblend"
    cp enblend_prefix/"bin/enfuse",  macos_dir/"enfuse"
    chmod 0755, macos_dir/"enblend"
    chmod 0755, macos_dir/"enfuse"

    # exiftool
    cp Formula["exiftool"].opt_bin/"exiftool", macos_dir/"exiftool"
    chmod 0755, macos_dir/"exiftool"

    # ── Embed internal Hugin dylibs and fix all references ────────────────────
    # AIDEV-NOTE: MAC_SELF_CONTAINED_BUNDLE=ON does NOT embed internal dylibs;
    # cmake links them via absolute build-time /tmp paths that disappear after
    # brew's sandbox is cleaned. Copy + rewrite with @executable_path here.
    internal_dylib_sources = {
      "libhuginbase.0.0.dylib"     => buildpath/"build/src/hugin_base/libhuginbase.0.0.dylib",
      "libhuginbasewx.0.0.dylib"  => buildpath/"build/src/hugin1/base_wx/libhuginbasewx.0.0.dylib",
      "libceleste.0.0.dylib"       => buildpath/"build/src/celeste/libceleste.0.0.dylib",
      "libicpfindlib.0.0.dylib"   => buildpath/"build/src/hugin1/icpfind/libicpfindlib.0.0.dylib",
      "liblocalfeatures.0.0.dylib" => buildpath/"build/src/hugin_cpfind/localfeatures/liblocalfeatures.0.0.dylib",
    }

    fixup_bundle = lambda do |bundle_macos|
      # Copy each dylib in and set its own install name
      internal_dylib_sources.each do |name, src|
        cp src, bundle_macos/name
        chmod 0755, bundle_macos/name
        system "install_name_tool", "-id", "@executable_path/#{name}", (bundle_macos/name).to_s
      end
      # Fix references in every binary (executables + the dylibs themselves)
      Dir[bundle_macos/"*"].select { |f| File.file?(f) }.each do |bin|
        internal_dylib_sources.each_key do |dylib_name|
          old_ref = `otool -L "#{bin}" 2>/dev/null`.lines
                      .map(&:strip)
                      .find { |l| l.include?(dylib_name) && l.include?("/") && !l.start_with?("@") }
                      &.split(/\s+/)&.first
          next unless old_ref
          system "install_name_tool", "-change", old_ref,
                 "@executable_path/#{dylib_name}", bin
        end
      end
    end

    # Fix Hugin.app
    fixup_bundle.call(macos_dir)

    # Fix the other app bundles before installing them
    [
      buildpath/"build/src/hugin1/ptbatcher/PTBatcherGUI.app/Contents/MacOS",
      buildpath/"build/src/hugin1/stitch_project/HuginStitchProject.app/Contents/MacOS",
      buildpath/"build/src/hugin1/calibrate_lens/calibrate_lens_gui.app/Contents/MacOS",
    ].each { |d| fixup_bundle.call(d) }

    # Set locale env for all child processes (prevents "Cannot set locale" dialogs)
    # AIDEV-NOTE: rescue nil is needed — PlistBuddy errors if the key already exists
    plist = app/"Contents/Info.plist"
    system "/usr/libexec/PlistBuddy", "-c", "Add :LSEnvironment dict",                       plist.to_s rescue nil # rubocop:disable Style/RescueModifier
    system "/usr/libexec/PlistBuddy", "-c", "Add :LSEnvironment:LANG string en_US.UTF-8",    plist.to_s rescue nil # rubocop:disable Style/RescueModifier
    system "/usr/libexec/PlistBuddy", "-c", "Add :LSEnvironment:LC_ALL string en_US.UTF-8",  plist.to_s rescue nil # rubocop:disable Style/RescueModifier

    # ── Install into Cellar ────────────────────────────────────────────────────
    [
      app,  # Hugin.app — already a Pathname with Info.plist edits applied
      buildpath/"build/src/hugin1/ptbatcher/PTBatcherGUI.app",
      buildpath/"build/src/hugin1/calibrate_lens/calibrate_lens_gui.app",
      buildpath/"build/src/hugin1/stitch_project/HuginStitchProject.app",
    ].each { |a| (prefix/"Applications").install a }

    # ── Install hugin-link helper ──────────────────────────────────────────────
    # AIDEV-NOTE: Homebrew's sandbox blocks writes to ~/Applications during install.
    # We install a small script to #{bin} instead; running it once after install
    # creates the symlinks (and it's idempotent / safe to re-run after upgrade).
    (bin/"hugin-link").write <<~SH
      #!/bin/sh
      # Links Hugin apps into ~/Applications so they appear in Spotlight/Launchpad.
      # Safe to re-run after `brew upgrade hugin-src-2025`.
      set -e
      PREFIX="#{opt_prefix}/Applications"
      DEST="$HOME/Applications"
      mkdir -p "$DEST"
      for app in Hugin.app PTBatcherGUI.app calibrate_lens_gui.app HuginStitchProject.app; do
        rm -f "$DEST/$app"
        ln -sf "$PREFIX/$app" "$DEST/$app"
        echo "✅  Linked $app"
      done
      echo "Done — Hugin should appear in Spotlight within a few seconds."
    SH
    chmod 0755, bin/"hugin-link"
  end

  def caveats
    <<~EOS
      Run once to add Hugin to ~/Applications (Spotlight/Launchpad):

        hugin-link

      Re-run after `brew upgrade` to refresh the symlinks.
      For a system-wide install in /Applications instead:

        sudo cp -R "#{opt_prefix}/Applications/Hugin.app" /Applications/
    EOS
  end

  test do
    assert_path_exists opt_prefix/"Applications/Hugin.app"
    assert_path_exists opt_prefix/"Applications/Hugin.app/Contents/MacOS/enblend"
    assert_path_exists opt_prefix/"Applications/Hugin.app/Contents/MacOS/nona"
  end
end


__END__
--- a/CMakeLists.txt
+++ b/CMakeLists.txt
@@ -19,7 +19,8 @@
 endif()
 
 if(APPLE)
-  set(CMAKE_OSX_DEPLOYMENT_TARGET "10.9")
+  # AIDEV-NOTE: bumped from 10.9 to 10.15; std::filesystem requires 10.15+
+  set(CMAKE_OSX_DEPLOYMENT_TARGET "10.15")
   if (MAC_SELF_CONTAINED_BUNDLE)
       set(CMAKE_LIBRARY_PATH ${CMAKE_SOURCE_DIR}/mac/ExternalPrograms/repository/lib)
       set(CMAKE_INCLUDE_PATH ${CMAKE_SOURCE_DIR}/mac/ExternalPrograms/repository/include ${CMAKE_SOURCE_DIR}/mac/ExternalPrograms/repository/bin)
--- a/CMakeModules/FindVIGRA.cmake
+++ b/CMakeModules/FindVIGRA.cmake
@@ -53,9 +53,15 @@
   IF(NOT VIGRA_CONFIG_VERSION_HXX)
     MESSAGE(FATAL_ERROR "Could not find vigra/configVersion.hxx or vigra/config_version.hxx. Your vigra installation seems to be corrupt.")
   ENDIF()
-  FILE(STRINGS "${VIGRA_CONFIG_VERSION_HXX}" VIGRA_VERSION_HXX REGEX ".*#define +VIGRA_VERSION +\"")
-  STRING(REGEX REPLACE ".*#define +VIGRA_VERSION +\"([.0-9]+).*" "\\1" VIGRA_VERSION "${VIGRA_VERSION_HXX}")
-  IF(${VIGRA_VERSION} VERSION_EQUAL VIGRA_FIND_VERSION OR ${VIGRA_VERSION} VERSION_GREATER VIGRA_FIND_VERSION)
+  # AIDEV-NOTE: config_version.hxx uses macro-based version (not a string literal); extract major/minor/patch individually
+  FILE(STRINGS "${VIGRA_CONFIG_VERSION_HXX}" VIGRA_VERSION_MAJOR_LINE REGEX "#define +VIGRA_VERSION_MAJOR +[0-9]+")
+  FILE(STRINGS "${VIGRA_CONFIG_VERSION_HXX}" VIGRA_VERSION_MINOR_LINE REGEX "#define +VIGRA_VERSION_MINOR +[0-9]+")
+  FILE(STRINGS "${VIGRA_CONFIG_VERSION_HXX}" VIGRA_VERSION_PATCH_LINE REGEX "#define +VIGRA_VERSION_PATCH +[0-9]+")
+  STRING(REGEX REPLACE ".*#define +VIGRA_VERSION_MAJOR +([0-9]+).*" "\\1" VIGRA_VERSION_MAJOR "${VIGRA_VERSION_MAJOR_LINE}")
+  STRING(REGEX REPLACE ".*#define +VIGRA_VERSION_MINOR +([0-9]+).*" "\\1" VIGRA_VERSION_MINOR "${VIGRA_VERSION_MINOR_LINE}")
+  STRING(REGEX REPLACE ".*#define +VIGRA_VERSION_PATCH +([0-9]+).*" "\\1" VIGRA_VERSION_PATCH "${VIGRA_VERSION_PATCH_LINE}")
+  SET(VIGRA_VERSION "${VIGRA_VERSION_MAJOR}.${VIGRA_VERSION_MINOR}.${VIGRA_VERSION_PATCH}")
+  IF("${VIGRA_VERSION}" VERSION_GREATER_EQUAL "${VIGRA_FIND_VERSION}")
     SET(VIGRA_VERSION_CHECK TRUE)
     MESSAGE(STATUS "VIGRA version: ${VIGRA_VERSION}")
   ELSE()
--- a/src/hugin1/base_wx/Executor.cpp
+++ b/src/hugin1/base_wx/Executor.cpp
@@ -128,19 +128,9 @@
     // return path in internal program (program that is shipped with Hugin)
     wxString GetInternalProgram(const wxString& bindir, const wxString& name)
     {
-#if defined __WXMAC__ && defined MAC_SELF_CONTAINED_BUNDLE
-        CFStringRef filename = MacCreateCFStringWithWxString(name);
-        wxString fn = MacGetPathToBundledExecutableFile(filename);
-        CFRelease(filename);
-        if (fn == wxEmptyString)
-        {
-            std::cerr << wxString::Format(_("External program %s not found in the bundle, reverting to system path"), name.c_str()) << std::endl;
-            return name;
-        }
-        return fn;
-#else
+        // AIDEV-NOTE: Use bindir directly on all platforms — avoids CF bundle lookup
+        // failures in child processes (e.g. hugin_executor) on macOS.
         return bindir + name;
-#endif
     };
 
     // return name of external program (can be program bundeled with Hugin, or an external program 
@@ -174,15 +164,11 @@
             };
         };
 
-        CFStringRef filename = MacCreateCFStringWithWxString(name);
-        wxString fn = MacGetPathToBundledExecutableFile(filename);
-        CFRelease(filename);
-        if (fn == wxEmptyString)
-        {
-            std::cerr << wxString::Format(_("WARNING: External program %s not found in the bundle, reverting to system path"), name.c_str()) << std::endl;
-            return name;
-        };
-        return fn;
+        // AIDEV-NOTE: Use bindir (Contents/MacOS/) directly — reliable for both the main
+        // Hugin process and child processes (e.g. hugin_executor) where
+        // CFBundleCopyAuxiliaryExecutableURL fails. All external tools are co-located
+        // with the Hugin executable in Contents/MacOS/.
+        return bindir + name;
 #else
         if (config->Read(name + "/Custom", 0l))
         {
--- a/src/hugin1/executor/hugin_executor.cpp
+++ b/src/hugin1/executor/hugin_executor.cpp
@@ -95,6 +95,21 @@
         setlocale(LC_ALL, "");
         // initialize i18n
         int localeID = config->Read("language", (long)HUGIN_LANGUAGE);
+        // AIDEV-NOTE: hugin_executor uses wxApp on macOS (can show dialogs), so the
+        // same locale pre-check as huginApp.cpp is needed here. Without it, an
+        // unsupported system locale (e.g. en_AE) causes an invisible blocking modal.
+        if (localeID == wxLANGUAGE_DEFAULT || localeID == wxLANGUAGE_UNKNOWN)
+        {
+            int sysLang = wxLocale::GetSystemLanguage();
+            const wxLanguageInfo* info = wxLocale::GetLanguageInfo(sysLang);
+            if (info)
+            {
+                wxString name = info->CanonicalName + ".UTF-8";
+                if (!setlocale(LC_ALL, name.mb_str()))
+                    localeID = wxLANGUAGE_ENGLISH_US;
+                setlocale(LC_ALL, ""); // restore
+            }
+        }
         m_locale.Init(localeID);
         // set the name of locale recource to look for
         m_locale.AddCatalog("hugin");
--- a/src/hugin1/hugin/huginApp.cpp
+++ b/src/hugin1/hugin/huginApp.cpp
@@ -300,6 +300,25 @@
     int localeID = config->Read("language", (long) HUGIN_LANGUAGE);
     DEBUG_TRACE("localeID: " << localeID);
     {
+        // AIDEV-NOTE: wxLocale::Init() shows an error dialog if the system locale
+        // (e.g. en_AE on UAE-region systems) is unknown to the C runtime.
+        // Pre-check via setlocale() and silently fall back to English US so the
+        // dialog never appears. Translations still work for explicitly chosen languages.
+        if (localeID == wxLANGUAGE_DEFAULT || localeID == wxLANGUAGE_UNKNOWN)
+        {
+            int sysLang = wxLocale::GetSystemLanguage();
+            const wxLanguageInfo* info = wxLocale::GetLanguageInfo(sysLang);
+            if (info)
+            {
+                wxString name = info->CanonicalName + ".UTF-8";
+                if (!setlocale(LC_ALL, name.mb_str()))
+                {
+                    // System locale not supported by C runtime; use English US silently.
+                    localeID = wxLANGUAGE_ENGLISH_US;
+                }
+                setlocale(LC_ALL, ""); // restore
+            }
+        }
         bool bLInit;
 	    bLInit = locale.Init(localeID);
 	    if (bLInit) {
--- a/src/hugin1/ptbatcher/CMakeLists.txt
+++ b/src/hugin1/ptbatcher/CMakeLists.txt
@@ -32,8 +32,6 @@
     # Tools
     set( TOOLS ${CMAKE_BINARY_DIR}/src/tools/align_image_stack ${CMAKE_BINARY_DIR}/src/tools/nona
                ${CMAKE_BINARY_DIR}/src/tools/hugin_hdrmerge ${CMAKE_BINARY_DIR}/src/tools/verdandi
-               ${CMAKE_SOURCE_DIR}/mac/ExternalPrograms/repository/bin/enblend
-               ${CMAKE_SOURCE_DIR}/mac/ExternalPrograms/repository/bin/enfuse 
     )
 
     FOREACH(_file ${TOOLS})
--- a/src/hugin1/ptbatcher/PTBatcherGUI.cpp
+++ b/src/hugin1/ptbatcher/PTBatcherGUI.cpp
@@ -73,7 +73,21 @@
     int localeID = wxConfigBase::Get()->Read("language", (long) wxLANGUAGE_DEFAULT);
     m_locale.Init(localeID);
 #else
-    m_locale.Init(wxLANGUAGE_DEFAULT);
+    // AIDEV-NOTE: pre-check locale support to avoid invisible blocking modal on
+    // systems with unsupported locales (e.g. en_AE). Same fix as huginApp.cpp.
+    {
+        int localeID = wxLANGUAGE_DEFAULT;
+        int sysLang = wxLocale::GetSystemLanguage();
+        const wxLanguageInfo* info = wxLocale::GetLanguageInfo(sysLang);
+        if (info)
+        {
+            wxString localeName = info->CanonicalName + ".UTF-8";
+            if (!setlocale(LC_ALL, localeName.mb_str()))
+                localeID = wxLANGUAGE_ENGLISH_US;
+            setlocale(LC_ALL, "");
+        }
+        m_locale.Init(localeID);
+    }
 #endif
     // initialize help provider
     wxHelpControllerHelpProvider* provider = new wxHelpControllerHelpProvider;
--- a/src/hugin1/stitch_project/CMakeLists.txt
+++ b/src/hugin1/stitch_project/CMakeLists.txt
@@ -24,8 +24,6 @@
     # Tools
     set( TOOLS ${CMAKE_BINARY_DIR}/src/tools/align_image_stack ${CMAKE_BINARY_DIR}/src/tools/nona
                ${CMAKE_BINARY_DIR}/src/tools/hugin_hdrmerge ${CMAKE_BINARY_DIR}/src/tools/verdandi
-               ${CMAKE_SOURCE_DIR}/mac/ExternalPrograms/repository/bin/enblend
-               ${CMAKE_SOURCE_DIR}/mac/ExternalPrograms/repository/bin/enfuse 
     )
 
     FOREACH(_file ${TOOLS})
--- a/src/hugin1/stitch_project/hugin_stitch_project.cpp
+++ b/src/hugin1/stitch_project/hugin_stitch_project.cpp
@@ -313,7 +313,21 @@
     int localeID = wxConfigBase::Get()->Read("language", (long) wxLANGUAGE_DEFAULT);
     m_locale.Init(localeID);
 #else
-    m_locale.Init(wxLANGUAGE_DEFAULT);
+    // AIDEV-NOTE: pre-check locale support to avoid invisible blocking modal on
+    // systems with unsupported locales (e.g. en_AE). Same fix as huginApp.cpp.
+    {
+        int localeID = wxLANGUAGE_DEFAULT;
+        int sysLang = wxLocale::GetSystemLanguage();
+        const wxLanguageInfo* info = wxLocale::GetLanguageInfo(sysLang);
+        if (info)
+        {
+            wxString localeName = info->CanonicalName + ".UTF-8";
+            if (!setlocale(LC_ALL, localeName.mb_str()))
+                localeID = wxLANGUAGE_ENGLISH_US;
+            setlocale(LC_ALL, "");
+        }
+        m_locale.Init(localeID);
+    }
 #endif
 
     // setup the environment for the different operating systems

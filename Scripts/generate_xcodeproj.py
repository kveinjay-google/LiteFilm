#!/usr/bin/env python3
"""Write SpektraFilm.xcodeproj. Re-run after adding a Swift file."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = "E10000000000000000000002"

SWIFT = [
    "SpektraFilmApp.swift",
    "LaunchSplashView.swift",
    "ContentView.swift",
    "ObsidianStyle.swift",
    "EditorControls.swift",
    "AdjustmentControls.swift",
    "CropEditor.swift",
    "PhotoText.swift",
    "PhotoTextEditor.swift",
    "PhotoTextSelfTest.swift",
    "ObsidianSheets.swift",
    "HomeGalleryViews.swift",
    "GalleryWallView.swift",
    "ImportGalleryStore.swift",
    "LabModel.swift",
    "EngineClient.swift",
    "PhotoAdjustments.swift",
    "AdvancedColorControls.swift",
    "AdvancedColorSelfTest.swift",
    "PhotoRetouch.swift",
    "RetouchEditor.swift",
    "RetouchSelfTest.swift",
    "PhotoDetailView.swift",
    "PhotoAnalysis.swift",
    "PhotoAnalysisSelfTest.swift",
    "RecipeBook.swift",
    "EditingSuiteSelfTest.swift",
    "BatchProcessing.swift",
    "BatchProcessingSelfTest.swift",
    "AdjustmentSelfTest.swift",
    "ImageCodec.swift",
    "ExportEncoder.swift",
    "FilmCatalog.swift",
    "FrameModels.swift",
    "FramePainter.swift",
    "FrameChrome.swift",
    "FrameSelfTest.swift",
    "WatermarkModels.swift",
    "WatermarkPainter.swift",
    "SelfTest.swift",
]

FRAMEWORKS = [
    "Metal",
    "QuartzCore",
    "CoreText",
    "CoreGraphics",
    "Accelerate",
    "PhotosUI",
    "ImageIO",
    "UIKit",
]


def q(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def main() -> None:
    lines: list[str] = []
    w = lines.append

    def section(name: str) -> None:
        w(f"\n/* Begin {name} section */")

    def end(name: str) -> None:
        w(f"/* End {name} section */")

    w("// !$*UTF8*$!")
    w("{")
    w("\tarchiveVersion = 1;")
    w("\tclasses = {};")
    w("\tobjectVersion = 63;")
    w("\tobjects = {")

    section("PBXBuildFile")
    for name in SWIFT:
        w(f"\t\tB1{name[:8].upper():<22} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = F1{name[:8].upper():<22}; }};")
    # Stable explicit ids below. The padded trick above is ugly if names collide.
    # Rewrite with a dictionary instead.
    lines.clear()

    ids: dict[str, str] = {}
    counter = 0x1000

    def nid(key: str) -> str:
        nonlocal counter
        if key not in ids:
            ids[key] = f"E1{counter:022X}"
            counter += 1
        return ids[key]

    swift_refs = [(name, nid(f"src:{name}"), nid(f"build:{name}")) for name in SWIFT]
    asset_ref = nid("asset")
    catalog_ref, catalog_build = nid("catalog"), nid("catalog-build")
    frame_catalog_ref, frame_catalog_build = nid("frame-catalog"), nid("frame-catalog-build")
    sample_ref, sample_build = nid("sample"), nid("sample-build")
    launch_ref, launch_build = nid("launch-screen"), nid("launch-screen-build")
    header_ref = nid("header")
    frameworks = [(name, nid(f"fw:{name}"), nid(f"fwbuild:{name}")) for name in FRAMEWORKS]
    script_compile = nid("script-compile")
    script_bundle = nid("script-bundle")
    sources_phase = nid("sources-phase")
    frameworks_phase = nid("frameworks-phase")
    resources_phase = nid("resources-phase")
    app_ref = nid("app-product")
    app_group = nid("group-app")
    res_group = nid("group-res")
    main_group = nid("group-main")
    products_group = nid("group-products")
    project = nid("project")
    target = TARGET
    ids["target"] = target
    project_configs = nid("project-configs")
    target_configs = nid("target-configs")
    project_debug = nid("project-debug")
    project_release = nid("project-release")
    target_debug = nid("target-debug")
    target_release = nid("target-release")

    w("// !$*UTF8*$!")
    w("{")
    w("\tarchiveVersion = 1;")
    w("\tclasses = {};")
    w("\tobjectVersion = 63;")
    w("\tobjects = {")

    section("PBXBuildFile")
    for name, ref, build in swift_refs:
        w(f"\t\t{build} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};")
    w(f"\t\t{catalog_build} /* FilmCatalog.json in Resources */ = {{isa = PBXBuildFile; fileRef = {catalog_ref} /* FilmCatalog.json */; }};")
    w(f"\t\t{frame_catalog_build} /* FrameCatalog.json in Resources */ = {{isa = PBXBuildFile; fileRef = {frame_catalog_ref} /* FrameCatalog.json */; }};")
    w(f"\t\t{sample_build} /* SampleBars.png in Resources */ = {{isa = PBXBuildFile; fileRef = {sample_ref} /* SampleBars.png */; }};")
    w(f"\t\t{launch_build} /* LaunchScreen.storyboard in Resources */ = {{isa = PBXBuildFile; fileRef = {launch_ref} /* LaunchScreen.storyboard */; }};")
    w(f"\t\t{nid('asset-build')} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {asset_ref} /* Assets.xcassets */; }};")
    for name, ref, build in frameworks:
        w(f"\t\t{build} /* {name}.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name}.framework */; }};")
    end("PBXBuildFile")

    section("PBXFileReference")
    for name, ref, _ in swift_refs:
        w(f"\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};")
    w(f"\t\t{header_ref} /* SpektraFilm-Bridging-Header.h */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = \"SpektraFilm-Bridging-Header.h\"; sourceTree = \"<group>\"; }};")
    w(f"\t\t{catalog_ref} /* FilmCatalog.json */ = {{isa = PBXFileReference; lastKnownFileType = text.json; path = FilmCatalog.json; sourceTree = \"<group>\"; }};")
    w(f"\t\t{frame_catalog_ref} /* FrameCatalog.json */ = {{isa = PBXFileReference; lastKnownFileType = text.json; path = FrameCatalog.json; sourceTree = \"<group>\"; }};")
    w(f"\t\t{sample_ref} /* SampleBars.png */ = {{isa = PBXFileReference; lastKnownFileType = image.png; path = SampleBars.png; sourceTree = \"<group>\"; }};")
    w(f"\t\t{launch_ref} /* LaunchScreen.storyboard */ = {{isa = PBXFileReference; lastKnownFileType = file.storyboard; path = LaunchScreen.storyboard; sourceTree = \"<group>\"; }};")
    w(f"\t\t{asset_ref} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};")
    w(f"\t\t{app_ref} /* LiteFilm.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = LiteFilm.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    for name, ref, _ in frameworks:
        w(
            f"\t\t{ref} /* {name}.framework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = {name}.framework; path = System/Library/Frameworks/{name}.framework; sourceTree = SDKROOT; }};"
        )
    end("PBXFileReference")

    section("PBXFrameworksBuildPhase")
    w(f"\t\t{frameworks_phase} /* Frameworks */ = {{")
    w("\t\t\tisa = PBXFrameworksBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    for name, _, build in frameworks:
        w(f"\t\t\t\t{build} /* {name}.framework in Frameworks */,")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    end("PBXFrameworksBuildPhase")

    section("PBXGroup")
    w(f"\t\t{main_group} = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w(f"\t\t\t\t{app_group} /* SpektraFilm */,")
    w(f"\t\t\t\t{products_group} /* Products */,")
    w("\t\t\t);")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    w(f"\t\t{products_group} /* Products */ = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w(f"\t\t\t\t{app_ref} /* LiteFilm.app */,")
    w("\t\t\t);")
    w("\t\t\tname = Products;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    w(f"\t\t{app_group} /* SpektraFilm */ = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    for name, ref, _ in swift_refs:
        w(f"\t\t\t\t{ref} /* {name} */,")
    w(f"\t\t\t\t{header_ref} /* SpektraFilm-Bridging-Header.h */,")
    w(f"\t\t\t\t{launch_ref} /* LaunchScreen.storyboard */,")
    w(f"\t\t\t\t{asset_ref} /* Assets.xcassets */,")
    w(f"\t\t\t\t{res_group} /* Resources */,")
    w("\t\t\t);")
    w("\t\t\tpath = SpektraFilm;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    w(f"\t\t{res_group} /* Resources */ = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w(f"\t\t\t\t{catalog_ref} /* FilmCatalog.json */,")
    w(f"\t\t\t\t{frame_catalog_ref} /* FrameCatalog.json */,")
    w(f"\t\t\t\t{sample_ref} /* SampleBars.png */,")
    w("\t\t\t);")
    w("\t\t\tpath = Resources;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    end("PBXGroup")

    section("PBXNativeTarget")
    w(f"\t\t{target} /* SpektraFilm */ = {{")
    w("\t\t\tisa = PBXNativeTarget;")
    w(f"\t\t\tbuildConfigurationList = {target_configs} /* Build configuration list for PBXNativeTarget \"SpektraFilm\" */;")
    w("\t\t\tbuildPhases = (")
    w(f"\t\t\t\t{script_compile} /* Compile SpektraLab engine */,")
    w(f"\t\t\t\t{sources_phase} /* Sources */,")
    w(f"\t\t\t\t{frameworks_phase} /* Frameworks */,")
    w(f"\t\t\t\t{resources_phase} /* Resources */,")
    w(f"\t\t\t\t{script_bundle} /* Bundle engine resources */,")
    w("\t\t\t);")
    w("\t\t\tbuildRules = (")
    w("\t\t\t);")
    w("\t\t\tdependencies = (")
    w("\t\t\t);")
    w("\t\t\tname = SpektraFilm;")
    w("\t\t\tproductName = SpektraFilm;")
    w(f"\t\t\tproductReference = {app_ref} /* LiteFilm.app */;")
    w("\t\t\tproductType = \"com.apple.product-type.application\";")
    w("\t\t};")
    end("PBXNativeTarget")

    section("PBXProject")
    w(f"\t\t{project} /* Project object */ = {{")
    w("\t\t\tisa = PBXProject;")
    w(f"\t\t\tbuildConfigurationList = {project_configs} /* Build configuration list for PBXProject \"SpektraFilm\" */;")
    w("\t\t\tcompatibilityVersion = \"Xcode 15.0\";")
    w("\t\t\tdevelopmentRegion = \"zh-Hans\";")
    w("\t\t\thasScannedForEncodings = 0;")
    w("\t\t\tknownRegions = (")
    w("\t\t\t\ten,")
    w("\t\t\t\t\"zh-Hans\",")
    w("\t\t\t\tBase,")
    w("\t\t\t);")
    w(f"\t\t\tmainGroup = {main_group};")
    w(f"\t\t\tproductRefGroup = {products_group} /* Products */;")
    w("\t\t\tprojectDirPath = \"\";")
    w("\t\t\tprojectRoot = \"\";")
    w("\t\t\ttargets = (")
    w(f"\t\t\t\t{target} /* SpektraFilm */,")
    w("\t\t\t);")
    w("\t\t};")
    end("PBXProject")

    section("PBXResourcesBuildPhase")
    w(f"\t\t{resources_phase} /* Resources */ = {{")
    w("\t\t\tisa = PBXResourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    w(f"\t\t\t\t{catalog_build} /* FilmCatalog.json in Resources */,")
    w(f"\t\t\t\t{frame_catalog_build} /* FrameCatalog.json in Resources */,")
    w(f"\t\t\t\t{sample_build} /* SampleBars.png in Resources */,")
    w(f"\t\t\t\t{launch_build} /* LaunchScreen.storyboard in Resources */,")
    w(f"\t\t\t\t{nid('asset-build')} /* Assets.xcassets in Resources */,")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    end("PBXResourcesBuildPhase")

    section("PBXShellScriptBuildPhase")
    for phase, name, mode in (
        (script_compile, "Compile SpektraLab engine", "compile"),
        (script_bundle, "Bundle engine resources", "bundle"),
    ):
        w(f"\t\t{phase} /* {name} */ = {{")
        w("\t\t\tisa = PBXShellScriptBuildPhase;")
        w("\t\t\tbuildActionMask = 2147483647;")
        w("\t\t\tfiles = (")
        w("\t\t\t);")
        w("\t\t\tinputPaths = (")
        w("\t\t\t);")
        w(f"\t\t\tname = {q(name)};")
        w("\t\t\toutputPaths = (")
        w("\t\t\t);")
        w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        w("\t\t\tshellPath = /bin/sh;")
        script = '/usr/bin/python3 "${SRCROOT}/Scripts/build_engine_ios.py" ' + mode + "\n"
        w(f"\t\t\tshellScript = {q(script)};")
        w("\t\t};")
    end("PBXShellScriptBuildPhase")

    section("PBXSourcesBuildPhase")
    w(f"\t\t{sources_phase} /* Sources */ = {{")
    w("\t\t\tisa = PBXSourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    for name, _, build in swift_refs:
        w(f"\t\t\t\t{build} /* {name} in Sources */,")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    end("PBXSourcesBuildPhase")

    shared = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_INFINITE_RECURSION": "YES",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "COPY_PHASE_STRIP": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "SDKROOT": "iphoneos",
        "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "TARGETED_DEVICE_FAMILY": "1,2",
    }
    debug_extra = {
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_DYNAMIC_NO_PIC": "NO",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
    }
    release_extra = {
        "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
        "ENABLE_NS_ASSERTIONS": "NO",
        "MTL_ENABLE_DEBUG_INFO": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL": '"-O"',
        "VALIDATE_PRODUCT": "YES",
    }

    def settings_block(values: dict[str, str], indent: str = "\t\t\t\t") -> None:
        for key in sorted(values):
            value = values[key]
            if value.startswith('"'):
                w(f"{indent}{key} = {value};")
            else:
                w(f"{indent}{key} = {q(value) if ' ' in value or value == '' else value};")

    # The helper above quotes values with spaces but leaves YES unquoted, which is correct.
    # Empty string must be quoted. Override by writing configs explicitly for clarity.

    # Automatic signing rejects a fully qualified identity. "Apple Development"
    # Select your own development team in Xcode before device builds.
    target_common = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
        "CODE_SIGNING_ALLOWED": "YES",
        "CODE_SIGNING_REQUIRED": "YES",
        "CODE_SIGN_IDENTITY": '"Apple Development"',
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "12",
        "DEVELOPMENT_TEAM": "267KQ4A3N4",
        "ENABLE_PREVIEWS": "NO",
        "GENERATE_INFOPLIST_FILE": "YES",
        "HEADER_SEARCH_PATHS": '"$(SRCROOT)/vendor/SpektraLab/engine/include"',
        "INFOPLIST_KEY_CFBundleDisplayName": "LiteFilm",
        "INFOPLIST_KEY_CFBundleName": "LiteFilm",
        "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption": "NO",
        "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.photography",
        "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
        # An empty UILaunchScreen dictionary replaces the storyboard and stays blank.
        "INFOPLIST_KEY_UILaunchStoryboardName": "LaunchScreen",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations": '"UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
        "INFOPLIST_KEY_UIUserInterfaceStyle": "Dark",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": '"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
        "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"',
        "LIBRARY_SEARCH_PATHS": '"$(inherited) $(DERIVED_FILE_DIR)"',
        "MARKETING_VERSION": "0.1.0",
        "OTHER_LDFLAGS": '"$(inherited) -lspektrafilm_engine -lc++"',
        "PRODUCT_BUNDLE_IDENTIFIER": "com.spektrafilm.ios",
        "PRODUCT_NAME": "LiteFilm",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_OBJC_BRIDGING_HEADER": "SpektraFilm/SpektraFilm-Bridging-Header.h",
        "SWIFT_STRICT_CONCURRENCY": "minimal",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": '"1,2"',
    }

    def write_config(cid: str, name: str, base: dict[str, str], extra: dict[str, str]) -> None:
        w(f"\t\t{cid} /* {name} */ = {{")
        w("\t\t\tisa = XCBuildConfiguration;")
        w("\t\t\tbuildSettings = {")
        merged = dict(base)
        merged.update(extra)
        for key in sorted(merged):
            value = merged[key]
            if value.startswith('"') or value in ("YES", "NO") or value.replace(".", "", 1).isdigit():
                w(f"\t\t\t\t{key} = {value};")
            else:
                w(f"\t\t\t\t{key} = {q(value)};")
        w("\t\t\t};")
        w(f"\t\t\tname = {name};")
        w("\t\t};")

    section("XCBuildConfiguration")
    write_config(project_debug, "Debug", shared, debug_extra)
    write_config(project_release, "Release", shared, release_extra)
    write_config(target_debug, "Debug", target_common, {"SWIFT_OPTIMIZATION_LEVEL": '"-Onone"', "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG"})
    write_config(target_release, "Release", target_common, {"SWIFT_OPTIMIZATION_LEVEL": '"-O"', "SWIFT_COMPILATION_MODE": "wholemodule"})
    end("XCBuildConfiguration")

    section("XCConfigurationList")
    w(f"\t\t{project_configs} /* Build configuration list for PBXProject \"SpektraFilm\" */ = {{")
    w("\t\t\tisa = XCConfigurationList;")
    w("\t\t\tbuildConfigurations = (")
    w(f"\t\t\t\t{project_debug} /* Debug */,")
    w(f"\t\t\t\t{project_release} /* Release */,")
    w("\t\t\t);")
    w("\t\t\tdefaultConfigurationIsVisible = 0;")
    w("\t\t\tdefaultConfigurationName = Release;")
    w("\t\t};")
    w(f"\t\t{target_configs} /* Build configuration list for PBXNativeTarget \"SpektraFilm\" */ = {{")
    w("\t\t\tisa = XCConfigurationList;")
    w("\t\t\tbuildConfigurations = (")
    w(f"\t\t\t\t{target_debug} /* Debug */,")
    w(f"\t\t\t\t{target_release} /* Release */,")
    w("\t\t\t);")
    w("\t\t\tdefaultConfigurationIsVisible = 0;")
    w("\t\t\tdefaultConfigurationName = Release;")
    w("\t\t};")
    end("XCConfigurationList")

    w("\t};")
    w(f"\trootObject = {project} /* Project object */;")
    w("}")
    w("")

    # The first attempt pushed junk then cleared `lines` after writing the header once
    # into a different list. `lines` was cleared only in the abandoned branch, which
    # was removed. This file builds `lines` from the second header. Drop the unused
    # first-pass variables by simply writing what we have.
    text = "\n".join(lines) + "\n"
    # Remove the abandoned first header if it survived. It did not: lines.clear()
    # was deleted with the abandoned branch. Sanity-check a single header.
    if text.count("// !$*UTF8*$!") != 1:
        raise SystemExit(f"pbxproj header count {text.count('// !$*UTF8*$!')}")
    dest = ROOT / "SpektraFilm.xcodeproj"
    dest.mkdir(exist_ok=True)
    (dest / "project.pbxproj").write_text(text)
    scheme_dir = dest / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    (scheme_dir / "SpektraFilm.xcscheme").write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target}"
               BuildableName = "LiteFilm.app"
               BlueprintName = "SpektraFilm"
               ReferencedContainer = "container:SpektraFilm.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target}"
            BuildableName = "LiteFilm.app"
            BlueprintName = "SpektraFilm"
            ReferencedContainer = "container:SpektraFilm.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target}"
            BuildableName = "LiteFilm.app"
            BlueprintName = "SpektraFilm"
            ReferencedContainer = "container:SpektraFilm.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
""")
    print(dest / "project.pbxproj")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Build the SpektraLab C++/Metal engine for the active iOS SDK.

Called from the SpektraFilm Xcode target:

    python3 Scripts/build_engine_ios.py compile
    python3 Scripts/build_engine_ios.py bundle

`compile` writes libspektrafilm_engine.a and spektrafilm.metallib into
DERIVED_FILE_DIR. `bundle` copies engine resources, the metallib, merged
neutral-filter packs, and the license set into the app bundle.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ROOT = Path(os.environ.get("SRCROOT", Path(__file__).resolve().parents[1]))
ENGINE = ROOT / "vendor" / "SpektraLab" / "engine"
LICENSES = ROOT / "Licenses"


def env(name: str, default: str | None = None) -> str:
    value = os.environ.get(name, default)
    if not value:
        sys.exit(f"build_engine_ios.py: ${name} is not set. Run this from an Xcode build.")
    return value


def run(cmd: list[str], label: str) -> None:
    result = subprocess.run(cmd, text=True, capture_output=True)
    if result.returncode != 0:
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        sys.exit(f"{label} failed ({result.returncode}): {' '.join(cmd[:6])} ...")


def stamp_of(paths: list[Path], extra: str) -> str:
    digest = hashlib.sha256()
    digest.update(extra.encode())
    for path in sorted(paths, key=lambda item: str(item)):
        stat = path.stat()
        digest.update(f"{path.relative_to(ROOT)}:{stat.st_mtime_ns}:{stat.st_size}\n".encode())
    return digest.hexdigest()


def sources() -> list[Path]:
    found: list[Path] = []
    for folder in ("core", "gpu", "pipeline"):
        found.extend(sorted((ENGINE / "src" / folder).glob("*.cpp")))
    if not found:
        sys.exit(f"no C++ sources under {ENGINE / 'src'}")
    return found


def headers_and_shaders() -> list[Path]:
    paths = sources()
    for folder in (ENGINE / "src", ENGINE / "include"):
        paths.extend(folder.rglob("*.hpp"))
        paths.extend(folder.rglob("*.h"))
    paths.extend(sorted((ENGINE / "src" / "shaders").glob("*.metal")))
    paths.extend(sorted((ENGINE / "src" / "shaders").glob("*.h")))
    return paths


def sdk_layout() -> dict[str, str]:
    # Xcode 26 sets SDK_NAME to iphonesimulator26.5, not iphonesimulator.
    platform = os.environ.get("PLATFORM_NAME") or env("SDK_NAME")
    sdkroot = env("SDKROOT")
    archs = env("ARCHS").split()
    if len(archs) != 1:
        sys.exit(f"this iOS engine build expects one architecture, got {archs}")
    arch = archs[0]
    deploy = os.environ.get("IPHONEOS_DEPLOYMENT_TARGET", "17.0")
    if platform == "iphonesimulator":
        sdk_name = "iphonesimulator"
        triple = f"{arch}-apple-ios{deploy}-simulator"
        min_flag = f"-mios-simulator-version-min={deploy}"
        metal_target = f"air64-apple-ios{deploy}-simulator"
    elif platform == "iphoneos":
        sdk_name = "iphoneos"
        triple = f"{arch}-apple-ios{deploy}"
        min_flag = f"-miphoneos-version-min={deploy}"
        metal_target = f"air64-apple-ios{deploy}"
    else:
        sys.exit(f"unsupported platform {platform} (SDK_NAME={os.environ.get('SDK_NAME')})")
    cxx = subprocess.check_output(["xcrun", "--sdk", sdk_name, "--find", "clang++"], text=True).strip()
    return {
        "sdk_name": sdk_name,
        "sdkroot": sdkroot,
        "arch": arch,
        "deploy": deploy,
        "triple": triple,
        "min_flag": min_flag,
        "metal_target": metal_target,
        "cxx": cxx,
    }


def compile_engine() -> None:
    if os.environ.get("ACTION") == "clean":
        derived = Path(env("DERIVED_FILE_DIR"))
        for name in ("libspektrafilm_engine.a", "spektrafilm.metallib", "engine-stamp.txt"):
            (derived / name).unlink(missing_ok=True)
        shutil.rmtree(derived / "engine-obj", ignore_errors=True)
        return

    layout = sdk_layout()
    derived = Path(env("DERIVED_FILE_DIR"))
    obj_dir = derived / "engine-obj"
    obj_dir.mkdir(parents=True, exist_ok=True)
    stamp_path = derived / "engine-stamp.txt"
    extra = json.dumps(layout, sort_keys=True)
    stamp = stamp_of(headers_and_shaders(), extra)
    library = derived / "libspektrafilm_engine.a"
    metallib = derived / "spektrafilm.metallib"
    if stamp_path.is_file() and stamp_path.read_text() == stamp and library.is_file() and metallib.is_file():
        print("engine up to date")
        return

    includes = [
        "-I", str(ENGINE / "include"),
        "-I", str(ENGINE / "src"),
        "-I", str(ENGINE / "src" / "core"),
        "-I", str(ENGINE / "third_party" / "metal-cpp"),
    ]
    flags = [
        "-std=c++20", "-O2", "-Wall", "-Wextra", "-Wno-return-type-c-linkage",
        "-target", layout["triple"],
        "-isysroot", layout["sdkroot"],
        layout["min_flag"],
        "-fblocks",
        "-DNDEBUG",
    ]
    cxx = layout["cxx"]

    def compile_one(src: Path) -> None:
        obj = obj_dir / f"{src.stem}.o"
        cmd = [cxx, *flags, *includes, "-c", str(src), "-o", str(obj)]
        result = subprocess.run(cmd, text=True, capture_output=True)
        if result.returncode != 0:
            raise RuntimeError(result.stderr or result.stdout or f"compile failed: {src.name}")
        if result.stderr.strip():
            sys.stderr.write(result.stderr)

    print(f"compiling SpektraLab engine for {layout['triple']}")
    workers = 4  # Keep local engine compilation within the shared Mac build budget.
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [pool.submit(compile_one, src) for src in sources()]
        for future in as_completed(futures):
            future.result()

    objects = sorted(str(path) for path in obj_dir.glob("*.o"))
    run(["xcrun", "--sdk", layout["sdk_name"], "ar", "rcs", str(library), *objects], "ar")

    air_dir = obj_dir / "air"
    air_dir.mkdir(exist_ok=True)
    airs: list[str] = []
    math_flags = ["-fmetal-math-mode=safe", "-fmetal-math-fp32-functions=precise"]
    for shader in sorted((ENGINE / "src" / "shaders").glob("*.metal")):
        air = air_dir / f"{shader.stem}.air"
        run([
            "xcrun", "--sdk", layout["sdk_name"], "metal",
            *math_flags,
            "-target", layout["metal_target"],
            "-Werror", "-c", str(shader), "-o", str(air),
        ], f"metal {shader.name}")
        airs.append(str(air))
    run(["xcrun", "--sdk", layout["sdk_name"], "metallib", *airs, "-o", str(metallib)], "metallib")
    stamp_path.write_text(stamp)
    print(f"static lib -> {library}")
    print(f"metallib   -> {metallib}")


def deep_merge(base: dict, extra: dict) -> None:
    for key, value in extra.items():
        if key in base and isinstance(base[key], dict) and isinstance(value, dict):
            deep_merge(base[key], value)
        else:
            base[key] = value


def bundle_resources() -> None:
    if os.environ.get("ACTION") == "clean":
        return
    derived = Path(env("DERIVED_FILE_DIR"))
    metallib = derived / "spektrafilm.metallib"
    if not metallib.is_file():
        sys.exit("bundle: spektrafilm.metallib is missing. The compile phase did not run.")
    wrapper = os.environ.get("WRAPPER_NAME", "SpektraFilm.app")
    app = Path(env("TARGET_BUILD_DIR")) / wrapper
    if not app.is_dir():
        app.mkdir(parents=True)
    shutil.copy2(ROOT / "SpektraFilm" / "PrivacyInfo.xcprivacy", app / "PrivacyInfo.xcprivacy")
    font_dir = ROOT / "SpektraFilm/Resources/Fonts"
    font_manifest = json.loads((font_dir / "SOURCES.json").read_text())
    for item in font_manifest:
        source = (LICENSES if item["file"].endswith(".txt") else font_dir) / item["file"]
        if hashlib.sha256(source.read_bytes()).hexdigest() != item["sha256"]:
            sys.exit(f"bundle: font/license checksum mismatch: {source.name}")
    shutil.copytree(font_dir, app / "Fonts", dirs_exist_ok=True)
    destination = app / "engine"
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(ENGINE / "resources", destination)
    product_profiles = ENGINE / "resources_product" / "profiles"
    profile_dir = destination / "profiles"
    for profile in product_profiles.glob("*.json"):
        shutil.copy2(profile, profile_dir / profile.name)
    shutil.copy2(ENGINE / "resources_product" / "NOTICE.md", destination / "PRODUCT_PROFILES_NOTICE.md")

    merged_path = destination / "neutral_print_filters.json"
    merged = json.loads(merged_path.read_text())
    product_filters = ENGINE / "resources_product" / "neutral_print_filters.json"
    deep_merge(merged, json.loads(product_filters.read_text()))
    merged_path.write_text(json.dumps(merged, indent=2) + "\n")

    shutil.copy2(metallib, destination / "spektrafilm.metallib")
    license_dest = app / "Licenses"
    if license_dest.exists():
        shutil.rmtree(license_dest)
    shutil.copytree(LICENSES, license_dest)
    print(f"bundle -> {destination}")


def main() -> None:
    if len(sys.argv) != 2 or sys.argv[1] not in ("compile", "bundle"):
        sys.exit("usage: build_engine_ios.py compile|bundle")
    if not ENGINE.is_dir():
        sys.exit(f"missing SpektraLab engine at {ENGINE}")
    if sys.argv[1] == "compile":
        compile_engine()
    else:
        bundle_resources()


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as error:
        sys.stderr.write(str(error) + "\n")
        sys.exit(1)

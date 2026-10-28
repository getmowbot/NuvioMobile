#!/usr/bin/env python3
"""Adds the NuvioAetherKit Swift package to the iOS app target of iosApp.xcodeproj.

The fork keeps upstream's project.pbxproj untouched in git, so merging upstream releases never
conflicts on it; this script applies the AetherEngine changes on top of whatever upstream ships:

  * a local package reference to aether/NuvioAetherKit,
  * its NuvioAetherKit product linked into the `iosApp` target,
  * an "Embed Frameworks" phase copying NuvioAetherKit.framework into the app: Xcode links a
    dynamic package product without embedding it (the AetherLib* FFmpeg frameworks it depends
    on are binary targets, which Xcode does embed on its own),
  * an iOS deployment target of at least 18.0, which AetherEngine 7 requires.

Idempotent: running it on an already patched project changes nothing.
Usage: aether/scripts/patch-xcode-project.py [path/to/project.pbxproj]
"""

import pathlib
import re
import sys

PACKAGE_PATH = "../aether/NuvioAetherKit"
PRODUCT = "NuvioAetherKit"
MIN_IOS = (18, 0)

# Fixed object identifiers, chosen so they cannot collide with Xcode's generated ones.
BUILD_FILE_ID = "AE7E4E000000000000000001"
PRODUCT_DEP_ID = "AE7E4E000000000000000002"
PACKAGE_REF_ID = "AE7E4E000000000000000003"
EMBED_BUILD_FILE_ID = "AE7E4E000000000000000004"
EMBED_PHASE_ID = "AE7E4E000000000000000005"

REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_PROJECT = REPOSITORY_ROOT / "iosApp" / "iosApp.xcodeproj" / "project.pbxproj"


def fail(message: str) -> None:
    print(f"patch-xcode-project: {message}", file=sys.stderr)
    sys.exit(1)


def insert_after(text: str, anchor: str, addition: str) -> str:
    index = text.find(anchor)
    if index < 0:
        fail(f"anchor not found: {anchor!r}")
    index += len(anchor)
    return text[:index] + addition + text[index:]


def object_block(text: str, object_id: str) -> tuple[int, int]:
    """Span of `<id> /* ... */ = { ... };` for a top-level object."""
    match = re.search(r"\n\t\t" + object_id + r"(?: /\*[^*]*\*/)? = \{", text)
    if not match:
        fail(f"object {object_id} not found")
    start = match.start() + 1
    depth = 0
    for position in range(match.end() - 1, len(text)):
        character = text[position]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                end = text.index(";", position) + 1
                return start, end
    fail(f"object {object_id} is not terminated")
    raise AssertionError


def add_to_list(text: str, object_id: str, list_name: str, entry: str) -> str:
    start, end = object_block(text, object_id)
    block = text[start:end]
    if entry.split(" ")[0] in block:
        return text
    match = re.search(r"\n(\t+)" + list_name + r" = \(\n", block)
    if match:
        indentation = match.group(1) + "\t"
        block = block[:match.end()] + f"{indentation}{entry},\n" + block[match.end():]
    else:
        closing = block.rfind("\n\t\t};")
        block = block[:closing] + f"\n\t\t\t{list_name} = (\n\t\t\t\t{entry},\n\t\t\t);" + block[closing:]
    return text[:start] + block + text[end:]


def app_target_id(text: str) -> str:
    for match in re.finditer(r"\n\t\t([0-9A-F]{24}) /\* ([^*]+) \*/ = \{\n\t\t\tisa = PBXNativeTarget;", text):
        start, end = object_block(text, match.group(1))
        if 'productType = "com.apple.product-type.application";' in text[start:end]:
            return match.group(1)
    fail("no application target found")
    raise AssertionError


def insert_build_phase(text: str, target_id: str, after_id: str, entry: str) -> str:
    """Adds `entry` to the target's buildPhases right after the phase `after_id`."""
    start, end = object_block(text, target_id)
    block = text[start:end]
    match = re.search(r"\n(\t+)" + after_id + r"(?: /\*[^*]*\*/)?,\n", block)
    if not match:
        fail(f"build phase {after_id} not found in target {target_id}")
    block = block[:match.end()] + f"{match.group(1)}{entry},\n" + block[match.end():]
    return text[:start] + block + text[end:]


def frameworks_phase_id(text: str, target_id: str) -> str:
    start, end = object_block(text, target_id)
    match = re.search(r"([0-9A-F]{24}) /\* Frameworks \*/", text[start:end])
    if not match:
        fail("the application target has no Frameworks build phase")
    return match.group(1)


def project_object_id(text: str) -> str:
    match = re.search(r"rootObject = ([0-9A-F]{24})", text)
    if not match:
        fail("rootObject not found")
    return match.group(1)


def add_section_entry(text: str, section: str, entry: str) -> str:
    end_marker = f"/* End {section} section */"
    if end_marker in text:
        return text.replace(end_marker, entry + end_marker, 1)
    # Create the section right before the end of the objects dictionary.
    closing = text.rfind("\n\t};\n\trootObject")
    if closing < 0:
        fail("objects dictionary end not found")
    block = f"\n/* Begin {section} section */\n{entry}{end_marker}\n"
    return text[:closing] + block + text[closing:]


def raise_deployment_targets(text: str) -> str:
    def replace(match: re.Match) -> str:
        version = tuple(int(part) for part in match.group(1).split("."))
        if version >= MIN_IOS:
            return match.group(0)
        return f"IPHONEOS_DEPLOYMENT_TARGET = {MIN_IOS[0]}.{MIN_IOS[1]};"

    return re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);", replace, text)


def patch(text: str) -> str:
    text = raise_deployment_targets(text)
    if PACKAGE_REF_ID not in text:
        text = add_package(text)
    if EMBED_PHASE_ID not in text:
        text = add_embed_phase(text)
    return text


def add_package(text: str) -> str:
    target_id = app_target_id(text)
    phase_id = frameworks_phase_id(text, target_id)

    text = insert_after(
        text,
        "/* Begin PBXBuildFile section */\n",
        f"\t\t{BUILD_FILE_ID} /* {PRODUCT} in Frameworks */ = "
        f"{{isa = PBXBuildFile; productRef = {PRODUCT_DEP_ID} /* {PRODUCT} */; }};\n",
    )
    text = add_to_list(text, phase_id, "files", f"{BUILD_FILE_ID} /* {PRODUCT} in Frameworks */")
    text = add_to_list(text, target_id, "packageProductDependencies", f"{PRODUCT_DEP_ID} /* {PRODUCT} */")
    text = add_to_list(
        text,
        project_object_id(text),
        "packageReferences",
        f'{PACKAGE_REF_ID} /* XCLocalSwiftPackageReference "{PACKAGE_PATH}" */',
    )
    text = add_section_entry(
        text,
        "XCLocalSwiftPackageReference",
        f'\t\t{PACKAGE_REF_ID} /* XCLocalSwiftPackageReference "{PACKAGE_PATH}" */ = {{\n'
        f"\t\t\tisa = XCLocalSwiftPackageReference;\n"
        f"\t\t\trelativePath = {PACKAGE_PATH};\n"
        f"\t\t}};\n",
    )
    text = add_section_entry(
        text,
        "XCSwiftPackageProductDependency",
        f"\t\t{PRODUCT_DEP_ID} /* {PRODUCT} */ = {{\n"
        f"\t\t\tisa = XCSwiftPackageProductDependency;\n"
        f'\t\t\tpackage = {PACKAGE_REF_ID} /* XCLocalSwiftPackageReference "{PACKAGE_PATH}" */;\n'
        f"\t\t\tproductName = {PRODUCT};\n"
        f"\t\t}};\n",
    )
    return text


def add_embed_phase(text: str) -> str:
    target_id = app_target_id(text)
    text = insert_after(
        text,
        "/* Begin PBXBuildFile section */\n",
        f"\t\t{EMBED_BUILD_FILE_ID} /* {PRODUCT} in Embed Frameworks */ = "
        f"{{isa = PBXBuildFile; productRef = {PRODUCT_DEP_ID} /* {PRODUCT} */; "
        f"settings = {{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }}; }};\n",
    )
    text = add_section_entry(
        text,
        "PBXCopyFilesBuildPhase",
        f"\t\t{EMBED_PHASE_ID} /* Embed Frameworks */ = {{\n"
        f"\t\t\tisa = PBXCopyFilesBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f'\t\t\tdstPath = "";\n'
        f"\t\t\tdstSubfolderSpec = 10;\n"
        f"\t\t\tfiles = (\n"
        f"\t\t\t\t{EMBED_BUILD_FILE_ID} /* {PRODUCT} in Embed Frameworks */,\n"
        f"\t\t\t);\n"
        f'\t\t\tname = "Embed Frameworks";\n'
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};\n",
    )
    return insert_build_phase(
        text,
        target_id,
        frameworks_phase_id(text, target_id),
        f"{EMBED_PHASE_ID} /* Embed Frameworks */",
    )


def main() -> None:
    project = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PROJECT
    if not project.is_file():
        fail(f"{project} does not exist")
    original = project.read_text(encoding="utf-8")
    patched = patch(original)
    if patched == original:
        print(f"{project}: already patched")
        return
    project.write_text(patched, encoding="utf-8")
    print(f"{project}: added and embedded {PRODUCT}, raised the iOS deployment target to {MIN_IOS[0]}.{MIN_IOS[1]}")


if __name__ == "__main__":
    main()

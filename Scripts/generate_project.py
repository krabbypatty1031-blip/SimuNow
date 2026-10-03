#!/usr/bin/env python3
"""Generate the checked-in Xcode scaffold without XcodeGen or third-party packages.

Run from any directory. Target IDs are stable so shared schemes remain valid.
Keep application entry points in Apps; put feature files in the local Swift package.
"""
from pathlib import Path
import hashlib
import json
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]


def identifier(key):
    return hashlib.sha1(key.encode()).hexdigest()[:24].upper()


def quoted(value):
    return json.dumps(value, ensure_ascii=False)


def generate():
    objects = []

    def obj(key, body):
        objects.append(f"\t\t{identifier(key)} = {{ {body} }};")
        return identifier(key)

    def ref(path, file_type):
        return obj(path, f"isa = PBXFileReference; lastKnownFileType = {file_type}; path = {quoted(path)}; sourceTree = \"<group>\";")

    sources = {
        "SimuNowMac": ref("Apps/SimuNowMac/SimuNowMacApp.swift", "sourcecode.swift"),
        "SimuNowiOS": ref("Apps/SimuNowiOS/SimuNowiOSApp.swift", "sourcecode.swift"),
    }
    assets = ref("Apps/Shared/Assets.xcassets", "folder.assetcatalog")
    configs = {name: ref(f"Configurations/{name}.xcconfig", "text.xcconfig") for name in ("Shared", "macOS", "iOS")}
    root_refs = list(sources.values()) + [assets] + list(configs.values())
    root_refs.append(ref("Apps/SimuNowMac/SimuNowMac.entitlements", "text.plist.entitlements"))
    root_refs.append(ref("Apps/SimuNowMac/SimuNowMacDebug.entitlements", "text.plist.entitlements"))
    for path in ("README.md", "AGENTS.md"):
        root_refs.append(ref(path, "net.daringfireball.markdown"))
    for path in ("Plans", "Protocols", "Backend", "Fixtures", "Scripts", "Packages/SimuKit"):
        root_refs.append(ref(path, "folder"))

    local_package = obj("local-package", 'isa = XCLocalSwiftPackageReference; relativePath = "Packages/SimuKit";')
    products, targets = [], []

    for name, platform in (("SimuNowMac", "macOS"), ("SimuNowiOS", "iOS")):
        product = obj(f"{name}-product", 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SimuNow.app; sourceTree = BUILT_PRODUCTS_DIR;')
        products.append(product)
        package_product = obj(f"{name}-package-product", f"isa = XCSwiftPackageProductDependency; package = {local_package}; productName = SimuWorkspace;")
        source_build = obj(f"{name}-source-build", f"isa = PBXBuildFile; fileRef = {sources[name]};")
        resource_build = obj(f"{name}-resource-build", f"isa = PBXBuildFile; fileRef = {assets};")
        framework_build = obj(f"{name}-framework-build", f"isa = PBXBuildFile; productRef = {package_product};")
        phases = []
        for kind, build_ref in (("Sources", source_build), ("Resources", resource_build), ("Frameworks", framework_build)):
            phases.append(obj(f"{name}-{kind}", f"isa = PBX{kind}BuildPhase; buildActionMask = 2147483647; files = ({build_ref},); runOnlyForDeploymentPostprocessing = 0;"))
        if name == "SimuNowMac":
            script = (
                'mkdir -p "${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/WorkerTree/Backend/src" '
                '"${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/WorkerTree/test/p1"\n'
                'rm -rf "${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/WorkerTree/Backend/src/simunow_worker"\n'
                'cp -R "${SRCROOT}/Backend/src/simunow_worker" '
                '"${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/WorkerTree/Backend/src/simunow_worker"\n'
                'cp "${SRCROOT}/test/p1/write_idf.py" "${SRCROOT}/test/p1/run_l1.py" "${SRCROOT}/test/p1/room_input.py" '
                '"${SRCROOT}/test/p1/run_room.py" "${SRCROOT}/test/p1/write_openfoam_room.py" "${SRCROOT}/test/p1/quality.py" '
                '"${SRCROOT}/test/p1/sample_seats.py" "${SRCROOT}/test/p1/foam_io.py" "${SRCROOT}/test/p1/field_slice.py" '
                '"${SRCROOT}/test/p1/field_flow.py" '
                '"${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/WorkerTree/test/p1/"\n'
            )
            escaped = script.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
            phases.append(obj(
                f"{name}-stage-worker",
                f'isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647; files = (); inputPaths = (); '
                f'name = "Stage WorkerTree"; outputPaths = (); runOnlyForDeploymentPostprocessing = 0; '
                f'shellPath = /bin/bash; shellScript = "{escaped}"; showEnvVarsInLog = 0;',
            ))

        build_configs = []
        for mode in ("Debug", "Release"):
            sdk = 'SDKROOT = macosx; SUPPORTED_PLATFORMS = macosx; COMBINE_HIDPI_IMAGES = YES;' if platform == "macOS" else 'SDKROOT = iphoneos; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; SUPPORTS_MACCATALYST = NO; SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;'
            # Debug Mac hand-test skips the file sandbox so user-selected
            # EnergyPlus can exec. Release keeps SimuNowMac.entitlements.
            extra = ""
            if name == "SimuNowMac" and mode == "Debug":
                extra = " CODE_SIGN_ENTITLEMENTS = Apps/SimuNowMac/SimuNowMacDebug.entitlements;"
            build_configs.append(obj(f"{name}-{mode}", f"isa = XCBuildConfiguration; baseConfigurationReference = {configs[platform]}; buildSettings = {{ {sdk}{extra} }}; name = {mode};"))
        config_list = obj(f"{name}-config-list", f"isa = XCConfigurationList; buildConfigurations = ({','.join(build_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
        target = obj(name, f'isa = PBXNativeTarget; buildConfigurationList = {config_list}; buildPhases = ({",".join(phases)},); buildRules = (); dependencies = (); name = {name}; packageProductDependencies = ({package_product},); productName = SimuNow; productReference = {product}; productType = "com.apple.product-type.application";')
        targets.append(target)

    product_group = obj("products-group", f'isa = PBXGroup; children = ({",".join(products)},); name = Products; sourceTree = "<group>";')
    main_group = obj("main-group", f'isa = PBXGroup; children = ({",".join(root_refs + [product_group])},); sourceTree = "<group>";')
    project_configs = []
    for mode in ("Debug", "Release"):
        optimization = 'ONLY_ACTIVE_ARCH = YES; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; ENABLE_TESTABILITY = YES; DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";' if mode == "Debug" else 'ONLY_ACTIVE_ARCH = NO; SWIFT_COMPILATION_MODE = wholemodule; SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
        project_configs.append(obj(f"project-{mode}", f"isa = XCBuildConfiguration; baseConfigurationReference = {configs['Shared']}; buildSettings = {{ {optimization} }}; name = {mode};"))
    project_config_list = obj("project-config-list", f"isa = XCConfigurationList; buildConfigurations = ({','.join(project_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
    # developmentRegion stays zh-Hans (Chinese-first app, merge decision
    # 2026-10-04); the in-app English locale is a language toggle, not the
    # project's development region.
    project_id = obj("project", f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2700; }}; buildConfigurationList = {project_config_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = (en, "zh-Hans", Base,); mainGroup = {main_group}; packageReferences = ({local_package},); productRefGroup = {product_group}; projectDirPath = ""; projectRoot = ""; targets = ({",".join(targets)},);')
    project_dir = ROOT / "SimuNow.xcodeproj"
    project_dir.mkdir(exist_ok=True)
    text = "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n" + "\n".join(objects) + f"\n\t}};\n\trootObject = {project_id};\n}}\n"
    (project_dir / "project.pbxproj").write_text(text)
    workspace = project_dir / "project.xcworkspace"
    workspace.mkdir(exist_ok=True)
    (workspace / "contents.xcworkspacedata").write_text('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0"><FileRef location="self:"></FileRef></Workspace>\n')
    scheme_dir = project_dir / "xcshareddata/xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    for name in ("SimuNowMac", "SimuNowiOS"):
        buildable = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identifier(name)}" BuildableName="SimuNow.app" BlueprintName="{escape(name)}" ReferencedContainer="container:SimuNow.xcodeproj"/>'
        scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable}</BuildActionEntry></BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
        (scheme_dir / f"{name}.xcscheme").write_text(scheme)
    print("Generated SimuNow.xcodeproj (SimuNowMac, SimuNowiOS).")


if __name__ == "__main__":
    generate()

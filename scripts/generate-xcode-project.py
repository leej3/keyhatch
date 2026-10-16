#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Generate the deterministic native Xcode Store project. No accounts/network required."""
import hashlib
from pathlib import Path
import plistlib

ROOT = Path(__file__).resolve().parent.parent
objects = {}


def identifier(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def obj(object_name, isa, **values):
    key = identifier(object_name)
    objects[key] = dict(isa=isa, **values)
    return key


def file(path, kind):
    return obj("file:" + path, "PBXFileReference", path=path, sourceTree="<group>", lastKnownFileType=kind)


def build_file(name, reference, **values):
    return obj("build:" + name, "PBXBuildFile", fileRef=reference, **values)


def configs(name, settings):
    items = []
    for config in ("Debug", "Release"):
        merged = dict(settings)
        merged.update(SWIFT_OPTIMIZATION_LEVEL="-Onone" if config == "Debug" else "-O",
                      DEBUG_INFORMATION_FORMAT="dwarf" if config == "Debug" else "dwarf-with-dsym")
        items.append(obj(name + config, "XCBuildConfiguration", name=config, buildSettings=merged))
    return obj(name + "configs", "XCConfigurationList", buildConfigurations=items,
               defaultConfigurationIsVisible="0", defaultConfigurationName="Release")


def dependency(name, target):
    proxy = obj(name + "proxy", "PBXContainerItemProxy", containerPortal=identifier("project"),
                proxyType="1", remoteGlobalIDString=identifier(target), remoteInfo=target)
    return obj(name + "dependency", "PBXTargetDependency", target=identifier(target), targetProxy=proxy)


def phase(phase_name, isa, files, **values):
    return obj(phase_name, isa, buildActionMask="2147483647", files=files,
               runOnlyForDeploymentPostprocessing="0", **values)


references = []
source_files = {}
for target, directory in (("Core", "KeyhatchCore"), ("App", "Keyhatch"), ("Client", "KeyhatchCLI")):
    source_files[target] = []
    for path in sorted((ROOT / "Sources" / directory).glob("*.swift")):
        ref = file(str(path.relative_to(ROOT)), "sourcecode.swift")
        references.append(ref)
        source_files[target].append(build_file(target + path.name, ref))
resources = []
for path in ("Resources/Privacy.md", "Resources/PrivacyInfo.xcprivacy", "LICENSE"):
    ref = file(path, "text.xml" if path.endswith("xcprivacy") else "text")
    references.append(ref)
    resources.append(ref)
for path in sorted((ROOT / "Configuration").glob("*")):
    references.append(file(str(path.relative_to(ROOT)), "text.plist.xml"))
icon_catalog = file("Resources/Assets.xcassets", "folder.assetcatalog")
references.append(icon_catalog)
products = {}
for name, path, kind in (("Core", "libKeyhatchCore.a", "archive.ar"),
                         ("App", "Keyhatch.app", "wrapper.application"),
                         ("Client", "KeyhatchClient.app", "wrapper.application")):
    products[name] = obj(name + "product", "PBXFileReference", explicitFileType=kind,
                         path=path, sourceTree="BUILT_PRODUCTS_DIR")
product_group = obj("products", "PBXGroup", name="Products", children=list(products.values()), sourceTree="<group>")
main_group = obj("main", "PBXGroup", children=references + [product_group], sourceTree="<group>")
project_config = configs("project", {
    "MACOSX_DEPLOYMENT_TARGET": "14.0", "SDKROOT": "macosx", "SWIFT_VERSION": "5.0",
    "CLANG_ENABLE_MODULES": "YES", "ONLY_ACTIVE_ARCH": "NO",
    "KEYHATCH_BUNDLE_ID": "com.example.keyhatch", "KEYHATCH_APP_GROUP": "",
    "DEVELOPMENT_TEAM": "", "CODE_SIGN_STYLE": "Manual",
    "CODE_SIGN_IDENTITY": "Apple Distribution", "ENABLE_HARDENED_RUNTIME": "YES",
    "REGISTER_APP_GROUPS": "YES", "ENABLE_DEBUG_DYLIB": "NO",
    "CODE_SIGN_INJECT_BASE_ENTITLEMENTS": "NO", "SWIFT_INCLUDE_PATHS": "$(inherited) $(BUILT_PRODUCTS_DIR)",
    "LIBRARY_SEARCH_PATHS": "$(inherited) $(BUILT_PRODUCTS_DIR)"})
for name in ("Core", "Client", "App"):
    phases = [phase(name + "sources", "PBXSourcesBuildPhase", source_files[name])]
    settings = {"PRODUCT_NAME": {"Core": "KeyhatchCore", "App": "Keyhatch", "Client": "KeyhatchClient"}[name]}
    dependencies = []
    if name == "Core":
        settings.update(SKIP_INSTALL="YES", DEFINES_MODULE="YES", PRODUCT_MODULE_NAME="KeyhatchCore",
                        CODE_SIGNING_ALLOWED="NO")
        product_type = "com.apple.product-type.library.static"
    else:
        phases.append(phase(name + "frameworks", "PBXFrameworksBuildPhase",
                            [build_file(name + "linkcore", products["Core"])]))
        phases.append(phase(name + "resources", "PBXResourcesBuildPhase",
                            [build_file(name + str(i), ref) for i, ref in enumerate(resources + ([icon_catalog] if name == "App" else []))]))
        dependencies.append(dependency(name + "core", "Core"))
        settings.update(PRODUCT_BUNDLE_IDENTIFIER="$(KEYHATCH_BUNDLE_ID)" + (".client" if name == "Client" else ""),
                        INFOPLIST_FILE="Configuration/StoreClientInfo.plist" if name == "Client" else "Configuration/StoreInfo.plist",
                        CODE_SIGN_ENTITLEMENTS="Configuration/StoreClient.entitlements" if name == "Client" else "Configuration/StoreBroker.entitlements",
                        PROVISIONING_PROFILE_SPECIFIER="$(KEYHATCH_CLIENT_PROFILE)" if name == "Client" else "$(KEYHATCH_BROKER_PROFILE)",
                        SKIP_INSTALL="YES" if name == "Client" else "NO",
                        INSTALL_PATH="$(LOCAL_APPS_DIR)", EXECUTABLE_NAME="keyhatch" if name == "Client" else "Keyhatch")
        product_type = "com.apple.product-type.application"
        if name == "App":
            settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
            dependencies.append(dependency("appclient", "Client"))
            phases.append(phase("embedclient", "PBXCopyFilesBuildPhase",
                [build_file("embedclient", products["Client"], settings={"ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]})],
                name="Embed sandboxed client", dstSubfolderSpec="1", dstPath="Contents/Helpers"))
    obj(name, "PBXNativeTarget", name={"App": "Keyhatch", "Core": "KeyhatchCore", "Client": "KeyhatchClient"}[name],
        productName=settings["PRODUCT_NAME"], productReference=products[name], productType=product_type,
        buildConfigurationList=configs(name, settings), buildPhases=phases, buildRules=[], dependencies=dependencies)
obj("project", "PBXProject", attributes={"LastUpgradeCheck": "1600",
    "TargetAttributes": {identifier(name): {"SystemCapabilities": {
        "com.apple.ApplicationGroups.iOS": {"enabled": "1"},
        "com.apple.Sandbox": {"enabled": "1"}}} for name in ("App", "Client")}},
    buildConfigurationList=project_config, compatibilityVersion="Xcode 14.0", developmentRegion="en",
    hasScannedForEncodings="0", knownRegions=["en", "Base"], mainGroup=main_group,
    productRefGroup=product_group, projectDirPath="", projectRoot="",
    targets=[identifier("App"), identifier("Client"), identifier("Core")])
project = ROOT / "Keyhatch.xcodeproj"
project.mkdir(exist_ok=True)
with (project / "project.pbxproj").open("wb") as stream:
    plistlib.dump(dict(archiveVersion="1", classes={}, objectVersion="56", objects=objects,
                      rootObject=identifier("project")), stream, sort_keys=True)
schemes = project / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
(schemes / "Keyhatch Store.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
   <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identifier('App')}" BuildableName="Keyhatch.app" BlueprintName="Keyhatch" ReferencedContainer="container:Keyhatch.xcodeproj"/>
  </BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.PosixSpawn" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="NO">
  <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identifier('App')}" BuildableName="Keyhatch.app" BlueprintName="Keyhatch" ReferencedContainer="container:Keyhatch.xcodeproj"/></BuildableProductRunnable>
 </LaunchAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(project)

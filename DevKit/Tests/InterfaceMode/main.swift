import Foundation

private var failures = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard !condition() else { return }
    print("not ok \(message)")
    failures += 1
}

private func testFullMode() {
    let mode = RelaxinInterfaceMode.full
    expect(mode.showsJailbreakInterface, "full shows the jailbreak interface")
    expect(mode.showsPostJailbreakInterface, "full shows the post-jailbreak interface")
    expect(mode.allowsSileoReinstallation, "full allows Sileo reinstallation")
    expect(mode.allowsExternalNavigation, "full allows external navigation")
    expect(mode.allowsFileExport, "full allows maintenance exports")
    expect(mode.showsMaintenance, "full shows maintenance")
}

private func testLiteMode() {
    let mode = RelaxinInterfaceMode.lite
    expect(!mode.showsJailbreakInterface, "lite hides the jailbreak interface")
    expect(mode.showsPostJailbreakInterface, "lite shows the post-jailbreak interface")
    expect(!mode.allowsSileoReinstallation, "lite hides Sileo reinstallation")
    expect(mode.allowsExternalNavigation, "lite allows external navigation")
    expect(!mode.allowsFileExport, "lite has no maintenance exports")
    expect(!mode.showsMaintenance, "lite has no maintenance interface")
}

private func testOverlayMode() {
    let mode = RelaxinInterfaceMode.overlay
    expect(mode.showsJailbreakInterface, "overlay shows the jailbreak interface")
    expect(!mode.showsPostJailbreakInterface, "overlay hides the post-jailbreak interface")
    expect(!mode.allowsSileoReinstallation, "overlay cannot reinstall Sileo")
    expect(!mode.allowsExternalNavigation, "overlay blocks external navigation")
    expect(!mode.allowsFileExport, "overlay blocks maintenance exports")
    expect(mode.showsMaintenance, "overlay keeps Reset Relaxin")
}

private func testNativeRuntime() {
    let runtime = RelaxinRuntime.native
    expect(runtime.interfaceMode == .full, "native runtime uses the full interface")
    expect(
        runtime.additionalBootstrapPackageResourceNames.isEmpty,
        "native runtime has no additional bootstrap packages"
    )
    expect(
        runtime.postJailbreakEnvironment.interfaceMode == .full,
        "native runtime derives the full post-jailbreak mode"
    )
    expect(
        runtime.postJailbreakEnvironment.resourceBundle === runtime.resourceBundle,
        "native runtime preserves its post-jailbreak resource bundle"
    )
}

private func testPostJailbreakEnvironment() {
    let bundle = Bundle(for: NSObject.self)
    let environment = PostJailbreakEnvironment(
        interfaceMode: .lite,
        resourceBundle: bundle
    )
    expect(environment.interfaceMode == .lite, "environment preserves the interface mode")
    expect(environment.resourceBundle === bundle, "environment preserves the resource bundle")
}

expect(RelaxinInterfaceMode.allCases.count == 3, "interface mode remains closed")
testFullMode()
testLiteMode()
testOverlayMode()
testNativeRuntime()
testPostJailbreakEnvironment()

if failures == 0 {
    print("ok interface-mode")
}

exit(failures == 0 ? 0 : 1)

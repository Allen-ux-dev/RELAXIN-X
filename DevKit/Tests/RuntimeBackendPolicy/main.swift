import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let suite = "com.relaxin.tests.runtimebackendpolicy.\(UUID().uuidString)"
guard let defaults = UserDefaults(suiteName: suite) else {
    fatalError("could not create defaults suite")
}
defaults.removePersistentDomain(forName: suite)
let store = RuntimeBackendPolicyStore(defaults: defaults)

require(store.load() == .recommended, "default policy must be Recommended/Stable")
store.setExperimentalEnabled(true)
require(store.load().experimentalEnabled, "experimental opt-in must persist")
store.setPreferredBackendID("experimental.test")
require(store.load().preferredBackendID == "experimental.test", "preferred backend must persist")
store.setExperimentalEnabled(false)
require(!store.load().experimentalEnabled, "experimental opt-in must be revocable")
require(store.load().preferredBackendID == "experimental.test", "preference may remain but resolver still validates eligibility")
store.setPreferredBackendID(nil)
require(store.load().preferredBackendID == nil, "Recommended selection must clear preference")

print("PASS RuntimeBackendPolicy")

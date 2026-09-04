import Foundation

enum RepairPackageManager: String, Codable, Equatable, Hashable, Sendable {
    case sileo
    case zebra
}

enum RepairAction: Equatable, Hashable, Sendable {
    case repairSileo
    case repairZebra
    case repairPackageSources(RepairPackageManager)
    case repairAppRegistration(RepairPackageManager)

    /// Stable vocabulary used by host-side contracts. There is deliberately
    /// no fresh-install operation in the repair subsystem.
    static let allCasesForContract = [
        "repairSileo",
        "repairZebra",
        "repairPackageSources",
        "repairAppRegistration",
    ]
}

struct RepairFinding: Equatable, Hashable, Sendable {
    let code: String
    let message: String
    let blocking: Bool
}

struct RepairPlan: Equatable, Sendable {
    let actions: [RepairAction]
    let findings: [RepairFinding]

    var blockingFindings: [RepairFinding] {
        findings.filter(\.blocking)
    }

    var isActionable: Bool {
        blockingFindings.isEmpty && !actions.isEmpty
    }

    static func derive(
        from snapshot: EnvironmentSnapshot,
        desiredPackageManagers: Set<RepairPackageManager> = []
    ) -> RepairPlan {
        var findings: [RepairFinding] = []
        var actions: [RepairAction] = []

        guard snapshot.target.supported else {
            return RepairPlan(
                actions: [],
                findings: [
                    RepairFinding(
                        code: "unsupported-target",
                        message: snapshot.target.reason ?? "Unsupported target",
                        blocking: true
                    ),
                ]
            )
        }

        if let conflict = snapshot.conflicts.first {
            return RepairPlan(
                actions: [],
                findings: [
                    RepairFinding(
                        code: conflict.code,
                        message: conflict.message,
                        blocking: true
                    ),
                ]
            )
        }

        switch snapshot.bootstrap {
        case .absent:
            findings.append(
                RepairFinding(
                    code: "bootstrap-absent",
                    message: "No verified RELAXIN-X bootstrap is available to repair.",
                    blocking: true
                )
            )
        case .incomplete(let reason):
            findings.append(
                RepairFinding(
                    code: "bootstrap-incomplete",
                    message: reason,
                    blocking: true
                )
            )
        case .ambiguous(let count):
            findings.append(
                RepairFinding(
                    code: "bootstrap-ambiguous",
                    message: "Found \(count) candidate bootstrap roots.",
                    blocking: true
                )
            )
        case .validRelaxin:
            break
        }

        guard findings.allSatisfy({ !$0.blocking }) else {
            return RepairPlan(actions: [], findings: findings)
        }

        guard snapshot.runtime.active else {
            findings.append(
                RepairFinding(
                    code: "runtime-inactive",
                    message: "Restore the jailbreak runtime before repairing installed components.",
                    blocking: true
                )
            )
            return RepairPlan(actions: [], findings: findings)
        }

        appendRepair(
            manager: .sileo,
            health: snapshot.packageManagers.sileo,
            actions: &actions,
            findings: &findings
        )
        appendRepair(
            manager: .zebra,
            health: snapshot.packageManagers.zebra,
            actions: &actions,
            findings: &findings
        )

        let bothAbsent: Bool = {
            if case .notInstalled = snapshot.packageManagers.sileo,
               case .notInstalled = snapshot.packageManagers.zebra
            {
                return true
            }
            return false
        }()
        if bothAbsent {
            guard !desiredPackageManagers.isEmpty else {
                findings.append(
                    RepairFinding(
                        code: "package-manager-missing",
                        message: "No installed package manager could be verified.",
                        blocking: true
                    )
                )
                actions.removeAll()
                return RepairPlan(actions: actions, findings: findings)
            }

            findings.append(
                RepairFinding(
                    code: "package-manager-missing",
                    message: "No installed package manager could be verified; restoring the selected package manager configuration.",
                    blocking: false
                )
            )
            if desiredPackageManagers.contains(.sileo) {
                actions.append(.repairSileo)
            }
            if desiredPackageManagers.contains(.zebra) {
                actions.append(.repairZebra)
            }
        }

        // Derivation is deterministic and must never duplicate a mutation.
        var seen = Set<RepairAction>()
        actions = actions.filter { seen.insert($0).inserted }
        return RepairPlan(actions: actions, findings: findings)
    }

    private static func appendRepair(
        manager: RepairPackageManager,
        health: PackageManagerComponentHealth,
        actions: inout [RepairAction],
        findings: inout [RepairFinding]
    ) {
        switch health {
        case .notInstalled, .healthy:
            return
        case .degraded(let reason):
            findings.append(
                RepairFinding(
                    code: "\(manager.rawValue)-degraded",
                    message: reason,
                    blocking: false
                )
            )
            if reason.contains("sources_missing") {
                actions.append(.repairPackageSources(manager))
            } else if reason.contains("registration_missing") {
                actions.append(.repairAppRegistration(manager))
            } else {
                actions.append(manager == .sileo ? .repairSileo : .repairZebra)
            }
        case .repairRequired(let reason):
            findings.append(
                RepairFinding(
                    code: "\(manager.rawValue)-repair-required",
                    message: reason,
                    blocking: false
                )
            )
            actions.append(manager == .sileo ? .repairSileo : .repairZebra)
        }
    }
}

import ProjectDescription

let project = Project(
    name: "Moremaid",
    targets: [
        .target(
            name: "Moremaid",
            destinations: .macOS,
            product: .app,
            bundleId: "com.moremaid.app",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "LSUIElement": .boolean(true),
                "CFBundleDisplayName": "Moremaid",
                "CFBundleShortVersionString": "1.0.0",
            ]),
            sources: ["Sources/**"],
            resources: ["Resources/**"],
            dependencies: [
                .external(name: "FlyingFox"),
                .external(name: "ZIPFoundation"),
            ],
            settings: .settings(
                base: [
                    "SWIFT_VERSION": "6.0",
                    "SWIFT_STRICT_CONCURRENCY": "complete",
                    "CODE_SIGN_ENTITLEMENTS": "Moremaid.entitlements",
                ]
            )
        ),
        .target(
            name: "MoremaidTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.moremaid.app.tests",
            deploymentTargets: .macOS("14.0"),
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "Moremaid"),
            ]
        ),
    ]
)

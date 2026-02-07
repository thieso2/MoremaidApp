import ProjectDescription

let project = Project(
    name: "Moremaid",
    targets: [
        .target(
            name: "Moremaid",
            destinations: .macOS,
            product: .app,
            bundleId: "com.moremaid.app",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Moremaid",
                "CFBundleShortVersionString": "1.0.0",
                "CFBundleDocumentTypes": .array([
                    .dictionary([
                        "CFBundleTypeName": "Markdown",
                        "CFBundleTypeRole": "Viewer",
                        "LSHandlerRank": "Alternate",
                        "LSItemContentTypes": .array([
                            "net.daringfireball.markdown",
                            "public.plain-text",
                        ]),
                    ]),
                    .dictionary([
                        "CFBundleTypeName": "Folder",
                        "CFBundleTypeRole": "Viewer",
                        "LSHandlerRank": "Alternate",
                        "LSItemContentTypes": .array([
                            "public.folder",
                        ]),
                    ]),
                    .dictionary([
                        "CFBundleTypeName": "All Files",
                        "CFBundleTypeRole": "Viewer",
                        "LSHandlerRank": "None",
                        "LSItemContentTypes": .array([
                            "public.item",
                        ]),
                    ]),
                ]),
            ]),
            sources: ["Sources/**"],
            resources: ["Resources/**"],
            dependencies: [
                .external(name: "ZIPFoundation"),
                .target(name: "MoremaidQuickLook"),
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
            name: "MoremaidQuickLook",
            destinations: .macOS,
            product: .appExtension,
            bundleId: "com.moremaid.app.quicklook",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleShortVersionString": "1.0.0",
                "NSExtension": .dictionary([
                    "NSExtensionPointIdentifier": "com.apple.quicklook.preview",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).PreviewProvider",
                ]),
                "QLSupportedContentTypes": .array([
                    "net.daringfireball.markdown",
                    "public.plain-text",
                ]),
                "QLSupportsSearchableItems": true,
            ]),
            sources: ["QuickLook/**"],
            resources: ["QuickLook/Resources/**"],
            dependencies: [],
            settings: .settings(
                base: [
                    "SWIFT_VERSION": "6.0",
                    "SWIFT_STRICT_CONCURRENCY": "complete",
                ]
            )
        ),
        .target(
            name: "MoremaidTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.moremaid.app.tests",
            deploymentTargets: .macOS("26.0"),
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "Moremaid"),
            ]
        ),
    ]
)

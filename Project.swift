import ProjectDescription

let project = Project(
    name: "Moremaid",
    targets: [
        .target(
            name: "Moremaid",
            destinations: .macOS,
            product: .app,
            bundleId: "de.tmp8.moremaid",
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
            scripts: [
                .post(
                    script: """
                    mkdir -p "${BUILT_PRODUCTS_DIR}/Moremaid.app/Contents/SharedSupport/bin"
                    cp "${BUILT_PRODUCTS_DIR}/mm" "${BUILT_PRODUCTS_DIR}/Moremaid.app/Contents/SharedSupport/bin/mm"
                    """,
                    name: "Copy CLI to SharedSupport",
                    basedOnDependencyAnalysis: false
                ),
            ],
            dependencies: [
                .external(name: "ZIPFoundation"),
                .target(name: "MoremaidQuickLook"),
                .target(name: "MoremaidCLI"),
            ],
            settings: .settings(
                base: [
                    "SWIFT_VERSION": "6.0",
                    "SWIFT_STRICT_CONCURRENCY": "complete",
                    "CODE_SIGN_ENTITLEMENTS": "Moremaid.entitlements",
                    "CODE_SIGN_STYLE": "Automatic",
                    "DEVELOPMENT_TEAM": "6629AD7A87",
                ]
            )
        ),
        .target(
            name: "MoremaidCLI",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "de.tmp8.moremaid.cli",
            deploymentTargets: .macOS("26.0"),
            sources: ["CLI/**"],
            settings: .settings(
                base: [
                    "SWIFT_VERSION": "6.0",
                    "PRODUCT_NAME": "mm",
                ]
            )
        ),
        .target(
            name: "MoremaidQuickLook",
            destinations: .macOS,
            product: .appExtension,
            bundleId: "de.tmp8.moremaid.quicklook",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleShortVersionString": "1.0.0",
                "NSExtension": .dictionary([
                    "NSExtensionPointIdentifier": "com.apple.quicklook.preview",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).PreviewProvider",
                    "NSExtensionAttributes": .dictionary([
                        "QLSupportedContentTypes": .array([
                            "net.daringfireball.markdown",
                        ]),
                        "QLSupportsSearchableItems": false,
                        "QLIsDataBasedPreview": true,
                    ]),
                ]),
            ]),
            sources: ["QuickLook/**"],
            resources: ["QuickLook/Resources/**"],
            dependencies: [],
            settings: .settings(
                base: [
                    "SWIFT_VERSION": "6.0",
                    "SWIFT_STRICT_CONCURRENCY": "complete",
                    "CODE_SIGN_ENTITLEMENTS": "MoremaidQuickLook.entitlements",
                    "CODE_SIGN_STYLE": "Automatic",
                    "DEVELOPMENT_TEAM": "6629AD7A87",
                ]
            )
        ),
        .target(
            name: "MoremaidTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "de.tmp8.moremaid.tests",
            deploymentTargets: .macOS("26.0"),
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "Moremaid"),
            ]
        ),
    ]
)

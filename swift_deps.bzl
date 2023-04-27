load("@rules_swift_package_manager//swiftpkg:defs.bzl", "swift_package")

def swift_dependencies():
    # version: 2.1.3
    swift_package(
        name = "swiftpkg_factory",
        commit = "1276137960e14561473f2dfe72b9ccf3a2e03690",
        dependencies_index = "@//:swift_deps_index.json",
        remote = "https://github.com/hmlongco/Factory",
    )

    # version: 2.6.1
    swift_package(
        name = "swiftpkg_floatingpanel",
        commit = "2a29cb5b3ecf4beb67cf524a030dd74a11b956c4",
        dependencies_index = "@//:swift_deps_index.json",
        remote = "https://github.com/scenee/FloatingPanel",
    )

    # branch: master
    swift_package(
        name = "swiftpkg_grdb.swift",
        commit = "655570181518ac25f7efccb83d50f86c82ee5ac5",
        dependencies_index = "@//:swift_deps_index.json",
        remote = "https://github.com/denis15yo/GRDB.swift.git",
    )

    # version: 1.2.0
    swift_package(
        name = "swiftpkg_lnextensionexecutor",
        commit = "16b741f659e344f4569c9f9d32ef2298ef0233ff",
        dependencies_index = "@//:swift_deps_index.json",
        remote = "https://github.com/LeoNatan/LNExtensionExecutor",
    )

    # branch: develop
    swift_package(
        name = "swiftpkg_nicegram_assistant_ios",
        commit = "9be55dd7e8a2852dd72c4fb1e4cd177495313472",
        dependencies_index = "@//:swift_deps_index.json",
        remote = "git@bitbucket.org:mobyrix/nicegram-assistant-ios.git",
    )

    # version: 5.15.5
    swift_package(
        name = "swiftpkg_sdwebimage",
        commit = "20df851f2ae27efbaeeff73e9babdf4fd839a144",
        dependencies_index = "@//:swift_deps_index.json",
        remote = "https://github.com/SDWebImage/SDWebImage.git",
    )

    # version: 5.6.0
    swift_package(
        name = "swiftpkg_snapkit",
        commit = "f222cbdf325885926566172f6f5f06af95473158",
        dependencies_index = "@//:swift_deps_index.json",
        remote = "https://github.com/SnapKit/SnapKit.git",
    )

    # version: 0.16.4
    swift_package(
        name = "swiftpkg_swiftystorekit",
        commit = "9ce911639680113dac9b554d6243e406a9758ebe",
        dependencies_index = "@//:swift_deps_index.json",
        remote = "https://github.com/bizz84/SwiftyStoreKit.git",
    )

// swift-tools-version: 6.2
// Fixture for R14 (PRD-AF-10): a dependency pinned to a branch instead of a tag. Never
// built — plain text read by ArchLintTests.swift and fed to `RuleEngine.checkR14`.
import PackageDescription

let package = Package(
    name: "MultiFixture",
    dependencies: [
        .package(url: "https://github.com/example/SomeDependency.git", branch: "main")
    ],
    targets: []
)

import Foundation

/// Domain: the shared vocabulary of this app — plain models and protocols, no SwiftUI/
/// UIKit, no SDK, no networking (`.archlint.yml`: `allowedImports: [Foundation]`). Every
/// `<Cap>Kit`/`<Sdk>Adapters` this project generates implements a protocol declared here;
/// every feature depends on Domain, never on a Kit/Adapter concrete type directly (R13).
/// See `AGENTS.md` § Módulos de este proyecto for the full dependency table.
public enum Domain {}

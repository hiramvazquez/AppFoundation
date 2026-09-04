import BFeature
import Foundation

/// R13 fixture: `AFeature` importing another feature — forbidden by `"*Feature":
/// forbiddenImports: ["*Feature", ...]` in `Fixtures/Multi/.archlint.yml`.
struct AFeatureThing {}

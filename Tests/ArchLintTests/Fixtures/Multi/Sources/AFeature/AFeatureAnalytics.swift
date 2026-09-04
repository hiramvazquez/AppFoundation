import Foundation
import FirebaseAnalytics

/// R13 fixture: `AFeature` importing an SDK directly — forbidden by `"*Feature":
/// forbiddenImports: [..., "Firebase*"]` in `Fixtures/Multi/.archlint.yml`. Triggers the
/// Adapter/Kit phrasing of the R13 message (the imported module does not end in "Feature").
struct AFeatureAnalytics {}

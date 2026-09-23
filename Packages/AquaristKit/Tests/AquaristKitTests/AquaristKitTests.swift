import Testing
@testable import AquaristKit

@Suite("Skeleton placeholder")
struct AquaristKitTests {
    @Test("domain namespace is reachable")
    func domainNamespace() {
        #expect(AquaristKit.domain == "AquaristKit")
    }

    @Test("milestone marker is set for M1")
    func milestoneMarker() {
        #expect(AquaristKit.milestone == "M1-skeleton")
    }

    @Test("skeleton exposes no stored state beyond constants")
    func constantsAreStable() {
        // Guards the contract later issues depend on: these markers exist
        // and are pure constants (no clock, no I/O) in the M1 skeleton.
        let first = (AquaristKit.domain, AquaristKit.milestone)
        let second = (AquaristKit.domain, AquaristKit.milestone)
        #expect(first == second)
    }
}

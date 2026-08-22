//
//  AddressSpaceTests.swift
//  MacEngineTests
//
//  Classification is the only judgement the region walk makes, so it is the
//  part worth pinning down. The walk itself is checked against this process.
//

import Darwin
import Foundation
import Testing
@testable import MacEngine

@Suite("Address space")
struct AddressSpaceTests {

    // MARK: - Classification

    @Test("Allocator tags win over everything else")
    func mallocTagsBecomeHeap() {
        let kinds = [VM_MEMORY_MALLOC, VM_MEMORY_MALLOC_TINY, VM_MEMORY_MALLOC_NANO].map {
            AddressSpaceSampler.classify(
                tag: UInt32($0),
                protection: VM_PROT_READ | VM_PROT_WRITE,
                shareMode: UInt8(SM_PRIVATE),
                path: "/some/file/that/should/be/ignored"
            )
        }

        #expect(kinds.allSatisfy { $0 == .heap })
    }

    @Test("Stack is tagged, not inferred")
    func stackTagBecomesStack() {
        let kind = AddressSpaceSampler.classify(
            tag: UInt32(VM_MEMORY_STACK),
            protection: VM_PROT_READ | VM_PROT_WRITE,
            shareMode: UInt8(SM_PRIVATE),
            path: nil
        )

        #expect(kind == .stack)
    }

    @Test("A backing file splits on the execute bit")
    func fileBackedSplitsByProtection() {
        let executable = AddressSpaceSampler.classify(
            tag: 0,
            protection: VM_PROT_READ | VM_PROT_EXECUTE,
            shareMode: UInt8(SM_COW),
            path: "/usr/lib/libSystem.dylib"
        )
        let readable = AddressSpaceSampler.classify(
            tag: 0,
            protection: VM_PROT_READ,
            shareMode: UInt8(SM_COW),
            path: "/usr/share/icu/data"
        )

        #expect(executable == .text)
        #expect(readable == .mappedFile)
    }

    /// The distinction that makes the panel readable: hundreds of gigabytes of
    /// no-access reservation must not be counted as anonymous memory.
    @Test("No-access mappings are reservations, not memory")
    func unreadableAnonymousBecomesReserved() {
        let kind = AddressSpaceSampler.classify(
            tag: 0,
            protection: VM_PROT_NONE,
            shareMode: UInt8(SM_PRIVATE),
            path: nil
        )

        #expect(kind == .reserved)
    }

    @Test("Shared anonymous memory is called shared")
    func sharedAnonymousBecomesShared() {
        let kind = AddressSpaceSampler.classify(
            tag: 0,
            protection: VM_PROT_READ,
            shareMode: UInt8(SM_TRUESHARED),
            path: nil
        )

        #expect(kind == .shared)
    }

    @Test("Every kind carries a label and an explanation")
    func everyKindIsDocumented() {
        #expect(RegionKind.allCases.allSatisfy { !$0.title.isEmpty && !$0.explanation.isEmpty })
    }

    // MARK: - The walk, against this process

    @Test("This process maps far more than it makes resident")
    func liveWalkFindsTheProcessItRunsIn() {
        let map = AddressSpaceSampler().sample()

        #expect(map.processIdentifier == ProcessInfo.processInfo.processIdentifier)
        #expect(map.regionCount > 0)
        #expect(map.residentBytes > 0)
        #expect(map.virtualBytes > map.residentBytes)
        #expect(!map.wasTruncated)
    }

    @Test("A Swift process always has a heap and executable pages")
    func liveWalkFindsHeapAndText() {
        let map = AddressSpaceSampler().sample()
        let kinds = Set(map.groups.map(\.kind))

        #expect(kinds.contains(.heap))
        #expect(kinds.contains(.text))
    }

    @Test("Residency never exceeds the mapping it is measured against")
    func residencyStaysWithinBounds() {
        let map = AddressSpaceSampler().sample()

        #expect(map.groups.allSatisfy { $0.residentBytes <= $0.virtualBytes })
        #expect(map.groups.allSatisfy { (0...1).contains($0.residency) })
    }
}

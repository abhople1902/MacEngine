//
//  AddressSpaceSampler.swift
//  MacEngine
//
//  Walks a task's VM regions with `mach_vm_region_recurse` and folds them into
//  the groups `AddressSpaceMap` reports.
//
//  The task is always `mach_task_self_`. There is no pid parameter on purpose:
//  the only way to get another process's task port is `task_for_pid`, and the
//  moment this function took a pid it would grow one.
//

import OSLog
import Darwin
import Foundation

nonisolated struct AddressSpaceSampler {
    /// Ceiling on the walk. A healthy process has a few hundred regions; a
    /// runaway one should not be able to stall the sampler.
    static let regionLimit = 20_000

    /// Tags the malloc zones stamp on their own regions.
    private static let mallocTags: Set<UInt32> = [
        UInt32(VM_MEMORY_MALLOC),
        UInt32(VM_MEMORY_MALLOC_SMALL),
        UInt32(VM_MEMORY_MALLOC_LARGE),
        UInt32(VM_MEMORY_MALLOC_HUGE),
        UInt32(VM_MEMORY_SBRK),
        UInt32(VM_MEMORY_REALLOC),
        UInt32(VM_MEMORY_MALLOC_TINY),
        UInt32(VM_MEMORY_MALLOC_LARGE_REUSABLE),
        UInt32(VM_MEMORY_MALLOC_LARGE_REUSED),
        UInt32(VM_MEMORY_MALLOC_NANO),
        UInt32(VM_MEMORY_MALLOC_MEDIUM)
    ]

    func sample() -> AddressSpaceMap {
        let pageSize = UInt64(vm_kernel_page_size)
        let pid = ProcessInfo.processInfo.processIdentifier

        var totals: [RegionKind: (count: Int, virtual: UInt64, resident: UInt64, swapped: UInt64)] = [:]
        var address: mach_vm_address_t = 0
        var depth: UInt32 = 1
        var walked = 0
        var pathBuffer = [CChar](repeating: 0, count: 1024)

        while walked < Self.regionLimit {
            var size: mach_vm_size_t = 0
            var info = vm_region_submap_info_64()
            var infoCount = mach_msg_type_number_t(
                MemoryLayout<vm_region_submap_info_64>.size / MemoryLayout<natural_t>.size
            )

            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: Int32.self, capacity: Int(infoCount)) { rebound in
                    mach_vm_region_recurse(mach_task_self_, &address, &size, &depth, rebound, &infoCount)
                }
            }

            // KERN_INVALID_ADDRESS is the ordinary way this loop ends: there is
            // nothing mapped at or above `address`.
            guard result == KERN_SUCCESS else { break }

            // A submap is a container, not a mapping. Descend and re-read the
            // same address one level down.
            if info.is_submap != 0 {
                depth += 1
                continue
            }

            let named = proc_regionfilename(pid, address, &pathBuffer, UInt32(pathBuffer.count))
            let path = named > 0 ? String(cString: pathBuffer) : nil

            let kind = Self.classify(
                tag: info.user_tag,
                protection: info.protection,
                shareMode: info.share_mode,
                path: path
            )

            var bucket = totals[kind] ?? (0, 0, 0, 0)
            bucket.count += 1
            bucket.virtual &+= UInt64(size)
            bucket.resident &+= UInt64(info.pages_resident) * pageSize
            bucket.swapped &+= UInt64(info.pages_swapped_out) * pageSize
            totals[kind] = bucket

            address &+= mach_vm_address_t(size)
            walked += 1
        }

        return AddressSpaceMap(
            processIdentifier: pid,
            processName: ProcessInfo.processInfo.processName,
            sampledAt: Date(),
            groups: RegionKind.allCases.compactMap { kind in
                guard let bucket = totals[kind] else { return nil }
                return RegionGroup(
                    kind: kind,
                    regionCount: bucket.count,
                    virtualBytes: bucket.virtual,
                    residentBytes: bucket.resident,
                    swappedBytes: bucket.swapped
                )
            },
            wasTruncated: walked >= Self.regionLimit
        )
    }

    /// Order matters: the allocator's own tags are the most reliable signal, a
    /// backing file is the next most reliable, and no-access reservations have
    /// to be separated from real anonymous memory or they swamp the totals.
    static func classify(
        tag: UInt32,
        protection: vm_prot_t,
        shareMode: UInt8,
        path: String?
    ) -> RegionKind {
        if mallocTags.contains(tag) { return .heap }
        if tag == UInt32(VM_MEMORY_STACK) { return .stack }

        if let path, !path.isEmpty {
            return (protection & VM_PROT_EXECUTE) != 0 ? .text : .mappedFile
        }

        if protection == VM_PROT_NONE { return .reserved }
        if shareMode == UInt8(SM_TRUESHARED) || shareMode == UInt8(SM_SHARED) { return .shared }
        return .other
    }
}

//
//  ProcessEnumerator.h
//  macengine-cli
//
//  Objective-C because the API underneath is C, and the C is the awkward part.
//
//  `proc_listpids` is a two-call dance: ask with a null buffer to learn the
//  size, allocate, ask again — and the answer can grow between the two calls,
//  so the second result must be trusted over the first. Doing that in Swift
//  means UnsafeMutablePointer, manual capacity arithmetic and a deallocate on
//  every exit path. In Objective-C it is malloc/free next to the call that
//  needs it, and Swift gets a clean array of value objects with no unsafe
//  types crossing the boundary.
//
//  This is also the honest answer to "where did you use Objective-C": at the
//  C boundary, which is what it is still genuinely good at.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One live process, as much as an unprivileged caller can see of it.
@interface ProcessEntry : NSObject

@property (nonatomic, readonly) pid_t processIdentifier;
@property (nonatomic, readonly, copy) NSString *name;
/// Resident size in bytes, from `proc_pid_rusage`.
@property (nonatomic, readonly) uint64_t residentBytes;

@end

@interface ProcessEnumerator : NSObject

/// Every pid the caller may inspect, heaviest first, capped at `limit`.
///
/// Processes that refuse `proc_pid_rusage` are skipped rather than reported as
/// zero: on a stock machine a handful of system processes always refuse, and
/// listing them at 0 MB would be a worse lie than omitting them.
+ (NSArray<ProcessEntry *> *)topProcessesByResidentSize:(NSUInteger)limit
    NS_SWIFT_NAME(topProcesses(byResidentSize:));

@end

NS_ASSUME_NONNULL_END

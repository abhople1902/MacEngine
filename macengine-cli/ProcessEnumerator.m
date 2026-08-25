//
//  ProcessEnumerator.m
//  macengine-cli
//

#import "ProcessEnumerator.h"

#import <libproc.h>
#import <sys/proc_info.h>
#import <sys/sysctl.h>

@implementation ProcessEntry

- (instancetype)initWithPid:(pid_t)pid name:(NSString *)name resident:(uint64_t)resident {
    self = [super init];
    if (self) {
        _processIdentifier = pid;
        _name = [name copy];
        _residentBytes = resident;
    }
    return self;
}

@end

@implementation ProcessEnumerator

/// The two-call dance. `proc_listpids` returns a byte count, not a pid count,
/// and the process table can grow between the sizing call and the real one —
/// so the buffer is deliberately over-allocated and the *second* return value
/// decides how much of it is valid.
+ (nullable NSData *)livePidBuffer {
    int sized = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (sized <= 0) {
        return nil;
    }

    // Headroom for processes spawned since the sizing call.
    size_t capacity = (size_t)sized + (32 * sizeof(pid_t));
    pid_t *pids = malloc(capacity);
    if (pids == NULL) {
        return nil;
    }

    int used = proc_listpids(PROC_ALL_PIDS, 0, pids, (int)capacity);
    if (used <= 0) {
        free(pids);
        return nil;
    }

    NSData *buffer = [NSData dataWithBytes:pids length:(NSUInteger)used];
    free(pids);
    return buffer;
}

+ (NSString *)nameForPid:(pid_t)pid {
    struct proc_bsdinfo info;
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, PROC_PIDTBSDINFO_SIZE) == PROC_PIDTBSDINFO_SIZE) {
        // comm is a fixed 16-byte field and is not guaranteed NUL-terminated.
        return [[NSString alloc] initWithBytes:info.pbi_comm
                                        length:strnlen(info.pbi_comm, sizeof(info.pbi_comm))
                                      encoding:NSUTF8StringEncoding] ?: @"?";
    }
    return @"?";
}

+ (NSArray<ProcessEntry *> *)topProcessesByResidentSize:(NSUInteger)limit {
    NSData *buffer = [self livePidBuffer];
    if (buffer == nil) {
        return @[];
    }

    const pid_t *pids = buffer.bytes;
    NSUInteger count = buffer.length / sizeof(pid_t);
    NSMutableArray<ProcessEntry *> *entries = [NSMutableArray arrayWithCapacity:count];

    for (NSUInteger i = 0; i < count; i++) {
        pid_t pid = pids[i];
        if (pid <= 0) {
            continue;
        }

        struct rusage_info_v4 usage;
        // Refusal is normal for processes this user does not own; skip rather
        // than report a zero that looks like a measurement.
        if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&usage) != 0) {
            continue;
        }

        [entries addObject:[[ProcessEntry alloc] initWithPid:pid
                                                       name:[self nameForPid:pid]
                                                   resident:usage.ri_resident_size]];
    }

    [entries sortUsingComparator:^NSComparisonResult(ProcessEntry *a, ProcessEntry *b) {
        if (a.residentBytes == b.residentBytes) {
            return NSOrderedSame;
        }
        return a.residentBytes > b.residentBytes ? NSOrderedAscending : NSOrderedDescending;
    }];

    if (entries.count > limit) {
        return [entries subarrayWithRange:NSMakeRange(0, limit)];
    }
    return entries;
}

@end

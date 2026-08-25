#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ProcessEntry : NSObject

@property (nonatomic, readonly) pid_t processIdentifier;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) uint64_t residentBytes;

@end

@interface ProcessEnumerator : NSObject

+ (NSArray<ProcessEntry *> *)topProcessesByResidentSize:(NSUInteger)limit
    NS_SWIFT_NAME(topProcesses(byResidentSize:));

@end

NS_ASSUME_NONNULL_END

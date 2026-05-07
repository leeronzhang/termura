#import "XPCMailboxItem.h"

@implementation XPCMailboxItem

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithRecordName:(NSString *)recordName
                         createdAt:(NSDate *)createdAt
                    sourceDeviceID:(NSUUID *)sourceDeviceID
                       payloadKind:(NSString *)payloadKind
                       payloadData:(NSData *)payloadData
                     schemaVersion:(NSInteger)schemaVersion {
    self = [super init];
    if (self) {
        _recordName = [recordName copy];
        _createdAt = [createdAt copy];
        _sourceDeviceID = [sourceDeviceID copy];
        _payloadKind = [payloadKind copy];
        _payloadData = [payloadData copy];
        _schemaVersion = schemaVersion;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    NSString *recordName = [coder decodeObjectOfClass:[NSString class] forKey:@"recordName"];
    NSDate *createdAt = [coder decodeObjectOfClass:[NSDate class] forKey:@"createdAt"];
    NSUUID *sourceDeviceID = [coder decodeObjectOfClass:[NSUUID class] forKey:@"sourceDeviceID"];
    NSString *payloadKind = [coder decodeObjectOfClass:[NSString class] forKey:@"payloadKind"];
    NSData *payloadData = [coder decodeObjectOfClass:[NSData class] forKey:@"payloadData"];
    NSInteger schemaVersion = [coder decodeIntegerForKey:@"schemaVersion"];

    if (!recordName || !createdAt || !sourceDeviceID || !payloadKind || !payloadData) {
        return nil;
    }

    return [self initWithRecordName:recordName
                          createdAt:createdAt
                     sourceDeviceID:sourceDeviceID
                        payloadKind:payloadKind
                        payloadData:payloadData
                      schemaVersion:schemaVersion];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.recordName forKey:@"recordName"];
    [coder encodeObject:self.createdAt forKey:@"createdAt"];
    [coder encodeObject:self.sourceDeviceID forKey:@"sourceDeviceID"];
    [coder encodeObject:self.payloadKind forKey:@"payloadKind"];
    [coder encodeObject:self.payloadData forKey:@"payloadData"];
    [coder encodeInteger:self.schemaVersion forKey:@"schemaVersion"];
}

@end

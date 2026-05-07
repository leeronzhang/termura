#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// PR8 Phase 2 — NSSecureCoding marshaling class that carries one
// `AgentMailboxItem`'s fields across NSXPC. The Swift wire struct
// `AgentMailboxItem` (in TermuraRemoteProtocol) is the canonical
// shape; this class is the on-the-wire bridge. Field roles:
//
//   * recordName     — diagnostics + gateway.delete(recordName:)
//                      addressing + quarantine table key. Never used
//                      for cursor advancement.
//   * createdAt      — single source of truth for cursor advancement
//                      (gateway.fetch(since: Date) keys on Date).
//                      Never used for record identity.
//   * sourceDeviceID — cloudSourceDeviceId domain only (the
//                      public-key-derived id, not the random
//                      pairedDeviceId).
//   * payloadKind    — @"plaintext" | @"cipher". Discriminator for the
//                      ingress decoder. Strings (not enum) so the
//                      wire shape doesn't need a custom NSCoding case.
//   * payloadData    — `.plaintext` => JSON-encoded Envelope;
//                      `.cipher` => JSON-encoded CipherBlob.
//   * schemaVersion  — bumped on incompatible field changes; readers
//                      reject mismatched versions.
@interface XPCMailboxItem : NSObject <NSSecureCoding>

@property (nonatomic, copy, readonly) NSString *recordName;
@property (nonatomic, copy, readonly) NSDate *createdAt;
@property (nonatomic, copy, readonly) NSUUID *sourceDeviceID;
@property (nonatomic, copy, readonly) NSString *payloadKind;
@property (nonatomic, copy, readonly) NSData *payloadData;
@property (nonatomic, assign, readonly) NSInteger schemaVersion;

- (instancetype)initWithRecordName:(NSString *)recordName
                         createdAt:(NSDate *)createdAt
                    sourceDeviceID:(NSUUID *)sourceDeviceID
                       payloadKind:(NSString *)payloadKind
                       payloadData:(NSData *)payloadData
                     schemaVersion:(NSInteger)schemaVersion NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

//  Created by Frederic Jacobs on 15/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSOutgoingMessage.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import "TSGroupThread.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSOutgoingMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                      messageBody:(NSString *)body
                    attachmentIds:(NSMutableArray<NSString *> *)attachmentIds
{
    self = [super initWithTimestamp:timestamp inThread:thread messageBody:body attachmentIds:attachmentIds];

    if (!self) {
        return self;
    }

    _messageState = TSOutgoingMessageStateAttemptingOut;
    _hasSyncedTranscript = NO;

    if ([thread isKindOfClass:[TSGroupThread class]]) {
        self.groupMetaMessage = TSGroupMessageDeliver;
    } else {
        self.groupMetaMessage = TSGroupMessageNone;
    }

    return self;
}

- (nullable NSString *)recipientIdentifier
{
    return self.thread.contactIdentifier;
}

- (OWSSignalServiceProtosDataMessage *)buildDataMessage
{
    TSThread *thread = self.thread;

    OWSSignalServiceProtosDataMessageBuilder *builder = [OWSSignalServiceProtosDataMessageBuilder new];
    [builder setBody:self.body];
    BOOL attachmentWasGroupAvatar = NO;
    if ([thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *gThread = (TSGroupThread *)thread;
        OWSSignalServiceProtosGroupContextBuilder *groupBuilder = [OWSSignalServiceProtosGroupContextBuilder new];

        switch (self.groupMetaMessage) {
            case TSGroupMessageQuit:
                [groupBuilder setType:OWSSignalServiceProtosGroupContextTypeQuit];
                break;
            case TSGroupMessageUpdate:
            case TSGroupMessageNew: {
                if (gThread.groupModel.groupImage != nil && self.attachmentIds.count == 1) {
                    attachmentWasGroupAvatar = YES;
                    [groupBuilder setAvatarBuilder:[self attachmentBuilderForAttachmentId:self.attachmentIds[0]]];
                }

                [groupBuilder setMembersArray:gThread.groupModel.groupMemberIds];
                [groupBuilder setName:gThread.groupModel.groupName];
                [groupBuilder setType:OWSSignalServiceProtosGroupContextTypeUpdate];
                break;
            }
            default:
                [groupBuilder setType:OWSSignalServiceProtosGroupContextTypeDeliver];
                break;
        }
        [groupBuilder setId:gThread.groupModel.groupId];
        [builder setGroup:groupBuilder.build];
    }
    if (!attachmentWasGroupAvatar) {
        NSMutableArray *attachments = [NSMutableArray new];
        for (NSString *attachmentId in self.attachmentIds) {
            OWSSignalServiceProtosAttachmentPointerBuilder *attachmentBuilder =
                [self attachmentBuilderForAttachmentId:attachmentId];
            [attachments addObject:[attachmentBuilder build]];
        }
        [builder setAttachmentsArray:attachments];
    }
    return [builder build];
}

- (NSData *)buildPlainTextData
{
    return [[self buildDataMessage] data];
}

- (BOOL)shouldSyncTranscript
{
    return !self.hasSyncedTranscript;
}

- (OWSSignalServiceProtosAttachmentPointerBuilder *)attachmentBuilderForAttachmentId:(NSString *)attachmentId
{
    TSAttachment *attachment = [TSAttachmentStream fetchObjectWithUniqueID:attachmentId];
    if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
        DDLogError(@"Unexpected type for attachment builder: %@", attachment);
        return nil;
    }
    TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;

    OWSSignalServiceProtosAttachmentPointerBuilder *builder = [OWSSignalServiceProtosAttachmentPointerBuilder new];
    [builder setId:[attachmentStream.identifier unsignedLongLongValue]];
    [builder setContentType:attachmentStream.contentType];
    [builder setKey:attachmentStream.encryptionKey];

    return builder;
}

@end

NS_ASSUME_NONNULL_END

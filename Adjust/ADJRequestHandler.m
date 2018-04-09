//
//  ADJRequestHandler.m
//  Adjust
//
//  Created by Christian Wellenbrock on 2013-07-04.
//  Copyright (c) 2013 adjust GmbH. All rights reserved.
//

#import "ADJUtil.h"
#import "ADJLogger.h"
#import "ADJActivityKind.h"
#import "ADJAdjustFactory.h"
#import "ADJPackageBuilder.h"
#import "ADJActivityPackage.h"
#import "NSString+ADJAdditions.h"

static const char * const kInternalQueueName = "io.adjust.RequestQueue";

@interface ADJRequestHandler()

@property (nonatomic, strong) dispatch_queue_t internalQueue;

@property (nonatomic, weak) id<ADJLogger> logger;

@property (nonatomic, weak) id<ADJPackageHandler> packageHandler;

@property (nonatomic, weak) id<ADJActivityHandler> activityHandler;

@property (nonatomic, copy) NSString *basePath;

@end

@implementation ADJRequestHandler

#pragma mark - Public methods

+ (ADJRequestHandler *)handlerWithPackageHandler:(id<ADJPackageHandler>)packageHandler
                              andActivityHandler:(id<ADJActivityHandler>)activityHandler {
    return [[ADJRequestHandler alloc] initWithPackageHandler:packageHandler
                                          andActivityHandler:activityHandler];
}

- (id)initWithPackageHandler:(id<ADJPackageHandler>)packageHandler
          andActivityHandler:(id<ADJActivityHandler>)activityHandler {
    self = [super init];
    
    if (self == nil) {
        return nil;
    }
    
    self.internalQueue = dispatch_queue_create(kInternalQueueName, DISPATCH_QUEUE_SERIAL);
    self.packageHandler = packageHandler;
    self.activityHandler = activityHandler;
    self.logger = ADJAdjustFactory.logger;
    self.basePath = [packageHandler getBasePath];

    return self;
}

- (void)sendPackage:(ADJActivityPackage *)activityPackage queueSize:(NSUInteger)queueSize {
    [ADJUtil launchInQueue:self.internalQueue
                selfInject:self
                     block:^(ADJRequestHandler* selfI) {
                         [selfI sendI:selfI activityPackage:activityPackage queueSize:queueSize];
                     }];
}

- (void)teardown {
    [ADJAdjustFactory.logger verbose:@"ADJRequestHandler teardown"];
    
    self.logger = nil;
    self.internalQueue = nil;
    self.packageHandler = nil;
}

#pragma mark - Private & helper methods

- (void)sendI:(ADJRequestHandler *)selfI activityPackage:(ADJActivityPackage *)activityPackage queueSize:(NSUInteger)queueSize {
    NSURL *url;
    NSString * baseUrl = [ADJAdjustFactory baseUrl];
    if (selfI.basePath != nil) {
        url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", baseUrl, selfI.basePath]];
    } else {
        url = [NSURL URLWithString:baseUrl];
    }

    [ADJUtil sendPostRequest:url
                   queueSize:queueSize
          prefixErrorMessage:activityPackage.failureMessage
          suffixErrorMessage:@"Will retry later"
             activityPackage:activityPackage
         responseDataHandler:^(ADJResponseData *responseData) {
             if (responseData.jsonResponse == nil) {
                 [selfI.packageHandler closeFirstPackage:responseData activityPackage:activityPackage];
                 
                 return;
             }

             // Check if successfully sent package is GDPR forget me.
             // If yes, disable SDK and flush any potentially stored packages that happened afterwards.
             if (activityPackage.activityKind == ADJActivityKindGdpr) {
                 // TODO: For now accept all answers to GDPR type of package.
                 // if (responseData.success) {
                     // TODO: Dummy string assumption, check with backend.
                     // if ([responseData.message containsString:@"user forgotten"]) {
                         [self.activityHandler setEnabled:NO];
                         [self.packageHandler flush];
                     // }
                 // }
             }

             [selfI.packageHandler sendNextPackage:responseData];
         }];
}

@end

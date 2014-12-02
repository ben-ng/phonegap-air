//
//  OTAApplication_Tests.m
//  OTAApplication Tests
//
//  Created by Ben on 11/22/14.
//
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import "AppUpdate.h"
#import "PersistentURLCache.h"

@interface OTAApplication_Tests : XCTestCase {
    NSObject<UIApplicationDelegate> *appDelegate;
    AppUpdate *appUpdate;
    PersistentURLCache *persistentCache;
}

@end

@implementation OTAApplication_Tests

- (void)setUp {
    [super setUp];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    
    NSURL *OTAUpdatedWWWURL = [NSURL fileURLWithPath:[basePath stringByAppendingString:@"/test_ota_updated_www"] isDirectory:YES];
    NSURL *WWWPrimerURL = [NSURL fileURLWithPath:[basePath stringByAppendingString:@"/test_www_primer"] isDirectory:YES];
    NSURL *cachePrimerURL = [NSURL fileURLWithPath:[basePath stringByAppendingString:@"/test_cache_primer"] isDirectory:YES];
    NSURL *OTAUpdatedCacheURL = [NSURL fileURLWithPath:[basePath stringByAppendingString:@"/test_ota_updated_cache"] isDirectory:YES];
    
    appDelegate = [UIApplication sharedApplication].delegate;
    
    persistentCache = [[PersistentURLCache alloc] initWithMemoryCapacity:8 * 1024 * 1024
                                                            diskCapacity:8 * 1024 * 1024
                                                                diskPath:@"test_persistent_cache"
                                                          cachePrimerURL:cachePrimerURL
                                                      OTAUpdatedCacheURL:OTAUpdatedCacheURL];
    
    appUpdate = [[AppUpdate alloc] initWithOTAUpdatedWWWURL:OTAUpdatedWWWURL
                                               WWWPrimerURL:WWWPrimerURL
                                             cachePrimerURL:cachePrimerURL
                                                      cache:persistentCache];
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

/**
 * Check that at launch, the bundle's contents are copied to the OTA updated www folder
 */
- (void)testAppPrimer {
    
    XCTAssert(YES, @"Pass");
}

@end

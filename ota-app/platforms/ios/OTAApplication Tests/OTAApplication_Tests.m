//
//  OTAApplication_Tests.m
//  OTAApplication Tests
//
//  Created by Ben on 11/22/14.
//
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import "Constants.h"
#import "AppUpdate.h"
#import "PersistentURLCache.h"

@interface OTAApplication_Tests : XCTestCase {
    NSObject<UIApplicationDelegate> *appDelegate;
    
    AppUpdate *appUpdate;
    PersistentURLCache *persistentCache;
    
    NSFileManager *fm;
    NSUserDefaults *defaults;
    
    NSString *basePath;
    
    NSURL *OTAUpdatedWWWURL;
    NSURL *WWWPrimerURL;
    NSURL *cachePrimerURL;
    NSURL *OTAUpdatedCacheURL;
}

@end

@implementation OTAApplication_Tests

- (void)setUp {
    [super setUp];
    
    NSError *error;
    
    defaults = [[NSUserDefaults alloc] init];
    fm = [NSFileManager defaultManager];
    
    NSString *directory = NSHomeDirectory();
    basePath = [directory stringByAppendingPathComponent:@"UnitTestTemp/"];
    
    // Load frequently used URLs up front
    OTAUpdatedWWWURL = [NSURL fileURLWithPath:[basePath stringByAppendingString:@"/test_ota_updated_www"] isDirectory:YES];
    WWWPrimerURL = [NSURL fileURLWithPath:[basePath stringByAppendingString:@"/test_www_primer"] isDirectory:YES];
    cachePrimerURL = [NSURL fileURLWithPath:[basePath stringByAppendingString:@"/test_cache_primer"] isDirectory:YES];
    OTAUpdatedCacheURL = [NSURL fileURLWithPath:[basePath stringByAppendingString:@"/test_ota_updated_cache"] isDirectory:YES];
    
    appDelegate = [UIApplication sharedApplication].delegate;
    
    // Recreate directories
    
    // We don't create this one because it is the job of AppUpdate
    // [fm createDirectoryAtURL:OTAUpdatedWWWURL withIntermediateDirectories:YES attributes:nil error:&error];
    // XCTAssertNil(error);
    
    [fm createDirectoryAtURL:WWWPrimerURL withIntermediateDirectories:YES attributes:nil error:&error];
    XCTAssertNil(error);
    [fm createDirectoryAtURL:cachePrimerURL withIntermediateDirectories:YES attributes:nil error:&error];
    XCTAssertNil(error);
    [fm createDirectoryAtURL:OTAUpdatedCacheURL withIntermediateDirectories:YES attributes:nil error:&error];
    XCTAssertNil(error);
    
    // Wipe out defaults
    [defaults setObject:@"0.0.0" forKey:@"version"];
    [defaults setObject:ProductionURL forKey:@"rootURL"];
    
    persistentCache = [[PersistentURLCache alloc] initWithMemoryCapacity:8 * 1024 * 1024
                                                            diskCapacity:8 * 1024 * 1024
                                                                diskPath:@"test_persistent_cache"
                                                          cachePrimerURL:cachePrimerURL
                                                      OTAUpdatedCacheURL:OTAUpdatedCacheURL];
    
    appUpdate = [[AppUpdate alloc] initWithOTAUpdatedWWWURL:OTAUpdatedWWWURL
                                               WWWPrimerURL:WWWPrimerURL
                                             cachePrimerURL:cachePrimerURL
                                                      cache:persistentCache
                                               userDefaults:defaults];
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
    
    NSError *error;
    
    // Empty directories
    [fm removeItemAtPath:basePath error:&error];
    XCTAssertNil(error);
}

/**
 * Check that at launch, the www primer is copied over to the OTA updated directory
 */
- (void)testAppPrimer {
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Primed"];
    
    // Create a file in the WWW primer
    NSString *testFixtureData = @"test data";
    NSURL *primerFixtureURL = [WWWPrimerURL URLByAppendingPathComponent:@"index.html"];
    NSError *error = nil;
    
    [testFixtureData writeToURL:[WWWPrimerURL URLByAppendingPathComponent:@"index.html"] atomically:YES encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNil(error);
    
    XCTAssert([[NSString stringWithContentsOfURL:primerFixtureURL
                                       encoding:NSUTF8StringEncoding
                                          error:&error] isEqualToString:testFixtureData]);
    XCTAssertNil(error);
    
    [appUpdate restoreFromBundleResourcesWithCompletionHandler:^(NSError *error) {
        XCTAssertNil(error);
        XCTAssert([testFixtureData isEqualToString:[NSString stringWithContentsOfURL:[OTAUpdatedWWWURL URLByAppendingPathComponent:@"index.html"] encoding:NSUTF8StringEncoding error:&error]]);
        XCTAssertNil(error);
        [expectation fulfill];
    }];
    
    [self waitForExpectationsWithTimeout:5.0 handler:^(NSError *error) {
        if(error) {
            XCTFail(@"The test fimed out");
        }
    }];
}

/**
 * Check that we can download a fresh app, and that we know when not to download a new version
 */
- (void)testProductionDownload {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Downloaded"];
    
    [appUpdate downloadUpdateWithCompletionHandler:^(NSDictionary *versionInfo, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(versionInfo);
        XCTAssert([(NSString *)[versionInfo objectForKey:@"version"] hasPrefix:@"1.1."]);
        
        [appUpdate downloadUpdateWithCompletionHandler:^(NSDictionary *versionInfoTwo, NSError *error) {
            XCTAssertNotNil(error);
            XCTAssertEqual(error.code, 200); // This is the error code for "no update needed"
            
            XCTAssertNotNil(versionInfo);
            XCTAssert([(NSString *)[versionInfo objectForKey:@"version"] hasPrefix:@"1.1."]);
            
            [expectation fulfill];
        }];
    }];
    
    [self waitForExpectationsWithTimeout:100.0 handler:^(NSError *error) {
        if(error) {
            XCTFail(@"The test fimed out");
        }
    }];
}

/**
 * Check that we can download a fresh app, and always download a new version
 */
- (void)testDevelopmentDownload {
    XCTestExpectation *expectation = [self expectationWithDescription:@"Downloaded"];
    
    [defaults setObject:StagingURL forKey:@"rootURL"];
    
    [appUpdate downloadUpdateWithCompletionHandler:^(NSDictionary *versionInfo, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNotNil(versionInfo);
        XCTAssert([(NSString *)[versionInfo objectForKey:@"version"] hasPrefix:@"1.1."]);
        
        [appUpdate downloadUpdateWithCompletionHandler:^(NSDictionary *versionInfoTwo, NSError *error) {
            XCTAssertNil(error);
            XCTAssertNotNil(versionInfo);
            XCTAssert([(NSString *)[versionInfo objectForKey:@"version"] hasPrefix:@"1.1."]);
            
            [expectation fulfill];
        }];
    }];
    
    [self waitForExpectationsWithTimeout:100.0 handler:^(NSError *error) {
        if(error) {
            XCTFail(@"The test fimed out");
        }
    }];
}

@end

//
//  AppUpdate.h
//  OTAApplication
//
//  Created by Ben on 7/15/14.
//
//

#import <Foundation/Foundation.h>
#import "Constants.h"
#import "PersistentURLCache.h"

@interface AppUpdate : NSObject <NSURLSessionDelegate, NSURLSessionDownloadDelegate, NSFileManagerDelegate>

- (id) initWithOTAUpdatedWWWURL: (NSURL *) OTAUpdatedWWWURL
                   WWWPrimerURL: (NSURL *) WWWPrimerURL
                 cachePrimerURL: (NSURL *) cachePrimerURL
                          cache: (PersistentURLCache *) cache
                   userDefaults: (NSUserDefaults *) userDefaults;

// Gets the latest version information
- (void) getLatestVersionWithCompletionHandler: (void (^)(NSDictionary *versionInfo, NSError *error))completionHandler;

// Downloads and applies the latest version
- (void) downloadUpdateWithCompletionHandler: (void (^)(NSDictionary *versionInfo, NSError *error))completionHandler;

// Primes the OTA updated WWW directory with bundle contents
- (void) restoreFromBundleResourcesWithCompletionHandler: (void (^)(NSError *error))completionHandler;

- (void) cancel;

@end

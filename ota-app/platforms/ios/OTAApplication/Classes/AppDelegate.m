/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

//
//  AppDelegate.m
//  HelloWorld
//
//  Created by ___FULLUSERNAME___ on ___DATE___.
//  Copyright ___ORGANIZATIONNAME___ ___YEAR___. All rights reserved.
//

#import "Constants.h"
#import "AppDelegate.h"
#import "MainViewController.h"

#import <Cordova/CDVPlugin.h>

@interface AppDelegate() {
}

/**
 * Nomenclature:
 *   The "application bundle" is what we actually distribute on the app store. We do not have permission to write here
 *   The "OTAUpdated" URLs refer to the Documents directory, where we do have permission to write to
 *   The "cache" is meant to hold static assets such as images
 *   The "cache primer" is data bundled together with the app to speed up initial load times
 *   "WWW" is the special folder where the phonegap app's web assets lie
 */

// Where app assets are in the application bundle
- (NSURL *) WWWPrimerURL;
// Where the cache primer is in the application bundle
- (NSURL *) cachePrimerURL;
// Where the phonegap app's web assets are in the Documents directory
- (NSURL *) OTAUpdatedWWWURL;
// Where the cache is in the Documents directory
- (NSURL *) OTAUpdatedCacheURL;

@end

@implementation AppDelegate {
    AppUpdate *_appUpdate;
    NSString *_URLScheme;
}

@synthesize window, viewController;

- (id)init
{
    NSHTTPCookieStorage* cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    
    [cookieStorage setCookieAcceptPolicy:NSHTTPCookieAcceptPolicyAlways];
    
    /**
     * We've replaced the standard NSURLCache with the PersistentURLCache, which
     * allows us to avoid internet requests for assets that are already in the cache
     * or in the cache primer
     */
    
    int cacheSizeMemory = 8 * 1024 * 1024; // 8MB
    int cacheSizeDisk = 32 * 1024 * 1024; // 32MB
    
#if __has_feature(objc_arc)
    PersistentURLCache* sharedCache = [[PersistentURLCache alloc] initWithMemoryCapacity:cacheSizeMemory
                                                                            diskCapacity:cacheSizeDisk
                                                                                diskPath:@"persistenturlcache"
                                                                          cachePrimerURL:[self cachePrimerURL]
                                                                      OTAUpdatedCacheURL:[self OTAUpdatedCacheURL]];
#else
    PersistentURLCache* sharedCache = [[[PersistentURLCache alloc] initWithMemoryCapacity:cacheSizeMemory
                                                                             diskCapacity:cacheSizeDisk
                                                                                 diskPath:@"persistenturlcache"
                                                                           cachePrimerURL:[self cachePrimerURL]
                                                                       OTAUpdatedCacheURL:[self OTAUpdatedCacheURL]] autorelease];
#endif
    
    [NSURLCache setSharedURLCache:sharedCache];
    
    /**
     * Initializes the OTA update library. This will perform necesscary set-up
     * like priming the OTA Updated WWW directory with the bundle contents.
     */
    _appUpdate = [[AppUpdate alloc] initWithOTAUpdatedWWWURL:[self OTAUpdatedWWWURL]
                                                WWWPrimerURL:[self WWWPrimerURL]
                                              cachePrimerURL:[self cachePrimerURL]
                                                       cache:sharedCache
                                                userDefaults:[NSUserDefaults standardUserDefaults]];
    
    /**
     * Read the URL Scheme from the plist file
     */
    NSArray *plistPaths = [[NSBundle mainBundle] pathsForResourcesOfType:@"plist" inDirectory:nil];
    
    _URLScheme = nil;
    
    // Find the plist called "Info.plist"
    [plistPaths enumerateObjectsUsingBlock:^(NSString *plistPath, NSUInteger idx, BOOL *stop) {
        if([plistPath hasSuffix:@"Info.plist"]) {
            NSDictionary *plistVals = [[NSDictionary alloc] initWithContentsOfFile:plistPath];
            NSArray *urlTypes = [plistVals objectForKey:@"CFBundleURLTypes"];
            NSDictionary *urlTypeOne = urlTypes.count > 0 ? urlTypes[0] : nil;
            NSArray *urlSchemes = urlTypeOne ? urlTypeOne[@"CFBundleURLSchemes"] : nil;
            _URLScheme = urlSchemes && urlSchemes.count > 0 ? (NSString *) [urlSchemes objectAtIndex:0] : nil;
            *stop = true;
        }
    }];
    
    self = [super init];
    return self;
}

#pragma mark Important Directory Locations
/**
 * See "Nomenclature" near the top of this file for descriptions of these directories
 */

-(NSURL *)OTAUpdatedWWWURL
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    return [NSURL fileURLWithPath:[basePath stringByAppendingString:@"/bundle"] isDirectory:YES];
}

-(NSURL *)OTAUpdatedCacheURL
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    return [NSURL fileURLWithPath:[basePath stringByAppendingString:@"/persist"] isDirectory:YES];
}

-(NSURL *)cachePrimerURL
{
    return [[[NSBundle mainBundle] resourceURL] URLByAppendingPathComponent:@"cache"];
}

-(NSURL *)WWWPrimerURL
{
    return [[[NSBundle mainBundle] resourceURL] URLByAppendingPathComponent:@"www"];
}

#pragma mark UIApplicationDelegate implementation

- (BOOL)application:(UIApplication *)application willFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    /**
     * Suggest to iOS that we check for updates as often as possible
     * The update library is efficient enough that this is cheap to do frequently
     */
    [[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalMinimum];
    return YES;
}

/**
 * This is main kick off after the app inits
 */
- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
    
#if __has_feature(objc_arc)
    self.window = [[UIWindow alloc] initWithFrame:screenBounds];
#else
    self.window = [[[UIWindow alloc] initWithFrame:screenBounds] autorelease];
#endif
    self.window.autoresizesSubviews = YES;
    
#if __has_feature(objc_arc)
    self.viewController = [[MainViewController alloc] initWithOTAUpdatedWWWURL:[self OTAUpdatedWWWURL] appUpdate: _appUpdate URLScheme: _URLScheme];
#else
    self.viewController = [[[MainViewController alloc] initWithOTAUpdatedWWWURL:[self OTAUpdatedWWWURL] appUpdate: self.appUpdate URLScheme: _URLScheme] autorelease];
#endif
    
    self.window.rootViewController = self.viewController;
    
    [self.window makeKeyAndVisible];
    
    return YES;
}

/**
 * Deep linking handler
 */
- (BOOL)application:(UIApplication*)application openURL:(NSURL*)url sourceApplication:(NSString*)sourceApplication annotation:(id)annotation
{
    if (!url) {
        return NO;
    }
    
    // Intercept our scheme and handle it ourselves
    if(_URLScheme != nil && [[url.scheme lowercaseString] isEqualToString:[_URLScheme lowercaseString]]) {
        [self.viewController performSelector:@selector(loadURLWhenPossible:) withObject:url afterDelay:0.3];
    }
    
    /**
     * This is Cordova's built-in, unreliable way of doing deep linking. Unreliable because it assumes
     * the app is ready to handle the link, or that the webview is even loaded. Don't do this.
     * Left here as a cautionary tale.
     
     NSString* jsString = [NSString stringWithFormat:@"handleOpenURL(\"%@\");", url];
     [self.viewController.webView stringByEvaluatingJavaScriptFromString:jsString];
     
     */
    
    // all plugins will get the notification, and their handlers will be called
    [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:CDVPluginHandleOpenURLNotification object:url]];
    
    return YES;
}

// repost all remote and local notification using the default NSNotificationCenter so multiple plugins may respond
- (void)            application:(UIApplication*)application
    didReceiveLocalNotification:(UILocalNotification*)notification
{
    // re-post ( broadcast )
    [[NSNotificationCenter defaultCenter] postNotificationName:CDVLocalNotification object:notification];
}

- (void)                                application:(UIApplication *)application
   didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    // re-post ( broadcast )
    NSString* token = [[[[deviceToken description]
                         stringByReplacingOccurrencesOfString: @"<" withString: @""]
                        stringByReplacingOccurrencesOfString: @">" withString: @""]
                       stringByReplacingOccurrencesOfString: @" " withString: @""];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:CDVRemoteNotification object:token];
}

- (void)                                 application:(UIApplication *)application
    didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    // re-post ( broadcast )
    [[NSNotificationCenter defaultCenter] postNotificationName:CDVRemoteNotificationError object:error];
}

- (NSUInteger)application:(UIApplication*)application supportedInterfaceOrientationsForWindow:(UIWindow*)window
{
    // iPhone doesn't support upside down by default, while the iPad does.  Override to allow all orientations always, and let the root view controller decide what's allowed (the supported orientations mask gets intersected).
    NSUInteger supportedInterfaceOrientations = (1 << UIInterfaceOrientationPortrait) | (1 << UIInterfaceOrientationLandscapeLeft) | (1 << UIInterfaceOrientationLandscapeRight) | (1 << UIInterfaceOrientationPortraitUpsideDown);
    
    return supportedInterfaceOrientations;
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication*)application
{
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
}

/**
 * Uses the app update library to perform an update. Called from the background periodically by iOS.
 */
- (void)application:(UIApplication *)application performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
    NSLog(@"Starting periodic background update from version %@", [[NSUserDefaults standardUserDefaults] valueForKey:@"version"]);
    
    [_appUpdate downloadUpdateWithCompletionHandler:^(NSDictionary *versionInfo, NSError *error) {
        if(error == nil) {
            NSLog(@"Now on (%@)", versionInfo[@"version"]);
            [self.viewController setPendingBackgroundUpdate:YES];
            completionHandler(UIBackgroundFetchResultNewData);
        }
        else {
            NSLog(@"Did not perform background update: %@", error.localizedDescription);
            completionHandler(UIBackgroundFetchResultFailed);
        }
    }];
}

/**
 * Uses the app update library to perform an update when the home button is pressed or the device goes to sleep.
 */
-(void)applicationDidEnterBackground:(UIApplication *)application
{
    UIBackgroundTaskIdentifier backgroundUpdate = 0;
    
    NSLog(@"Starting background update from version %@", [[NSUserDefaults standardUserDefaults] valueForKey:@"version"]);
    
    [_appUpdate downloadUpdateWithCompletionHandler:^(NSDictionary *versionInfo, NSError *error) {
        if(error == nil) {
            NSLog(@"Now on (%@)", versionInfo[@"version"]);
            [self.viewController setPendingBackgroundUpdate:YES];
            [application endBackgroundTask:backgroundUpdate];
        }
        else {
            NSLog(@"Did not perform background update: %@", error.localizedDescription);
            [application endBackgroundTask:backgroundUpdate];
        }
    }];
    
    backgroundUpdate = [application beginBackgroundTaskWithName:@"BackgroundUpdate" expirationHandler:^{
        [_appUpdate cancel];
    }];
}

/**
 * Gives the main view controller a chance to reload the webview to use the latest code before the user sees the app
 */
-(void)applicationWillEnterForeground:(UIApplication *)application
{
    [self.viewController willEnterForeground];
}

@end

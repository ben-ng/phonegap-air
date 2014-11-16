//
//  AppUpdate.m
//  Getable
//
//  Created by Ben on 7/15/14.
//
//

#import "AppUpdate.h"
#import "NSData+MD5.h"
#import "NSFileManager+DoNotBackup.h"
#import <CommonCrypto/CommonDigest.h>

@interface AppUpdate()
{
}

- (void) applyDownloadedFiles;
- (void) reset;

@end

@implementation AppUpdate {
    int _sessionCounter;
    
    NSString *_cachePrimerPath;
    NSURL *_cachePrimerURL;
    NSURL *_WWWPrimerURL;
    NSURL *_OTAUpdatedWWWURL;
    NSURL *_OTAUpdatedCacheURL;
    NSURL *_tempDirURL;
    NSURLSession *_session;
    PersistentURLCache *_cache;
    NSMutableDictionary *_downloadTasks;
    NSString *_targetVersion;
    void (^_proxiedCompletionHandler)(NSError *);
}

- (id)init
{
    self = [self initWithOTAUpdatedWWWURL:nil WWWPrimerURL:nil cachePrimerURL:nil cache:nil];
    _sessionCounter = 0;
    return self;
}

- (id)initWithOTAUpdatedWWWURL:(NSURL *)OTAUpdatedWWWURL
                  WWWPrimerURL:(NSURL *)WWWPrimerURL
                cachePrimerURL:(NSURL *)cachePrimerURL
                         cache:(PersistentURLCache *)cache
{
    self = [super init];
    
    if(self) {
        if(OTAUpdatedWWWURL == nil) {
            [NSException raise:@"OTAUpdatedWWWURL cannot be nil" format:@"OTAUpdatedWWWURL cannot be nil"];
        }
        
        if(WWWPrimerURL == nil) {
            [NSException raise:@"WWWPrimerURL cannot be nil" format:@"WWWPrimerURL cannot be nil"];
        }
        
        if(cache == nil) {
            [NSException raise:@"cache cannot be nil" format:@"cache cannot be nil"];
        }
        
        _OTAUpdatedWWWURL = OTAUpdatedWWWURL;
        _WWWPrimerURL = WWWPrimerURL;
        _cachePrimerURL = cachePrimerURL;
        _cachePrimerPath = cachePrimerURL.absoluteString;
        _OTAUpdatedCacheURL = [cache OTAUpdatedCacheURL];
        _cache = cache;
        
        // Use the /temp directory in caches for unapplied downloads
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
        _tempDirURL = [NSURL fileURLWithPath:[basePath stringByAppendingString:@"/temp"] isDirectory:YES];
        
        // Set up the rootURL if needed
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        
        if([defaults valueForKey:@"rootURL"] == nil) {
            [defaults setValue:ProductionURL forKey:@"rootURL"];
        }
    }
    
    return self;
}

/**
 * We can't write to the app bundle, so move the resources out
 * to somewhere where we can modify them
 */
-(void)restoreFromBundleResourcesWithCompletionHandler:(void (^)(NSError *))completionHandler
{
    NSFileManager *fm = [NSFileManager defaultManager];
    
    [fm setDelegate:self];
    
    NSError *error = nil;
    
    [fm removeItemAtURL:_OTAUpdatedWWWURL error:nil];
    
    [fm copyItemAtURL:_WWWPrimerURL toURL:_OTAUpdatedWWWURL error:&error];
    [fm addSkipBackupAttributeToItemAtURL:_OTAUpdatedWWWURL];
    
    if(error) {
        NSLog(@"Error priming WWW folder from %@ to %@: %@", _WWWPrimerURL.absoluteString, _OTAUpdatedWWWURL.absoluteString, error.localizedDescription);
        completionHandler(error);
    }
    else {
        NSLog(@"WWW primed");
        completionHandler(nil);
    }
    
    error = nil;
}

/**
 * Get the latest version information from the server
 */
- (void)getLatestVersionWithCompletionHandler:(void (^)(NSDictionary *, NSError *))completionHandler
{
    NSURLSession *session = [NSURLSession sharedSession];
    
    NSURL *rootURL = [NSURL URLWithString:[[NSUserDefaults standardUserDefaults] valueForKeyPath:@"rootURL"]];
    NSURLSessionTask *versionTask = [session dataTaskWithURL:[NSURL URLWithString:ManifestPath relativeToURL:rootURL]
                                           completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                               
                                               if(error != nil) {
                                                   completionHandler(nil, error);
                                                   return;
                                               }
                                               
                                               NSError *err = NULL;
                                               NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
                                               
                                               completionHandler(json, err);
                                           }];
    
    // Wtf, you need to call this to start the request?
    [versionTask resume];
}

/**
 * Update the app to the latest version
 */
-(void)downloadUpdateWithCompletionHandler:(void (^)(NSDictionary *, NSError *))completionHandler
{
    _sessionCounter++;
    
    int currentSession = _sessionCounter;
    
    [self getLatestVersionWithCompletionHandler:^(NSDictionary *versionInfo, NSError *error) {
        if(error != nil) {
            return completionHandler(nil, error);
        }
        else {
            
            // Don't run more than one update at a time
            if(_downloadTasks != nil && _downloadTasks.count > 0) {
                return completionHandler(nil, [NSError errorWithDomain:@"GETABLE"
                                                                  code:0
                                                              userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"An update task is already running with %lu pending downloads", (unsigned long)_downloadTasks.count]}
                                               ]);
            }
            else if(_downloadTasks == nil) {
                [self reset];
            }
            
            NSString *rootURLString = [[NSUserDefaults standardUserDefaults] valueForKeyPath:@"rootURL"];
            NSURL *rootURL = [NSURL URLWithString:rootURLString];
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
            _session = [NSURLSession sessionWithConfiguration:sessionConfig delegate:self delegateQueue:[NSOperationQueue mainQueue]];
            
            // Cancel if this takes too long, we get penalized for taking too long!
            // If this is someone's dev machine then give up to 2 mins since we're in dev mode anyway
            unsigned long long delay = [rootURLString hasSuffix:@"8080"] ? 120 * NSEC_PER_SEC : 25 * NSEC_PER_SEC; // The entire operation times out in 25s
            sessionConfig.timeoutIntervalForRequest = [rootURLString hasSuffix:@"8080"] ? 120 : 15; // Individual requests time out in 15s if no data is transferred
            
            // Oh don't you just love objective-c?
            _proxiedCompletionHandler = ^void (NSError *error) {
                // P.S. You can't use self in here because you'll get a retain cycle WTF
                completionHandler(versionInfo, error);
            };
            
            // If the version is the same, and we are in prod mode, don't update
            if([[defaults stringForKey:@"version"] isEqualToString: versionInfo[@"version"]] && [rootURLString isEqualToString:ProductionURL]) {
                // Need to restore the version because we wiped it out to nil
                [defaults setValue:versionInfo[@"version"] forKey:@"version"];
                return completionHandler(versionInfo, [NSError errorWithDomain:@"GETABLE" code:200 userInfo:@{NSLocalizedDescriptionKey: @"Already on latest version"}]);
            }
            // Otherwise, download the update
            else {
                if([defaults stringForKey:@"version"] == nil) {
                    NSLog(@"Downloading new version %@ - %@", versionInfo[@"version"], versionInfo[@"message"]);
                }
                else {
                    NSLog(@"Upgrading from version %@ to %@ - %@", [defaults stringForKey:@"version"], versionInfo[@"version"], versionInfo[@"message"]);
                }
                
                _targetVersion = versionInfo[@"version"];
                
                
                // Iterate through app bundle files and create download tasks
                NSDictionary *files = versionInfo[@"files"];
                
                [files enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *value, BOOL *stop) {
                    // Don't bother downloading files that didn't change
                    NSURL *destination = [_OTAUpdatedWWWURL URLByAppendingPathComponent:value[@"destination"]];
                    NSError *error = nil;
                    NSData *dat = [NSData dataWithContentsOfURL:destination options:0 error:&error];
                    
                    // Download if the file is missing, or if the checksum has changed
                    if(error != nil || ![[dat MD5] isEqualToString:value[@"checksum"]]) {
                        NSURL *resource = [NSURL URLWithString:value[@"source"] relativeToURL:rootURL];
                        NSURLSessionDownloadTask *task = [_session downloadTaskWithURL:resource];
                        task.taskDescription = [NSString stringWithFormat:@"%@: %@", key, value[@"source"]];
                        [_downloadTasks setObject:[NSMutableDictionary dictionaryWithDictionary:@{
                                                                                                  @"task": task,
                                                                                                  @"complete": [NSNumber numberWithBool:NO],
                                                                                                  @"checksum": value[@"checksum"],
                                                                                                  @"destination": destination,
                                                                                                  @"tempLocation": [_tempDirURL URLByAppendingPathComponent:value[@"destination"]]
                                                                                                  }]
                                           forKey:[NSNumber numberWithInteger:task.taskIdentifier]];
                        
                        NSLog(@"Downloading %@", resource.absoluteString);
                    }
                }];
                
                // Now iterate through app assets and create download tasks
                // NOTE: Duplicate assets will fry this thing, so GET RID OF THEM!
                /* Ignore assets for now, they tend to be flaky
                 NSMutableArray *assets = [NSMutableArray arrayWithCapacity:[versionInfo[@"assets"] count]];
                 NSMutableArray *assetKeys = [NSMutableArray arrayWithCapacity:[versionInfo[@"assets"] count]];
                 
                 [versionInfo[@"assets"] enumerateObjectsUsingBlock:^(NSString *assetPath, NSUInteger idx, BOOL *stop) {
                 NSString *assetKey = [_cache cacheKeyForURL:[NSURL URLWithString:assetPath]];
                 if([assetKeys indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
                 return [obj isEqualToString:assetKey];
                 }] == NSNotFound) {
                 [assetKeys addObject:assetKey];
                 [assets addObject:assetPath];
                 }
                 }];
                 
                 [assets enumerateObjectsUsingBlock:^(NSString *value, NSUInteger idx, BOOL *stop) {
                 // Don't bother downloading files that didn't change
                 NSURL *URLToFetch = [NSURL URLWithString:value];
                 NSURL *destination = [_cache persistedDataURLForURL:URLToFetch];
                 NSError *error = nil;
                 
                 [NSData dataWithContentsOfURL:destination options:0 error:&error];
                 
                 // Download if the file is missing
                 if(error != nil) {
                 NSURLSessionDownloadTask *task = [_session downloadTaskWithURL:URLToFetch];
                 task.taskDescription = [NSString stringWithFormat:@"Asset: %@", value];
                 
                 [_downloadTasks setObject:[NSMutableDictionary dictionaryWithDictionary:@{
                 @"task": task,
                 @"complete": [NSNumber numberWithBool:NO],
                 @"destination": [_cache OTAUpdatedPersistedDataURLForURL:URLToFetch],
                 @"tempLocation": [_tempDirURL URLByAppendingPathComponent:[[_cache cacheKeyForURL:URLToFetch] stringByAppendingString:@".persist"]]
                 }]
                 forKey:[NSNumber numberWithInteger:task.taskIdentifier]];
                 
                 // NSLog(@"Asset to be updated: %@", value);
                 }
                 else {
                 // NSLog(@"Asset skipped: %@", value);
                 }
                 }];
                 */
                
                // Iterate through download tasks and start them
                [_downloadTasks enumerateKeysAndObjectsUsingBlock:^(id key, NSDictionary *taskDesc, BOOL *stop) {
                    [taskDesc[@"task"] resume];
                }];
                
                // If there are no download tasks this finishes and cleans up
                [self applyDownloadedFiles];
                
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay), dispatch_get_main_queue(), ^{
                    // There's no easy way to cancel a delayed block, so check if the session has been incremented since this method last ran
                    if(currentSession == _sessionCounter) {
                        [self cancel];
                    }
                });
            }
        }
    }];
}

-(void)applyDownloadedFiles
{
    __block BOOL isCorrupted = NO;
    __block BOOL notFinished = NO;
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if(_downloadTasks.count == 0) {
        // Still set version even if no changes
        [[NSUserDefaults standardUserDefaults] setValue:_targetVersion forKey:@"version"];
        [self reset];
        _proxiedCompletionHandler(nil);
        return;
    }
    
    // Check if tasks are all done
    [_downloadTasks enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if([obj[@"complete"] isEqualToNumber:[NSNumber numberWithBool:NO]]) {
            notFinished = YES;
            *stop = YES;
        }
    }];
    
    // If not all downloads are finished, don't do anything
    if(notFinished) {
        return;
    }
    
    // Verify checksums of downloaded files
    [_downloadTasks enumerateKeysAndObjectsUsingBlock:^(id key, NSDictionary *obj, BOOL *stop) {
        
        // We don't bother about checksums when it comes to asset files -- too slow, not critical
        // The local dev server will also give us nil checksums because it wants to force an update
        if(obj[@"checksum"] == nil || [[NSNull null] isEqual:obj[@"checksum"]]) {
            return;
        }
        
        NSString *hash = [[NSData dataWithContentsOfURL:obj[@"tempLocation"]] MD5];
        
        if(![hash isEqualToString:obj[@"checksum"]]) {
            NSLog(@"Checksum failed!\n  Actual: %@\n  Expected: %@\n  Task: %@\n  Location: %@",
                  hash,
                  obj[@"checksum"],
                  ((NSURLSessionTask *) obj[@"task"]).taskDescription,
                  obj[@"tempLocation"]);
            isCorrupted = YES;
            *stop = YES;
        }
    }];
    
    // If this flag was set, we should bail out
    if(isCorrupted) {
        [self reset];
        _proxiedCompletionHandler([NSError errorWithDomain:@"GETABLE" code:500 userInfo:@{
                                                                                          NSLocalizedDescriptionKey: @"Download corrupted"
                                                                                          }]);
        return;
    }
    
    __block NSError *lastError = nil;
    
    // Iterate through all completed tasks and copy the temp file to the final destination
    [_downloadTasks enumerateKeysAndObjectsUsingBlock:^(id key, NSDictionary *obj, BOOL *stop) {
        NSError *error = nil;
        NSString *destString = [obj[@"destination"] absoluteString];
        
        // Remove an existing file
        [fm removeItemAtURL:obj[@"destination"] error:nil];
        
        // Recursively create the parent directory
        [fm createDirectoryAtURL:[obj[@"destination"] URLByDeletingLastPathComponent]
     withIntermediateDirectories:YES
                      attributes:nil
                           error:nil];
        
        // If the downloaded file is a js or css file, we need to fix some absolute paths
        if([destString hasSuffix:@".js"] || [destString hasSuffix:@".css"]
           || [destString containsString:@"/js/"] || [destString containsString:@"/css/"]) {
            NSString *fileContents = [NSString stringWithContentsOfFile:obj[@"tempLocation"] encoding:NSUTF8StringEncoding error:&error];
            
            if(error) {
                NSLog(@"Failed to read file %@, ignoring", obj[@"tempLocation"]);
                [fm moveItemAtURL:obj[@"tempLocation"] toURL:obj[@"destination"] error:&error];
                error = nil;
            }
            else {
                // This doodad converts absolute paths like /static into relative ones to the OTA updated bundle
                NSString * (^fixPrefix)(NSString *, NSString *) = ^NSString *(NSString * input, NSString *prefix) {
                    NSString *needle = [[@"/" stringByAppendingString:prefix] stringByAppendingString:@"/"];
                    NSString *replacement = [prefix stringByAppendingString:@"/"];
                    
                    input = [input stringByReplacingOccurrencesOfString:[@"'" stringByAppendingString:needle] withString:[@"'" stringByAppendingString:replacement]];
                    input = [input stringByReplacingOccurrencesOfString:[@"\"" stringByAppendingString:needle] withString:[@"\"" stringByAppendingString:replacement]];
                    input = [input stringByReplacingOccurrencesOfString:[@"(" stringByAppendingString:needle] withString:[@"(" stringByAppendingString:replacement]];
                    return input;
                };
                
                NSArray *prefixes = [AbsolutePathsToReplace componentsSeparatedByString:@","];
                
                for(int i=0; i<prefixes.count; i++) {
                    NSString *prefix = prefixes[i];
                    
                    // Only fix nonempty prefixes
                    if(prefix.length) {
                        fileContents = fixPrefix(fileContents, prefix);
                    }
                }
                
                [fm createFileAtPath:((NSURL *) obj[@"destination"]).path contents:[fileContents dataUsingEncoding:NSUTF8StringEncoding] attributes:nil];
            }
        }
        else {
            // Move the downloaded file
            [fm moveItemAtURL:obj[@"tempLocation"] toURL:obj[@"destination"] error:&error];
        }
        
        [fm addSkipBackupAttributeToItemAtURL:obj[@"destination"]];
        
        if(error) {
            *stop = YES;
            lastError = [NSError errorWithDomain:@"GETABLE" code:500 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Error swapping file %@: %@", obj[@"destination"], error.localizedDescription]}];
            return;
        }
    }];
    
    // Update the current version of the app so we don't waste time re-downloading stuff
    if(lastError == nil) {
        [[NSUserDefaults standardUserDefaults] setValue:_targetVersion forKey:@"version"];
    }
    
    // The update task is complete!
    [self reset];
    
    // Clear the temp directory
    NSString *tempdir = [_tempDirURL path];
    NSError *error = nil;
    for(NSString *file in [fm contentsOfDirectoryAtPath:tempdir error:&error]) {
        BOOL success = [fm removeItemAtPath:[_tempDirURL URLByAppendingPathComponent:file].path error:&error];
        
        if (!success || error) {
            NSLog(@"Failed to delete temp file %@: %@", file, error);
        }
    }
    
    // Report any error in the last block
    return _proxiedCompletionHandler(lastError);
}

- (void)reset
{
    _downloadTasks = [[NSMutableDictionary alloc] initWithCapacity:10];
    _targetVersion = nil;
    _session = nil;
}

-(void)cancel
{
    if(_session) {
        [_session invalidateAndCancel];
    }
}

#pragma mark - NSUrlSessionDelegate

-(void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error
{
    NSError *_error;
    
    if(error == nil) {
        _error = [NSError errorWithDomain:@"GETABLE" code:505 userInfo:@{NSLocalizedDescriptionKey: @"The downloads took too long"}];
    }
    else {
        _error = error;
    }
    
    NSLog(@"Error updating app: %@", _error);
    [self reset];
    
    _proxiedCompletionHandler(_error);
}

-(void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    if(error) {
        [session invalidateAndCancel];
        NSLog(@"Error downloading %@: %@", task.taskDescription, error.localizedDescription);
    }
}

#pragma mark - NSUrlSessionDownloadDelegate

-(void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location
{
    // This function IS NOT THREAD SAFE!!!
    // You will get sporadic app crashes if you do not understand why and remove this:
    // Find the task metadata we saved earlier
    NSMutableDictionary *task = _downloadTasks[[NSNumber numberWithInteger:downloadTask.taskIdentifier]];
    
    // Need to immediately copy the temporary file into the bundle or we will sporadically lose it, weird!
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *tempLocation = task[@"tempLocation"];
    NSURL *tempDestinationFolder = [tempLocation URLByDeletingLastPathComponent];
    NSError *error = nil;
    
    // Make sure that the destination folder exists
    if(![fm fileExistsAtPath:[tempDestinationFolder absoluteString]]) {
        [fm createDirectoryAtURL:tempDestinationFolder withIntermediateDirectories:YES attributes:0 error:&error];
        
        if(error != nil) {
            [NSException raise:@"Could not create temp folder" format:@"The temp folder %@ could not be created: %@", [tempDestinationFolder absoluteString], error.localizedDescription];
        }
    }
    
    // Copy the temp item into the slightly less temp folder
    [fm copyItemAtURL:location toURL:tempLocation error:&error];
    
    if(error != nil) {
        // File already exists, so remove the existing file
        if(error.code == 516) {
            error = nil;
            [fm removeItemAtURL:tempLocation error:&error];
            
            if(error != nil) {
                [NSException raise:@"Could not remove temp item" format:@"The temp item %@ could not be removed: %@", [tempLocation absoluteString], error.localizedDescription];
            }
            
            // Try again
            [fm copyItemAtURL:location toURL:tempLocation error:&error];
        }
        
        if(error != nil) {
            [NSException raise:@"Could not copy downloaded file" format:@"The file %@ could not be copied to %@: %@", [location absoluteString], [tempLocation absoluteString], error];
        }
    }
    
    // Mark this task as complete
    task[@"complete"] = [NSNumber numberWithBool:YES];
    
    [self applyDownloadedFiles];
}

-(void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didResumeAtOffset:(int64_t)fileOffset expectedTotalBytes:(int64_t)expectedTotalBytes
{
    // Don't care
}

-(void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    // Don't care
}

#pragma mark NSFileManagerDelegate

-(BOOL)fileManager:(NSFileManager *)fileManager shouldCopyItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath
{
    // Don't copy cache primer stuff to the documents directory! That shit gets backed up and is the wrong place anyway!
    return ![srcPath hasSuffix:@".persist"];
}

@end

//
//  PersistentURLCache.m
//  Getable
//
//  Created by Ben on 7/18/14.
//
//

#import "PersistentURLCache.h"
#import "NSString+MD5.h"

@interface PersistentURLCache() {
    NSURL *_cachePrimerURL;
    NSURL *_OTAUpdatedCacheURL;
    NSBundle *_mainBundle;
    NSFileManager *_fm;
    NSMutableDictionary *_cacheStatusCache;
}

@end

@implementation PersistentURLCache

-(id)initWithMemoryCapacity:(NSUInteger)memoryCapacity diskCapacity:(NSUInteger)diskCapacity diskPath:(NSString *)diskPath {
    return [self initWithMemoryCapacity:memoryCapacity
                    diskCapacity:diskCapacity
                        diskPath:diskPath
                         cachePrimerURL:nil
                     OTAUpdatedCacheURL:nil];
}

-(id)initWithMemoryCapacity:(NSUInteger)memoryCapacity
               diskCapacity:(NSUInteger)diskCapacity
                   diskPath:(NSString *)diskPath
             cachePrimerURL:(NSURL *)cachePrimerURL
         OTAUpdatedCacheURL:(NSURL *)OTAUpdatedCacheURL
{
    self = [super initWithMemoryCapacity:memoryCapacity diskCapacity:diskCapacity diskPath:diskPath];
    
    if (self) {
        if(cachePrimerURL != nil) {
            _cachePrimerURL = cachePrimerURL;
        }
        else {
            [NSException raise:@"No cachePrimerURL" format:@"PersisentURLCache must be initialized with a cachePrimerURL"];
        }
        
        if(OTAUpdatedCacheURL != nil) {
            _OTAUpdatedCacheURL = OTAUpdatedCacheURL;
        }
        else {
            [NSException raise:@"No OTAUpdatedCacheURL" format:@"PersisentURLCache must be initialized with a OTAUpdatedCacheURL"];
        }
        
        _cacheStatusCache = [[NSMutableDictionary alloc] initWithCapacity:100];
        _fm = [NSFileManager defaultManager];
        _mainBundle = [NSBundle mainBundle];
	}
    
	return self;
}

-(NSCachedURLResponse *)cachedResponseForRequest:(NSURLRequest *)request
{
    // Never cache file URLs
    if([request.URL.scheme isEqualToString:@"file"]) {
        return nil;
    }
    
    NSCachedURLResponse *resp = [super cachedResponseForRequest:request];
    
    if(resp != nil) {
        return resp;
    }
    
    NSString *cacheKey = [self cacheKeyForURL:request.URL];
    
    NSNumber *cacheResult = _cacheStatusCache[cacheKey];
    
    if(cacheResult != nil && [cacheResult isEqualToNumber:[NSNumber numberWithBool:NO]]) {
        return nil;
    }
    
    NSURL *fileURL = [self persistedDataURLForURL:request.URL];
    NSError *error = nil;
    NSData *content = [NSData dataWithContentsOfURL:fileURL options:0 error:&error];
    
    if(error) {
        // NSLog(@"Not in cache: %@", cacheKey);
        [_cacheStatusCache setValue:[NSNumber numberWithBool:NO] forKey:cacheKey];
        return nil;
    }
    else {
        NSURLResponse* response = [[NSURLResponse alloc] initWithURL:request.URL
                                                            MIMEType:@"cache"
                                               expectedContentLength:[content length]
                                                    textEncodingName:nil];
        
        // NSLog(@"Loaded from cache: %@", cacheKey);
        
        return [[NSCachedURLResponse alloc] initWithResponse:response data:content];
    }
}

-(NSString *)cacheKeyForURL:(NSURL *)url
{
    return [[url.host stringByAppendingString:url.path] MD5];
}

-(NSURL *)persistedDataURLForURL:(NSURL *)url
{
    // Try the cache primer that ships with the bundle first
    NSString *cacheKey = [self cacheKeyForURL:url];
    NSString *tempPath = [_mainBundle pathForResource:cacheKey ofType:@".persist" inDirectory:@"cache"];
    
    if([_fm fileExistsAtPath:tempPath]) {
        return [NSURL fileURLWithPath:tempPath];
    }
    // Fall back to the OTA updated cache if the cache primer doesn't contain the file we want
    else {
        return [self OTAUpdatedPersistedDataURLForURL:url];
    }
}

-(NSURL *)OTAUpdatedPersistedDataURLForURL:(NSURL *)url
{
    return [_OTAUpdatedCacheURL URLByAppendingPathComponent:[[self cacheKeyForURL:url] stringByAppendingString:@".persist"]];
}

-(NSURL *)OTAUpdatedCacheURL
{
    return _OTAUpdatedCacheURL;
}

@end

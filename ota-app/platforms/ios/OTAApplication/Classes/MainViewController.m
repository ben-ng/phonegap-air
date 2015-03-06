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
//  MainViewController.h
//  HelloWorld
//
//  Created by ___FULLUSERNAME___ on ___DATE___.
//  Copyright ___ORGANIZATIONNAME___ ___YEAR___. All rights reserved.
//

#import "MainViewController.h"

@interface MainViewController() {
}

- (void) enterUpdateModeWithLabelText: (NSString *) labelText;
- (void) exitUpdateMode;
- (void) reloadWebView;
- (void) findLaunchImage;

@end

@implementation MainViewController {
    // This bool is true when an update was downloaded in the background, but hasn't been applied yet
    BOOL _pendingBackgroundUpdate;
    
    // See "Nomenclature" in AppDelegate.m
    NSURL *_OTAUpdatedWWWURL;
    
    /**
     * The id of the app can change during updates from Xcode. When this happens, the code might not be reloaded, so
     * the webview still has a baseURL from the old app bundle, leading to missing assets and generally Bad Things.
     * We keep a reference to the last baseURL we set the webview to in this variable so that we can detect such changes
     * and reload the webview with the new baseURL. To be honest, this is super weird to me too.
     */
    NSURL *_webViewCurrentBaseURL;
    
    /**
     * _pendingFragment is where the deep linking URL is kept until it is ready to be loaded
     * When the webview is ready, the pending fragment is copied to onLoadFragment, where it is
     * applied when the webview finishes loading. These two variables are thus intimately linked.
     */
    NSString *_pendingFragment;
    NSString *_onLoadFragment;
    
    // Just a reference to the same OTA Updating library the app delegate uses
    AppUpdate *_appUpdate;
    
    // Keeps a reference to the launch image of the application so that the webview can easily use it
    // as its background image to appear super fast
    NSString *_launchImagePath;
    
    // Comes from the AppDelegate, is used to verify that we are handling a URL we can handle
    NSString *_URLScheme;
    
    // This boolean is true when the update library is working in a background thread
    BOOL _isUpdating;
}

- (id)initWithNibName:(NSString*)nibNameOrNil bundle:(NSBundle*)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        _isUpdating = NO;
        _pendingBackgroundUpdate = NO;
    }
    return self;
}

- (id)init
{
    self = [super init];
    if (self) {
        _isUpdating = NO;
        _pendingBackgroundUpdate = NO;
    }
    return self;
}

- (id)initWithOTAUpdatedWWWURL:(NSURL *)OTAUpdatedWWWURL
                     appUpdate:(AppUpdate *)appUpdate
                     URLScheme:(NSString *)URLScheme
{
    self = [super init];
    if(self) {
        _OTAUpdatedWWWURL = OTAUpdatedWWWURL;
        _appUpdate = appUpdate;
        _URLScheme = URLScheme;
        
        // Create a web view for the express purpose of getting the user agent.
        UIWebView* tempWebView = [[UIWebView alloc] initWithFrame:CGRectZero];
        NSString* userAgent = [tempWebView stringByEvaluatingJavaScriptFromString:@"navigator.userAgent"];
        
        // Get the native app version and append it to user agent.
        NSString *nativeAppVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
        userAgent = [NSString stringWithFormat:@"PhoneGap (iOS %@) %@", nativeAppVersion, userAgent];
        
        // This comes from cordova
        _userAgent = userAgent;
        
        // Default the staging URL
        if([[NSUserDefaults standardUserDefaults] valueForKey:@"customURL"] == nil) {
            [[NSUserDefaults standardUserDefaults] setValue:CustomURL forKey:@"customURL"];
        }
    }
    return self;
}

- (void)didReceiveMemoryWarning
{
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];

    // Release any cached data, images, etc that aren't in use.
}

#pragma mark External API

- (void)setPendingBackgroundUpdate:(BOOL)yes
{
    _pendingBackgroundUpdate = yes;
}

#pragma mark View lifecycle

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self findLaunchImage];
    [self willEnterForeground];
}

/**
 * This is called when the view is first created, or by the AppDelegate when the app is about to enter an active state,
 * for example a launch from the home screen (which surprisingly does not call "viewWillAppear"). Go figure.
 */
-(void)willEnterForeground
{
    NSString *oldVersion = [[NSUserDefaults standardUserDefaults] valueForKey:@"version"];
    NSString *lastBundleVersion = [[NSUserDefaults standardUserDefaults] stringForKey:@"bundleVersion"];
    NSString *currentBundleVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    BOOL isAfterUpdate = NO;
    
    // This forces a new OTA update and bundle copy after an app store update
    // Which allows us to update index.html in the OTA directory
    if(lastBundleVersion) {
        if(![lastBundleVersion isEqualToString:currentBundleVersion]) {
            isAfterUpdate = YES;
            [[NSUserDefaults standardUserDefaults] setValue:currentBundleVersion forKey:@"bundleVersion"];
        }
    }
    else {
        [[NSUserDefaults standardUserDefaults] setValue:currentBundleVersion forKey:@"bundleVersion"];
    }
    
    // If the version is empty, attempt an blocking immediate update
    if(oldVersion == nil || isAfterUpdate) {
        [self enterUpdateModeWithLabelText:@"Please wait.."];
        
        [_appUpdate restoreFromBundleResourcesWithCompletionHandler:^(NSError *error) {
            if(error != nil) {
                [NSException raise:@"Failed to launch" format:@"App failed: %@", error.localizedDescription];
            }
            
            [_appUpdate downloadUpdateWithCompletionHandler:^(NSDictionary *versionInfo, NSError *error) {
                if(error != nil) {
                    NSLog(@"Blocking update failed: %@", error.localizedDescription);
                }
                else {
                    NSLog(@"Blocking update completed");
                }
                [self exitUpdateMode];
            }];
        }];
    }
    // Otherwise do a non-blocking, background update
    else {
        // Apply background update if pending by reloading the webview
        if(_pendingBackgroundUpdate) {
            _pendingBackgroundUpdate = NO;
            [self reloadWebView];
        }
        // Otherwise, only reload if the bundle id changed (can happen if app is updated via xCode)
        // Otherwise the basepath will be wrong!
        else {
            if(![_webViewCurrentBaseURL.absoluteString isEqualToString:_OTAUpdatedWWWURL.absoluteString]) {
                [self findLaunchImage];
                [self reloadWebView];
            }
        }
        
        [_appUpdate downloadUpdateWithCompletionHandler:^(NSDictionary *versionInfo, NSError *error) {
            if(error == nil) {
                if(![versionInfo[@"version"] isEqualToString:oldVersion] ||
                   ![[[NSUserDefaults standardUserDefaults] valueForKey:@"rootURL"] isEqualToString:ProductionURL]) {
                    _pendingBackgroundUpdate = YES;
                    NSLog(@"Now on version %@", versionInfo[@"version"]);
                }
                else {
                    NSLog(@"No need to reload, already on version %@", versionInfo[@"version"]);
                }
            }
            else {
                NSLog(@"Failed to update: %@", error.localizedDescription);
            }
        }];
    }
    
    [self becomeFirstResponder];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
    return [super shouldAutorotateToInterfaceOrientation:interfaceOrientation];
}

/* Comment out the block below to over-ride */

/*
- (UIWebView*) newCordovaViewWithFrame:(CGRect)bounds
{
    return[super newCordovaViewWithFrame:bounds];
}
*/

#pragma mark External API

- (void)loadURLWhenPossible:(NSURL *)url
{
    NSString *fragment = nil;
    // Does this request follow our scheme?
    if(_URLScheme != nil && [[url scheme] isEqualToString:_URLScheme]) {
        fragment = [[url.absoluteString substringFromIndex:_URLScheme.length + @"://".length] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    }
    
    _pendingFragment = fragment;
    
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if(!_isUpdating) {
            [self reloadWebView];
        }
    });
}

-(void)reloadWebView
{
    NSString *indexHTMLData = [NSString stringWithContentsOfURL:[_OTAUpdatedWWWURL URLByAppendingPathComponent:self.startPage] encoding:NSUTF8StringEncoding error:nil];
    CGSize viewSize = [UIScreen mainScreen].bounds.size;
    
    // Replace timestamp so we force new js to load
    indexHTMLData = [indexHTMLData stringByReplacingOccurrencesOfString:@"{{ts}}" withString:[NSNumber numberWithDouble:[NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970].stringValue];
    if(_launchImagePath) {
        indexHTMLData = [indexHTMLData stringByReplacingOccurrencesOfString:@"{{launchImagePath}}" withString:_launchImagePath];
    }
    indexHTMLData = [indexHTMLData stringByReplacingOccurrencesOfString:@"{{launchImageSizeX}}" withString:[NSString stringWithFormat:@"%d", (int) viewSize.width]];
    indexHTMLData = [indexHTMLData stringByReplacingOccurrencesOfString:@"{{launchImageSizeY}}" withString:[NSString stringWithFormat:@"%d", (int) viewSize.height]];
    
    // If you don't do this, baseURL won't work ):
    NSString *tempString = [_OTAUpdatedWWWURL.path stringByReplacingOccurrencesOfString:@"/" withString:@"//"];
    tempString = [tempString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSURL *bastardizedURL = [NSURL URLWithString:[NSString stringWithFormat:@"file:/%@//", tempString]];
    
    if(_pendingFragment) {
        _onLoadFragment = _pendingFragment;
        _pendingFragment = nil;
    }
    
    [self.webView loadHTMLString:indexHTMLData baseURL:bastardizedURL];
    _webViewCurrentBaseURL = _OTAUpdatedWWWURL;
    
    [self.view sendSubviewToBack:self.launchImage];
}

#pragma mark Shake Gesture Handlers

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

-(void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event
{
    if(!_isUpdating && motion == UIEventSubtypeMotionShake && !self.webView.isLoading) {
        NSString *shouldAllow = [self.webView stringByEvaluatingJavaScriptFromString:@"window.shouldAllowOTADevTools()"];
        
        if([shouldAllow rangeOfString:@"true"].location != NSNotFound) {
            
            NSString *currentBranch = [[NSUserDefaults standardUserDefaults] valueForKey:@"rootURL"];
            
            if([currentBranch isEqualToString:ProductionURL]) {
                currentBranch = @"Production";
            }
            else if([currentBranch isEqualToString:StagingURL]) {
                currentBranch = @"Staging";
            }
            else {
                currentBranch = @"Custom";
            }
            
            NSString *alertTitle;
            NSString *version = [[NSUserDefaults standardUserDefaults] valueForKey:@"version"];
            
            if(version) {
                alertTitle = version;
            }
            else {
                alertTitle = @"(Last Update Failed)";
            }
            
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"Now On %@", currentBranch]
                                                                message:alertTitle
                                                               delegate:self
                                                      cancelButtonTitle:@"Cancel"
                                                      otherButtonTitles:@"Use Custom URL", @"Staging", @"Production", nil];
            
            alertView.alertViewStyle = UIAlertViewStylePlainTextInput;
            
            [[alertView textFieldAtIndex:0] setText: [[NSUserDefaults standardUserDefaults] valueForKey:@"customURL"]];
            
            [alertView show];
        }
    }
}

#pragma mark Update Logic

- (void)enterUpdateModeWithLabelText:(NSString *)labelText
{
    
    [self.webView setHidden:YES];
    self.spinnerLabel.text = labelText;
    self.spinnerLabel.hidden = NO;
    [self.spinnerLabel setNeedsDisplay];
    [self.spinner startAnimating];
    [self.view bringSubviewToFront:self.spinner];
    [self.view bringSubviewToFront:self.spinnerLabel];
    
    _isUpdating = YES;
}

- (void)exitUpdateMode
{
    dispatch_async(dispatch_get_main_queue(), ^{
        
        self.spinnerLabel.hidden = YES;
        [self.spinner stopAnimating];
        [self reloadWebView];
        
        // Avoid the weird flash by delaying the reappearance of the webview
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self.webView setHidden:NO];
            _isUpdating = NO;
        });
    });
}

#pragma mark UIAlertViewDelegate

-(void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    NSString *newBranch;
    
    switch (buttonIndex) {
        case 3:
            [[NSUserDefaults standardUserDefaults] setValue:ProductionURL forKey:@"rootURL"];
            newBranch = @"Production";
            break;
        case 2:
            [[NSUserDefaults standardUserDefaults] setValue:StagingURL forKey:@"rootURL"];
            newBranch = @"Staging";
            break;
        case 1:
            [[NSUserDefaults standardUserDefaults] setValue:[alertView textFieldAtIndex:0].text forKey:@"customURL"];
            [[NSUserDefaults standardUserDefaults] setValue:[alertView textFieldAtIndex:0].text forKey:@"rootURL"];
            newBranch = @"Custom";
            break;
        default:
            return;
    }
    
    // This forces a re-download of the app
    [[NSUserDefaults standardUserDefaults] setValue:nil forKey:@"version"];
    
    [self enterUpdateModeWithLabelText:[NSString stringWithFormat:@"Pulling from %@", newBranch]];
    
    [_appUpdate downloadUpdateWithCompletionHandler:^(NSDictionary *versionInfo, NSError *error) {
        [self exitUpdateMode];
        
        // If not on main queue, this will crash on movement of the device
        dispatch_async(dispatch_get_main_queue(), ^{
            if(error == nil) {
                NSString *alertTitle;
                
                alertTitle = [NSString stringWithFormat:@"Now On %@", newBranch];
                
                
                [[[UIAlertView alloc] initWithTitle:alertTitle
                                            message:[NSString stringWithFormat:@"%@\n%@", versionInfo[@"version"], versionInfo[@"message"]]
                                           delegate:nil
                                  cancelButtonTitle:@"Finish"
                                  otherButtonTitles:nil] show];
            }
            else {
                NSString *currentBranch = [[NSUserDefaults standardUserDefaults] valueForKey:@"rootURL"];
                
                // If a custom URL pull fails, reset to the StagingURL, which is a known good configuration
                if(![currentBranch isEqualToString:ProductionURL]) {
                    [[[UIAlertView alloc] initWithTitle:@"Error"
                                                message:[NSString stringWithFormat:@"It looks like your custom URL was unreachable.\nIs your dev server running?\nError: %@", error.localizedDescription]
                                               delegate:nil
                                      cancelButtonTitle:@"Done"
                                      otherButtonTitles:nil] show];
                }
                else {
                    [[[UIAlertView alloc] initWithTitle:@"Error"
                                                message:error.localizedDescription
                                               delegate:nil
                                      cancelButtonTitle:@"Done"
                                      otherButtonTitles:nil] show];
                }
            }
        });
    }];
}

#pragma mark UIWebDelegate implementation

- (void)webViewDidFinishLoad:(UIWebView*)theWebView
{
    // Stop annoying bouncing and scrollbars
    theWebView.backgroundColor = [UIColor whiteColor];
    theWebView.scrollView.bounces = false;
    theWebView.scrollView.showsHorizontalScrollIndicator = NO;
    theWebView.scrollView.showsVerticalScrollIndicator = NO;
    
    if(_onLoadFragment) {
        NSString *_tempFragment = _onLoadFragment;
        _onLoadFragment = nil;
        
        NSString *replacedString = [_tempFragment stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        
        if(replacedString != nil) {
            replacedString = [replacedString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            NSString *locationSwitcher = [NSString stringWithFormat:@"(function deepLink () {\
                                          function tryLinking () {\
                                          if(typeof window.handleDeepLinkedFragment == 'function') {window.handleDeepLinkedFragment('%@')}\
                                          else {setTimeout(tryLinking, 300)}\
                                          }\
                                          tryLinking()\
                                          })()", replacedString];
            NSLog(@"Deep linking to %@", replacedString);
            [theWebView stringByEvaluatingJavaScriptFromString:locationSwitcher];
        }
        else {
            NSLog(@"Invalid deep link fragment: %@", _tempFragment);
        }
    }
    
    if(_pendingFragment) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self reloadWebView];
        });
    }

    return [super webViewDidFinishLoad:theWebView];
}

/* Comment out the block below to over-ride

- (void) webViewDidStartLoad:(UIWebView*)theWebView
{
    return [super webViewDidStartLoad:theWebView];
 }
 */

- (void) webView:(UIWebView*)theWebView didFailLoadWithError:(NSError*)error
{
    // Ignore error from webview load cancellation and set the pending URL again so the next load uses it
    if(error.code == -999) {
        if(_onLoadFragment) {
            _pendingFragment = _onLoadFragment;
            _onLoadFragment = nil;
        }
    }
    /**
     * If the webview 404'ed, that usually means that someone left an absolute
     * link lying around or is using pushState. In either case, just reload the webview,
     * because its usually the result of a log-out action, in which case we guessed
     * the expected behavior. If it isn't, we restart instead of having the app go
     * into an undefined state, which should clue the dev into fixing the root problem.
     */
    else if(error.code == -1100 || error.code == 102) {
        [self reloadWebView];
    }
    else {
        [super webView:theWebView didFailLoadWithError:error];
    }
}

- (BOOL) webView:(UIWebView*)theWebView shouldStartLoadWithRequest:(NSURLRequest*)request navigationType:(UIWebViewNavigationType)navigationType
{
    BOOL shouldLoad = [super webView:theWebView shouldStartLoadWithRequest:request navigationType:navigationType];
    
    if(!shouldLoad) {
        return NO;
    }
    
    if(_pendingFragment != nil) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self reloadWebView];
        });
        return NO;
    }
    
    // Did the user request index.html? In which case, redirect them to use the OTA updated one instead of the bundled one
    if([request.URL.absoluteString rangeOfString:@"index.html"].location != NSNotFound) {
        [self performSelector:@selector(reloadWebView) withObject:nil afterDelay:0.1];
        return NO;
    }
    else {
        return YES;
    }
}

#pragma mark Helper Functions
/**
 * This looks through the launch images supplied with the app and picks out
 * the one that matches the device's resolution
 */
- (void) findLaunchImage
{
    NSArray *allPngImageNames = [[NSBundle mainBundle] pathsForResourcesOfType:@"png"
                                                                   inDirectory:nil];
    
    CGSize trueScreenSize = [UIScreen mainScreen].bounds.size;
    trueScreenSize.height *= [UIScreen mainScreen].scale;
    trueScreenSize.width *= [UIScreen mainScreen].scale;
    
    for (NSString *imgName in allPngImageNames){
        if ([imgName rangeOfString:@"LaunchImage"].location != NSNotFound){
            UIImage *img = [UIImage imageNamed:imgName];
            
            CGSize trueImageSize = img.size;
            trueImageSize.height *= img.scale;
            trueImageSize.width *= img.scale;
            
            // Has image same scale and dimensions as our current device's screen?
            if (CGSizeEqualToSize(trueImageSize, trueScreenSize)) {
                _launchImagePath = [@"file://" stringByAppendingString:imgName];
                [self.launchImage setImage:img];
                break;
            }
        }
    }
}

@end

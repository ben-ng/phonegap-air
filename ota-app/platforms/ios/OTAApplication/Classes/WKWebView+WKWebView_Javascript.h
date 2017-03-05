//
//  WKWebView+WKWebView_Javascript.h
//  OTAApplication
//
//  Created by Michael Dautermann on 2/2/17.
//
//

#import <WebKit/WebKit.h>

// http://stackoverflow.com/questions/26778955/wkwebview-evaluate-javascript-return-value

@interface WKWebView(SynchronousEvaluateJavaScript)
- (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)script;
@end

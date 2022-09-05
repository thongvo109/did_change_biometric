#import "DidChangeAuthlocalPlugin.h"
#if __has_include(<did_change_authlocal/did_change_authlocal-Swift.h>)
#import <did_change_authlocal/did_change_authlocal-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "did_change_authlocal-Swift.h"
#endif

@implementation DidChangeAuthlocalPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftDidChangeAuthlocalPlugin registerWithRegistrar:registrar];
}
@end

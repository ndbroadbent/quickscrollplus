#import <Preferences/Preferences.h>
#import <GriP/GPGetSmallAppIcon.h>
#import <UIKit/UIKit2.h>
#import <notify.h>
#import <SpringBoardServices/SpringBoardServices.h>

static NSComparisonResult comparePSSpecs(PSSpecifier* p1, PSSpecifier* p2, void* context) { return [p1.name localizedCompare:p2.name]; }

@interface QuickScrollDisabledAppsController : PSListController {
	NSMutableSet* gameModeApps;
	UIProgressHUD* enumeratingHUD;
}
-(id)initForContentSize:(CGSize)size;
-(void)dealloc;
-(void)suspend;
-(void)saveState;
-(NSArray*)specifiers;
-(void)populateSystemApps;
-(CFBooleanRef)getApp:(PSSpecifier*)spec;
-(void)set:(CFBooleanRef)enable app:(PSSpecifier*)spec;
-(void)showHUD;
-(void)hideHUD;
-(void)appendAppWithPath:(NSString*)path toArray:(NSMutableArray*)arr;
-(void)appendAppWithPath:(NSString*)path identifier:(NSString*)identifier toArray:(NSMutableArray*)arr;
@end
@implementation QuickScrollDisabledAppsController
-(id)initForContentSize:(CGSize)size {
	if ((self = [super initForContentSize:size])) {
		CFArrayRef gameModeAppsArray = CFPreferencesCopyAppValue(CFSTR("disabled_apps"), CFSTR("hk.ndb.quickscrollplus"));
		gameModeApps = [NSMutableSet alloc];
		gameModeApps = gameModeAppsArray ? [gameModeApps initWithArray:(NSArray*)gameModeAppsArray] : [gameModeApps init];
		if (gameModeAppsArray != nil)
			CFRelease(gameModeAppsArray);
		enumeratingHUD = [[UIProgressHUD alloc] init];
		[enumeratingHUD setText:[[NSBundle mainBundle] localizedStringForKey:@"LOADING_APPLICATIONS" value:@"Loading Applications\u2026" table:nil]];
	}
	return self;
}
-(void)dealloc {
	[self saveState];
	[gameModeApps release];
	[enumeratingHUD release];
	[super dealloc];
}
-(void)suspend {
	[self saveState];
	[super suspend];
}
-(void)saveState {
	CFPreferencesSetAppValue(CFSTR("disabled_apps"), [gameModeApps allObjects], CFSTR("hk.ndb.quickscrollplus"));
	CFPreferencesAppSynchronize(CFSTR("hk.ndb.quickscrollplus"));
	notify_post("hk.ndb.quickscrollplus.reload");
}	
-(void)appendAppWithPath:(NSString*)path identifier:(NSString*)identifier toArray:(NSMutableArray*)arr {
	UIImage* image = GPGetSmallAppIcon(identifier);
	if (image == nil) {
		NSString* iconPath = SBSCopyIconImagePathForDisplayIdentifier(identifier);
		image = [[UIImage imageWithContentsOfFile:iconPath] _smallApplicationIconImagePrecomposed:YES];
		[iconPath release];
	}
	
	NSString* localizedName = SBSCopyLocalizedApplicationNameForDisplayIdentifier(identifier);
	
	if ([identifier isEqualToString: @"com.apple.springboard"])
		localizedName = @"SpringBoard";
	
	if (localizedName == nil && image == nil)
		return;
	
	PSSpecifier* spec = [PSSpecifier preferenceSpecifierNamed:localizedName
													   target:self
														  set:@selector(set:app:)
														  get:@selector(getApp:)
													   detail:Nil
														 cell:PSSwitchCell
														 edit:Nil];
	[localizedName release];
	[spec setProperty:image forKey:@"iconImage"];
	[spec setProperty:identifier forKey:@"id"];
	[arr addObject:spec];
}
-(void)appendAppWithPath:(NSString*)path toArray:(NSMutableArray*)arr {
	NSBundle* appBundle = [[NSBundle alloc] initWithPath:path];
	NSString* identifier = [appBundle bundleIdentifier];
	
	if (identifier != nil) {
		NSMutableSet* allRoleIDs = [[NSMutableSet alloc] init];
		
		for (NSDictionary* role in [appBundle objectForInfoDictionaryKey:@"UIRoleInfo"]) {
			for (NSDictionary* role2 in [role objectForKey:@"Roles"]) {
				NSString* roleName = [role2 objectForKey:@"Role"];
				[allRoleIDs addObject:[NSString stringWithFormat:@"%@-%@", identifier, roleName]];
			}
		}
		
		if ([allRoleIDs count] != 0) {
			for (NSString* roleID in allRoleIDs)
				[self appendAppWithPath:path identifier:roleID toArray:arr];
		} else
			[self appendAppWithPath:path identifier:identifier toArray:arr];
		
		[allRoleIDs release];
	}
	
	[appBundle release];
}
-(void)populateSystemApps {
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	NSFileManager* fman = [NSFileManager defaultManager];
	
	NSMutableArray* userApps = [[NSMutableArray alloc] init];
	NSMutableArray* systemApps = [[NSMutableArray alloc] init];
	NSMutableArray* springBoardApp = [[NSMutableArray alloc] init];
	
	// 1. Enumerate apps in ~/Applications
	for (NSString* subpath in [fman contentsOfDirectoryAtPath:@"/var/mobile/Applications" error:NULL]) {
		NSString* fullSubpath = [@"/var/mobile/Applications" stringByAppendingPathComponent:subpath];
		for (NSString* appPath in [fman contentsOfDirectoryAtPath:fullSubpath error:NULL])
			if ([appPath hasSuffix:@".app"]) {
				[self appendAppWithPath:[fullSubpath stringByAppendingPathComponent:appPath] toArray:userApps];
				break;
			}
	}
	
	// 2. Enumerate apps in /Applications
	for (NSString* appPath in [fman contentsOfDirectoryAtPath:@"/Applications" error:NULL])
		[self appendAppWithPath:[@"/Applications" stringByAppendingPathComponent:appPath] toArray:systemApps];
	
	// sort the array using the localized name.
	[userApps sortUsingFunction:&comparePSSpecs context:NULL];
	[systemApps sortUsingFunction:&comparePSSpecs context:NULL];
	
	[springBoardApp addObject:[PSSpecifier emptyGroupSpecifier]];
	
	[self appendAppWithPath:@"/System/Library/CoreServices/SpringBoard.app" identifier:@"com.apple.springboard" toArray:springBoardApp];
	
	[springBoardApp addObjectsFromArray:userApps];
	[userApps release];
	
	// Commenting out the following line stops the 'disabled apps' controller from crashing.
	//[springBoardApp addObject:[PSSpecifier emptyGroupSpecifier]];
	
	[springBoardApp addObjectsFromArray:systemApps];
	[systemApps release];
	
	NSInvocation* invoc = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(insertContiguousSpecifiers:atIndex:animated:)]];
	BOOL _yes = YES;
	int index = 1;
	[invoc setTarget:self];
	[invoc setSelector:@selector(insertContiguousSpecifiers:atIndex:animated:)];
	[invoc setArgument:&springBoardApp atIndex:2];
	[invoc setArgument:&index atIndex:3];
	[invoc setArgument:&_yes atIndex:4];
	[invoc retainArguments];
	
	[invoc performSelectorOnMainThread:@selector(invoke) withObject:nil waitUntilDone:NO];
	[self performSelectorOnMainThread:@selector(hideHUD) withObject:nil waitUntilDone:NO];
	
	[springBoardApp release];
	
	[pool drain];
}

-(NSArray*)specifiers {
	if (_specifiers == nil) {
		_specifiers = [[NSArray alloc] initWithObjects:
					   [PSSpecifier emptyGroupSpecifier],
					   [PSSpecifier groupSpecifierWithName:[[NSBundle bundleForClass:[self class]]
															localizedStringForKey:@"Switch off to disable." value:nil table:@"QuickScrollPlus"]],
					   nil];
		[self showHUD];
		[self performSelectorInBackground:@selector(populateSystemApps) withObject:nil];
	}
	return _specifiers;
}
-(CFBooleanRef)getApp:(PSSpecifier*)spec { return [gameModeApps containsObject:spec.identifier] ? kCFBooleanFalse : kCFBooleanTrue; }
-(void)set:(CFBooleanRef)enable app:(PSSpecifier*)spec {
	NSString* iden = spec.identifier;
	if (enable == kCFBooleanFalse)
		[gameModeApps addObject:iden];
	else
		[gameModeApps removeObject:iden];
}

-(void)showHUD {
	[enumeratingHUD showInView:self.view];
}
-(void)hideHUD {
	[enumeratingHUD done];
	[enumeratingHUD performSelector:@selector(hide) withObject:nil afterDelay:1];
}
@end


@interface QuickScrollPlusController : PSListController
@end

@implementation QuickScrollPlusController
-(NSArray*)specifiers {
	if (_specifiers == nil)
		_specifiers = [[self loadSpecifiersFromPlistName:@"QuickScrollPlus" target:self] retain];
	return _specifiers;
}
@end

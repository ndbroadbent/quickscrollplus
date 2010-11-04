/*

 QS2.m - Quickly scroll through everything.
 Copyright (C) 2009  KennyTM~
 
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.

*/

#include <pthread.h>
#include <substrate2.h>
#import <UIKit/UIKit2.h>

static BOOL activate_by_single_tap, activate_by_triple_tap, activate_by_two_finger_tap, use_scrollbar, scrollbar_jump_by_pages_not, activate_by_scrolling;
static pthread_mutex_t prefs_lock = PTHREAD_MUTEX_INITIALIZER;
static NSTimeInterval autodismiss_timer;
static int dummy;

enum { QSI_0, QSI_1, QSI_2, QSI_3, QSI_empty, QSI_K1, QSI_K2, QSI_K5, QSI_K6, QSI_sel, QSI_UIPasscodeFieldButton };
static NSString* const imagesFn[] = {@"0", @"1", @"2", @"3", @"empty", @"K1", @"K2", @"K5", @"K6", @"sel", @"UIPasscodeFieldButton"};
static int const imagesStfl[] = {1, 1, 2, 2, 0, 1, 1, 0, 0, 3, 3};
static UIImage* imagesObj[11];
static CGSize handleSize, emptySize;
static CGFloat _close_height, _key_height;

#if TARGET_IPHONE_SIMULATOR
#define RSRC @"/Users/kennytm/XCodeProjects/iKeyEx/svn/trunk/hk.kennytm.quickscroll2/deb/System/Library/PreferenceBundles/QuickScroll.bundle"
#define PREFPATH @"/Users/kennytm/Library/Application Support/iPhone Simulator/User/Library/Preferences/hk.kennytm.quickscroll2.plist"
#else
#define RSRC @"/System/Library/PreferenceBundles/QuickScroll.bundle"
#define PREFPATH @"/var/mobile/Library/Preferences/hk.kennytm.quickscroll2.plist"
#endif

// From AppSupport.framework.
extern CFStringRef CPCopySharedResourcesPreferencesDomainForDomain(CFStringRef domain);

void reload_prefs() {
	pthread_mutex_lock(&prefs_lock);
	
	NSDictionary* dict2 = [NSDictionary dictionaryWithContentsOfFile:PREFPATH];
	if (dict2 == nil) {
		activate_by_single_tap = YES;
		activate_by_triple_tap = NO;
		activate_by_two_finger_tap = NO;
		use_scrollbar = YES;
		autodismiss_timer = 2;
		scrollbar_jump_by_pages_not = NO;
		activate_by_scrolling = NO;
		
		static NSString* const prefs_keys[] = {
			@"activate_by_single_tap", 
			@"activate_by_triple_tap", 
			@"activate_by_two_finger_tap", 
			@"use_scrollbar",
			@"autodismiss_timer",
			@"scrollbar_jump_by_pages_not",
			@"activate_by_scrolling",
		};		
		CFTypeRef default_values[] = {kCFBooleanTrue, kCFBooleanFalse, kCFBooleanFalse, kCFBooleanTrue, [NSNumber numberWithDouble:2], kCFBooleanFalse, kCFBooleanFalse};
		
		dict2 = [NSDictionary dictionaryWithObjects:(id*)default_values forKeys:prefs_keys count:sizeof(prefs_keys)/sizeof(prefs_keys[0])];
		[dict2 writeToFile:PREFPATH atomically:YES];
	} else {
		NSArray* disabled_apps = [dict2 objectForKey:@"disabled_apps"];
		if ([disabled_apps containsObject:[[NSBundle mainBundle] bundleIdentifier]]) {
			activate_by_single_tap = activate_by_triple_tap = activate_by_two_finger_tap = activate_by_scrolling = NO;
		} else {
			activate_by_single_tap = [[dict2 objectForKey:@"activate_by_single_tap"] boolValue];
			activate_by_triple_tap = [[dict2 objectForKey:@"activate_by_triple_tap"] boolValue];
			activate_by_two_finger_tap = [[dict2 objectForKey:@"activate_by_two_finger_tap"] boolValue];
			use_scrollbar = [[dict2 objectForKey:@"use_scrollbar"] boolValue];
			autodismiss_timer = [[dict2 objectForKey:@"autodismiss_timer"] doubleValue] ?: 2;
			scrollbar_jump_by_pages_not = [[dict2 objectForKey:@"scrollbar_jump_by_pages_not"] boolValue];
			activate_by_scrolling = [[dict2 objectForKey:@"activate_by_scrolling"] boolValue];
		}
	}
	
	pthread_mutex_unlock(&prefs_lock);
}

#pragma mark -

static void QSDestroyTimer (NSTimer** timer) {
	[*timer invalidate];
	[*timer release];
	*timer = nil;
}

static void QSCreateOrUpdateTimer (NSTimer** timer, NSTimeInterval interval, id target, SEL action) {
	if (*timer != nil)
		[*timer setFireDate:[NSDate dateWithTimeIntervalSinceNow:interval]];
	else if (interval > 0)
		*timer = [[NSTimer scheduledTimerWithTimeInterval:interval target:target selector:action userInfo:nil repeats:NO] retain];
}

static CGRect CGRectRound(CGRect r) {
	r.origin.x = roundf(r.origin.x);
	r.origin.y = roundf(r.origin.y);
	r.size.width = roundf(r.size.width);
	r.size.height = roundf(r.size.height);
	return r;
}

static void limitPoint(CGPoint* p, CGSize sz, CGSize sz2) {
	CGSize upl = CGSizeMake(MAX(sz.width-sz2.width,0), MAX(sz.height-sz2.height,0));
	
	if (p->x < 0)
		p->x = 0;
	else if (p->x > upl.width)
		p->x = upl.width;
	
	if (p->y < 0)
		p->y = 0;
	else if (p->y > upl.height)
		p->y = upl.height;
}

#pragma mark -

@interface WebPDFView : UIView
-(unsigned)totalPages;
-(unsigned)pageNumberForRect:(CGRect)rect;
@end

static inline ptrdiff_t offsetForClassAndName(Class cls, const char* str) {
	return ivar_getOffset(class_getInstanceVariable(cls, str));
}

static ptrdiff_t pdfOffset = 0;
static inline WebPDFView* WebPDF(UIWebDocumentView* view) {
	if (pdfOffset == 0)
		pdfOffset = offsetForClassAndName([UIWebDocumentView class], "_pdf");
	return *(WebPDFView**)((char*)view + pdfOffset);
}

static ptrdiff_t pageRectsOffset = 0;
static inline CGRect* pageRects(WebPDFView* view) {
	if (pageRectsOffset == 0)
		pageRectsOffset = offsetForClassAndName([view class], "_pageRects");
	return *(CGRect**)((char*)view + pageRectsOffset);
}

#pragma mark -

@interface QSAbstractScroller : UIView {
	// These are all weak references.
	UIScrollView* _scrollView;
	UIWebDocumentView* _webView;
	WebPDFView* _pdfView;
	NSTimer* _autodismisser;
	BOOL _isFadingAway, _isFadingDisabled, _canCancel;
}
@property(readonly,nonatomic) CGSize absoluteSize;
-(void)togglePager;
-(unsigned)setPDFPage:(unsigned)page;
-(unsigned)currentPage;
@property(assign,nonatomic) BOOL gestureEnabled;
@end
@implementation QSAbstractScroller
-(BOOL)gestureEnabled { return _scrollView.gesturesEnabled; }
-(void)setGestureEnabled:(BOOL)val { 
	if ([_scrollView isKindOfClass:[UIScrollView class]]) {
		if (!val) {
			_canCancel = _scrollView.canCancelContentTouches;
			_scrollView.canCancelContentTouches = NO;
		} else {
			_scrollView.canCancelContentTouches = _canCancel;
		}
	}
	_scrollView.gesturesEnabled = val; 
}
-(id)initWithScrollView:(UIScrollView*)scrollView webView:(UIWebDocumentView*)webView pdfView:(WebPDFView*)pdfView {
	if ((self = [super initWithFrame:scrollView.bounds])) {
		_scrollView = [scrollView retain];
		_webView = webView;
		_pdfView = pdfView;
				
		QSCreateOrUpdateTimer(&_autodismisser, autodismiss_timer, self, @selector(fadeAway));

		self.opaque = NO;
		self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		
		[scrollView addSubview:self];
	}
	return self;
}
-(void)disableFading {
	QSDestroyTimer(&_autodismisser);
	_isFadingDisabled = YES;
	self.alpha = 1;
	self.userInteractionEnabled = YES;
}
-(void)enableFading {
	_isFadingDisabled = NO;
	self.alpha = 1;
	self.userInteractionEnabled = YES;
	QSCreateOrUpdateTimer(&_autodismisser, autodismiss_timer, self, @selector(fadeAway));
}
-(void)finishFadingAway {
	_isFadingAway = NO;
	if (_autodismisser == nil && !_isFadingDisabled)
		[self removeFromSuperview];
	else {
		self.alpha = 1;
		self.userInteractionEnabled = YES;
		QSCreateOrUpdateTimer(&_autodismisser, autodismiss_timer, self, @selector(fadeAway));
	}
}
-(void)fadeAway {	
	if (_isFadingAway || _isFadingDisabled)
		return;

	_isFadingAway = YES;
	self.userInteractionEnabled = NO;
	
	QSDestroyTimer(&_autodismisser);
	
	[UIView beginAnimations:@"x"];
	[UIView setAnimationDelegate:self];
	[UIView setAnimationDidStopSelector:@selector(finishFadingAway)];
	self.alpha = 0;
	[UIView commitAnimations];
}
-(void)dealloc {
	QSDestroyTimer(&_autodismisser);
	[_scrollView release];
	[super dealloc];
}
-(void)_didScroll {
	self.frame = _scrollView.bounds;
	if (!_isFadingDisabled)
		QSCreateOrUpdateTimer(&_autodismisser, autodismiss_timer, self, @selector(fadeAway));
	[_scrollView bringSubviewToFront:self];
}
-(UIView*)hitTest:(CGPoint)test forEvent:(GSEventRef)event {
	UIView* res = [super hitTest:test forEvent:event];
	return res == self ? nil : res;
}
-(UIView*)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
	UIView* res = [super hitTest:point withEvent:event];
	return res == self ? nil : res;
}
static UIEdgeInsets getInsets(UIScrollView* sv) {
	return [sv respondsToSelector:@selector(contentInset)] ? sv.contentInset : UIEdgeInsetsZero;
}
static CGSize absoluteSizeWithInsets(UIEdgeInsets insets, UIScrollView* sv) {
	CGSize absSize = sv.contentSize;
	absSize.width += insets.left + insets.right;
	absSize.height += insets.top + insets.bottom;
	return absSize;
}
-(CGSize)absoluteSize {
	return absoluteSizeWithInsets(getInsets(_scrollView), _scrollView);
}
-(CGRect)relativeFrameScaledTo:(CGSize)size; {
	UIEdgeInsets insets = getInsets(_scrollView);
	CGSize absSize = absoluteSizeWithInsets(insets, _scrollView);
	
	absSize.width = size.width/absSize.width;
	absSize.height = size.height/absSize.height;
	
	CGRect fr = CGRectOffset(_scrollView.bounds, insets.left, insets.top);
	
	fr.origin.x *= absSize.width;
	fr.origin.y *= absSize.height;
	fr.size.width *= absSize.width;
	fr.size.height *= absSize.height;
	
	return fr;
}
-(void)scrollTo:(CGPoint)newPt animated:(BOOL)anim {
	if (!anim) {
		[_scrollView setOffset:newPt];
	} else {
		if ([_scrollView respondsToSelector:@selector(setContentOffset:animated:)])
			[_scrollView setContentOffset:newPt animated:anim];
		else {
			CGPoint old = [(UIScroller*)_scrollView offset];
			[(UIScroller*)_scrollView scrollByDelta:CGSizeMake(newPt.x-old.x, newPt.y-old.y) animated:anim];
		}
	}
	[_webView updatePDFPageNumberLabel];
}
-(void)setRelativePoint:(CGPoint)pt withScale:(CGSize)scale animated:(BOOL)anim {
	UIEdgeInsets insets = getInsets(_scrollView);
	CGSize absSize = absoluteSizeWithInsets(insets, _scrollView);
	
	CGPoint newPt;
	newPt.x = pt.x * absSize.width / scale.width;
	newPt.y = pt.y * absSize.height / scale.height;
	
	limitPoint(&newPt, absSize, _scrollView.bounds.size);
	
	newPt.x -= insets.left;
	newPt.y -= insets.top;
	[self scrollTo:newPt animated:anim];
}
-(void)togglePager {}
-(unsigned)currentPage {
	if (_pdfView != nil) {
		return [_pdfView pageNumberForRect:[_pdfView convertRect:_webView.visibleRect fromView:nil]];
	} else if ([_scrollView isKindOfClass:[UIScrollView class]] && ((UIScrollView*)_scrollView).pagingEnabled) {
		CGRect curBounds = _scrollView.bounds;
		unsigned h_pages = roundf(_scrollView.contentSize.width / curBounds.size.width);
		unsigned v_pages = roundf(_scrollView.contentSize.height / curBounds.size.height);
		unsigned x_mul = MIN(roundf(curBounds.origin.x / curBounds.size.width), h_pages-1);
		unsigned y_mul = MIN(roundf(curBounds.origin.y / curBounds.size.height), v_pages-1);
		return x_mul + y_mul * h_pages + 1;
	} else
		return 0;
}
-(unsigned)setPDFPage:(unsigned)page {
	if (_pdfView != nil) {
		CGRect* rects = pageRects(_pdfView);
		unsigned oldPage = [self currentPage];
		page = MIN(page, [_pdfView totalPages]);
		if (page != oldPage) {
			CGPoint newPt = [_pdfView convertPoint:rects[page-1].origin toView:nil];
			[self scrollTo:newPt animated:YES];
		} else
			[_webView updatePDFPageNumberLabel];
	} else if ([_scrollView isKindOfClass:[UIScrollView class]] && ((UIScrollView*)_scrollView).pagingEnabled) {
		CGRect curBounds = _scrollView.bounds;
		unsigned h_pages = roundf(_scrollView.contentSize.width / curBounds.size.width);
		unsigned v_pages = roundf(_scrollView.contentSize.height / curBounds.size.height);
		-- page;
		if (page >= h_pages * v_pages)
			page = h_pages*v_pages - 1;
		CGPoint res;
		unsigned x_mul = (page % h_pages), y_mul = (page / h_pages);
		res.x = x_mul * curBounds.size.width;
		res.y = y_mul * curBounds.size.height;
		[self scrollTo:res animated:YES];
		page = x_mul + y_mul * h_pages + 1;
	}
	return page;
}
-(BOOL)canSetPage {
	return _pdfView != nil || ([_scrollView isKindOfClass:[UIScrollView class]] && ((UIScrollView*)_scrollView).pagingEnabled);
}
@end

static QSAbstractScroller* findAbstractScroller(UIView* view) {
	Class QSAbstractScroller_class = [QSAbstractScroller class];
	for (QSAbstractScroller* scroller in view.subviews)
		if ([scroller isKindOfClass:QSAbstractScroller_class])
			return scroller;
	return nil;
}

#pragma mark -

#define MARGIN 3
#define YMARGIN 2
#define Y2MARGIN 4
#define SPACING 1

@interface QSAbstractPagerView : UIView {
	QSAbstractScroller* _abstractScroller;
}
@property(assign,nonatomic) QSAbstractScroller* abstractScroller;
-(BOOL)isClosing;
@end
@implementation QSAbstractPagerView
@synthesize abstractScroller = _abstractScroller;
-(BOOL)isClosing { return NO; }
-(id)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		self.backgroundColor = [UIColor clearColor];		
	}
	return self;
}
-(void)drawRect:(CGRect)rect {
	CGRect bds = self.bounds;
	[imagesObj[QSI_UIPasscodeFieldButton] drawInRect:bds];
	[imagesObj[[self isClosing]?QSI_K5:QSI_K6] drawAtPoint:CGPointMake(MARGIN, YMARGIN)];
}	
@end

#pragma mark -

@interface QSPagerView : QSAbstractPagerView {
	NSMutableString* _currentPage;
	
	CGRect _rx[12];
	int _activeKey, _movingMode;	// 0 = not moving, 1 = moving, 2 = locked not moving.
	CGPoint _initPos;
	BOOL _appendingMode;
	
	NSTimer* _asTimer, *_dsTimer;
	UIView* _whoToMove;
}
@property(assign,nonatomic) unsigned currentPage;
@property(assign,nonatomic) UIView* whoToMove;
@end
@implementation QSPagerView
@synthesize whoToMove = _whoToMove;
-(BOOL)isClosing { return _activeKey==11; }
-(id)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		_currentPage = [[NSMutableString alloc] initWithString:@"0"];
		
		_activeKey = -1;
		_whoToMove = self;
	}
	return self;
}
-(unsigned)currentPage { return [_currentPage intValue]; }
-(void)setCurrentPage:(unsigned)cp { 
	[_currentPage setString:[NSString stringWithFormat:@"%d", cp]];
	_appendingMode = NO;
	[self setNeedsDisplay];
}
-(void)dealloc {
	QSDestroyTimer(&_asTimer);
	QSDestroyTimer(&_dsTimer);
	[_currentPage release];
	[super dealloc];
}
-(void)setFrame:(CGRect)frame {
	[super setFrame:frame];
	CGFloat k[4];
	k[0] = MARGIN;
	k[1] = MARGIN + SPACING + roundf((frame.size.width-2*(SPACING+MARGIN))/3);
	k[2] = MARGIN + 2*SPACING + roundf((2*frame.size.width-4*(SPACING+MARGIN))/3);
	k[3] = frame.size.width+SPACING-MARGIN;
	for (int i = 0; i < 3; ++ i)
		for (int j = 0; j < 3; ++ j)
			_rx[1+j+(2-i)*3] = CGRectMake(k[j], MARGIN+SPACING+_close_height+i*(_key_height+SPACING), k[j+1]-k[j]-SPACING, _key_height);
	_rx[0] = CGRectMake(k[0], YMARGIN+SPACING+_close_height+3*(_key_height+SPACING), k[2]-k[0]-SPACING, _key_height);
	_rx[10] = CGRectMake(k[2], YMARGIN+SPACING+_close_height+3*(_key_height+SPACING), k[3]-k[2]-SPACING, _key_height);
	_rx[11] = CGRectMake(MARGIN, YMARGIN, _close_height, _close_height);
}

static void drawInCenter(NSString* d, UIFont* fnt, CGRect r) {
	CGSize s = [d sizeWithFont:fnt];
	CGPoint p = CGPointMake(r.origin.x + (r.size.width - s.width)/2, r.origin.y + (r.size.height - s.height)/2);
	[d drawAtPoint:p withFont:fnt];
}

-(void)drawRect:(CGRect)rect {
	[super drawRect:rect];
	
	UIFont* fnt = [UIFont boldSystemFontOfSize:[UIFont systemFontSize]];
	CGContextSetGrayFillColor(UIGraphicsGetCurrentContext(), 1, 1);
	drawInCenter(_currentPage, fnt, CGRectMake(0, YMARGIN, self.bounds.size.width, _close_height));
	
	static NSString* const letters[] = {@"0", @"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"⌫"};
	for (int i = 0; i < 11; ++ i) {
		[imagesObj[i==_activeKey?QSI_K1:QSI_K2] drawInRect:_rx[i]];
		if (i == 0) {
			CGRect rx0 = _rx[0];
			rx0.size.width = (rx0.size.width - SPACING)/2;
			drawInCenter(letters[0], fnt, rx0);
		} else {
			drawInCenter(letters[i], fnt, _rx[i]);
		}
	}
}
-(CGSize)sizeThatFits:(CGSize)size {
	return CGSizeMake(size.width, 4*SPACING + YMARGIN + Y2MARGIN + 4*_key_height + _close_height);
}
-(void)enableNeedsDisplay {
	QSDestroyTimer(&_dsTimer);
}
-(void)tellScrollerCurrentPage {
	QSDestroyTimer(&_asTimer);
	
	unsigned page = (unsigned)[_currentPage intValue];
	
	if (page > 0) {
		self.currentPage = [_abstractScroller setPDFPage:page];
		QSCreateOrUpdateTimer(&_dsTimer, 0.5, self, @selector(enableNeedsDisplay));
	}
}

-(void)touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event {
	UITouch* anyTouch = [touches anyObject];
	_abstractScroller.gestureEnabled = NO;
	
	if (_movingMode == 1) {
		CGPoint pt = [anyTouch locationInView:_whoToMove.superview];
		
		CGRect f0 = _whoToMove.frame;
		f0.origin.x = _initPos.x + pt.x;
		f0.origin.y = _initPos.y + pt.y;
		_whoToMove.frame = f0;
		
	} else {
		CGPoint pt = [anyTouch locationInView:self];
		
		_activeKey = -1;
		for (int i = 0; i < 12; ++ i)
			if (CGRectContainsPoint(_rx[i], pt)) {
				_activeKey = i;
				_movingMode = 2;
				break;
			}
		
		if (_movingMode == 0) {
			if (_activeKey == -1) {
				[_asTimer fire];
				
				_movingMode = 1;
				CGRect fr0 = _whoToMove.frame;
				pt = [anyTouch locationInView:_whoToMove.superview];
				_initPos.x = fr0.origin.x - pt.x;
				_initPos.y = fr0.origin.y - pt.y;
			}
		}
		
		[_abstractScroller disableFading];
		[self setNeedsDisplay];
	}
}
-(BOOL)canUpdatePage {
	return _movingMode == 0 && _asTimer == nil && _dsTimer == nil;
}
-(void)touchesMoved:(NSSet*)touches withEvent:(UIEvent*)event {
	[self touchesBegan:touches withEvent:event];
}
-(void)touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event {
	if (_activeKey != -1) {
		if (_activeKey == 10) {
			NSUInteger len = [_currentPage length];
			if (len == 1) {
				[_currentPage setString:@"0"];
				_appendingMode = NO;
			} else {
				[_currentPage deleteCharactersInRange:NSMakeRange(len-1, 1)];
				_appendingMode = YES;
			}
		} else if (_activeKey == 11) {
			[_abstractScroller togglePager];
		} else {
			if (!_appendingMode) {
				[_currentPage setString:@""];
			}
			[_currentPage appendFormat:@"%d", _activeKey];
			_appendingMode = ![_currentPage isEqualToString:@"0"];
		}
		
		if (_activeKey != 11)
			QSCreateOrUpdateTimer(&_asTimer, 0.75, self, @selector(tellScrollerCurrentPage));

		_activeKey = -1;
		[self setNeedsDisplay];
	} 
	
	_abstractScroller.gestureEnabled = YES;
	[_abstractScroller enableFading];
	
	_movingMode = 0;
}
-(void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
	[self touchesEnded:touches withEvent:event];
}
@end

static CGRect actualToVisual(CGRect act, CGSize maxSize, CGSize minSize) {
	CGRect res = act;
	if (act.size.height < minSize.height) {
		res.origin.y = act.origin.y * (maxSize.height - minSize.height) / (maxSize.height - act.size.height);
		res.size.height = minSize.height;
	}
	if (act.size.width < minSize.width) {
		res.origin.x = act.origin.x * (maxSize.width - minSize.width) / (maxSize.width - act.size.width);
		res.size.width = minSize.width;
	}
	return res;
}
static CGPoint visualToActualPoint(CGPoint visPt, CGSize actSize, CGSize maxSize, CGSize minSize) {
	CGPoint res = visPt;
	if (actSize.height < minSize.height && maxSize.height != minSize.height)
		res.y = res.y * (maxSize.height - actSize.height) / (maxSize.height - minSize.height);
	if (actSize.width < minSize.width && maxSize.width != minSize.width)
		res.x = res.x * (maxSize.width - actSize.width) / (maxSize.width - minSize.width);
	return res;
}

#pragma mark -

#define MINSIZE CGSizeMake(16, 16)
@interface QSDraggerView : QSAbstractPagerView {
	CGSize scale;
	CGRect relativeFrame, visualRelFrame, savedVisualRelFrame;
	CGPoint initTouch;
	BOOL closing;
	BOOL movingMode;
}
@property(assign,nonatomic) CGSize scale;
@end
@implementation QSDraggerView 
@synthesize scale;
-(BOOL)isClosing { return closing; }
-(void)drawRect:(CGRect)rect {
	[super drawRect:rect];
		
	CGRect r = CGRectRound(visualRelFrame);
	r.origin.y += _close_height + SPACING;
		
	[imagesObj[QSI_sel] drawInRect:r];
}
-(void)setRelativeFrame:(CGRect)rf {
	relativeFrame = rf;
	visualRelFrame = actualToVisual(rf, scale, MINSIZE);
}
-(void)shiftRelativeFrameVisuallyBy:(CGSize)shift {
	visualRelFrame = savedVisualRelFrame;
	visualRelFrame.origin.x += shift.width;
	visualRelFrame.origin.y += shift.height;
	
	limitPoint(&visualRelFrame.origin, scale, visualRelFrame.size);
	
	relativeFrame.origin = visualToActualPoint(visualRelFrame.origin, relativeFrame.size, scale, MINSIZE);
	[_abstractScroller setRelativePoint:relativeFrame.origin withScale:scale animated:NO];
}
-(void)touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event {
	[_abstractScroller disableFading];
	_abstractScroller.gestureEnabled = NO;
	//self.exclusiveTouch = YES;
	UITouch* anyTouch = [touches anyObject];
	CGPoint p = [anyTouch locationInView:self];
	
	movingMode = p.y < _close_height + SPACING + YMARGIN;
	
	if (movingMode) {
		closing = (p.x <= _close_height + SPACING + MARGIN);
		[self setNeedsDisplay];
		
		UIView* v = self.superview;
		CGRect fr0 = v.frame;
		p = [anyTouch locationInView:v.superview];
		initTouch.x = fr0.origin.x - p.x;
		initTouch.y = fr0.origin.y - p.y;
		
	} else {
		closing = NO;
		
		CGFloat actual_y = p.y - SPACING - YMARGIN - _close_height;
		
		if (!CGRectContainsPoint(visualRelFrame, CGPointMake(p.x, actual_y))) {
			savedVisualRelFrame = visualRelFrame;
			
			visualRelFrame.origin.x = p.x - visualRelFrame.size.width/2;
			visualRelFrame.origin.y = actual_y - visualRelFrame.size.height/2;
			
			[self shiftRelativeFrameVisuallyBy:CGSizeMake(visualRelFrame.origin.x - savedVisualRelFrame.origin.x,
														  visualRelFrame.origin.y - savedVisualRelFrame.origin.y)];
		}
		savedVisualRelFrame = visualRelFrame;

		initTouch = p;
	}
}
-(void)touchesMoved:(NSSet*)touches withEvent:(UIEvent*)event {
	UITouch* anyTouch = [touches anyObject];
	if (movingMode) {
		UIView* _whoToMove = self.superview;
		
		CGPoint pt = [anyTouch locationInView:_whoToMove.superview];
		
		CGRect f0 = _whoToMove.frame;
		f0.origin.x = initTouch.x + pt.x;
		f0.origin.y = initTouch.y + pt.y;
		_whoToMove.frame = f0;		
	} else {
		CGPoint newTouch = [anyTouch locationInView:self];
		[self shiftRelativeFrameVisuallyBy:CGSizeMake(newTouch.x - initTouch.x, newTouch.y - initTouch.y)];
	}
}
-(void)touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event {
	if (closing) {
		[_abstractScroller togglePager];
	
		closing = NO;
		[self setNeedsDisplay];
	}
	[_abstractScroller enableFading];
	_abstractScroller.gestureEnabled = YES;
	//self.exclusiveTouch = NO;
}
-(void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
	[self touchesEnded:touches withEvent:event];
}
@end


@interface QSDragScroller : QSAbstractScroller {
	QSPagerView* _pager;
	QSDraggerView* _dragger;
	UIView* _pdContainer;
	CGFloat _h;
}
@end
@implementation QSDragScroller
-(id)initWithScrollView:(UIScrollView*)scrollView webView:(UIWebDocumentView*)webView pdfView:(WebPDFView*)pdfView {
	if ((self = [super initWithScrollView:scrollView webView:webView pdfView:pdfView])) {
		BOOL pagerDefault = [self currentPage] != 0;
		
		_pager = [[QSPagerView alloc] initWithFrame:CGRectMake(0, 0, 84, 1)];
		_pager.hidden = !pagerDefault;
		_pager.abstractScroller = self;
		[_pager sizeToFit];
		CGRect pf = _pager.frame;
		_h = pf.size.height;
		pf.origin.x = floorf((_h - 84)/2);
		_pager.frame = pf;
		
		CGSize ss = self.bounds.size;
		
		_pdContainer = [[UIView alloc] initWithFrame:CGRectMake(floorf((ss.width-_h)/2), floorf((ss.height-_h)/2), _h, _h)];
		[_pdContainer addSubview:_pager];
		_pager.whoToMove = _pdContainer;
		[_pager release];
		
		[self addSubview:_pdContainer];
		
		_dragger = [[QSDraggerView alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];
		_dragger.abstractScroller = self;
		_dragger.hidden = pagerDefault;
		[_pdContainer addSubview:_dragger];
		[self _didScroll];
		[_dragger release];
	}
	return self;
}
-(void)_didScroll {
	[super _didScroll];
	
	CGFloat fixed_header = _close_height + SPACING;
	
	CGSize absSize = [self absoluteSize];
	CGSize targetSize = _pdContainer.bounds.size;
	targetSize.height -= fixed_header;
	
	if (absSize.height/absSize.width > targetSize.height/targetSize.width) {
		absSize.width = (absSize.width*targetSize.height)/absSize.height;
		absSize.height = targetSize.height;
		if (absSize.width < targetSize.width/2)
			absSize.width = targetSize.width/2;
	} else {
		absSize.height = (absSize.height*targetSize.width)/absSize.width;
		absSize.width = targetSize.width;
		if (absSize.height < targetSize.height/2)
			absSize.height = targetSize.height/2;
	}
	CGFloat equiAreaRescaler = sqrtf((targetSize.width*targetSize.height)/(2*absSize.height*absSize.width));
	absSize.height *= equiAreaRescaler;
	absSize.width *= equiAreaRescaler;
	
	CGRect relFr = [self relativeFrameScaledTo:absSize];
	
	int disa = 0;
	if (relFr.size.width >= absSize.width) {
		relFr.size.width = absSize.width;
		relFr.origin.x = 0;
		++ disa;
	}
	if (relFr.size.height >= absSize.height) {
		relFr.size.height = absSize.height;
		relFr.origin.y = 0;
		++ disa;
	}
	
	if (!_pager.hidden && [_pager canUpdatePage])
		_pager.currentPage = [self currentPage];
	
	if (disa != 2) {
		_dragger.scale = absSize;
		_dragger.frame = CGRectRound(CGRectMake((targetSize.width-absSize.width)/2, (targetSize.height-absSize.height)/2, absSize.width, absSize.height+fixed_header));
		_dragger.relativeFrame = relFr;
		
		[_dragger setNeedsDisplay];
	} else {
		[self fadeAway];
	}
}
-(void)togglePager {
	if (![self canSetPage])
		return;
	
	BOOL _inPagerView = !_pager.hidden;
	[UIView beginAnimations:@"z"];
	[UIView setAnimationTransition:(_inPagerView?UIViewAnimationTransitionFlipFromLeft:UIViewAnimationTransitionFlipFromRight) forView:_pdContainer cache:YES];
	_pager.hidden = _inPagerView;
	_dragger.hidden = !_inPagerView;
	[self _didScroll];
	[UIView commitAnimations];
}
@end

#pragma mark -

@interface QSScrollbar : UIView {
	CGSize scale;
	QSAbstractScroller* abstractScroller;
	CGRect relativeFrame, visualRelFrame, savedVisualRelFrame;
	CGPoint initTouch;
	NSTimer* autoShiftTimer;
	UIImage* button, *button_down;
	int location;	// -2 = left, -1 = above, 0 = on scrollbar, 1 = below, 2 = right
	BOOL isVertical;
	BOOL isTouchDown;
	BOOL firedOnce;
}
@property(assign,nonatomic) CGSize scale;
@end
@implementation QSScrollbar
@synthesize scale;
-(void)setRelativeFrame:(CGRect)rf {
	relativeFrame = rf;
	visualRelFrame = actualToVisual(rf, self.bounds.size, handleSize);
	
	if (isVertical) {
		visualRelFrame.origin.x = 0;
		visualRelFrame.size.width = handleSize.width;
	} else {
		visualRelFrame.origin.y = 0;
		visualRelFrame.size.height = handleSize.height;
	}
}
-(void)shiftRelativeFrameVisuallyBy:(CGSize)shift {
	visualRelFrame = savedVisualRelFrame;
	visualRelFrame.origin.x += shift.width;
	visualRelFrame.origin.y += shift.height;
	
	CGPoint oldOrigin = relativeFrame.origin;
	relativeFrame.origin = visualToActualPoint(visualRelFrame.origin, relativeFrame.size, self.bounds.size, handleSize);
	if (isVertical)
		relativeFrame.origin.x = oldOrigin.x;
	else
		relativeFrame.origin.y = oldOrigin.y;

	[abstractScroller setRelativePoint:relativeFrame.origin withScale:scale animated:NO];
}

-(id)initWithFrame:(CGRect)frame abstractScroller:(QSAbstractScroller*)absScr vertical:(BOOL)vert
			button:(UIImage*)btn buttonDown:(UIImage*)btnDown {
	if ((self = [super initWithFrame:frame])) {
		isVertical = vert;
		abstractScroller = absScr;
		button = btn;
		button_down = btnDown;
		self.autoresizingMask = vert ? (UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleHeight) : (UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth);
		self.contentMode = UIViewContentModeRedraw;
		self.backgroundColor = [UIColor clearColor];
	}
	return self;
}
-(void)drawRect:(CGRect)rect {
	[isTouchDown?button_down:button drawInRect:CGRectRound(visualRelFrame)];
}

-(void)getLocation:(UITouch*)touch {
	initTouch = [touch locationInView:self];
	if (isVertical) {
		if (initTouch.y < visualRelFrame.origin.y)
			location = -1;
		else if (initTouch.y < visualRelFrame.origin.y + visualRelFrame.size.height)
			location = 0;
		else
			location = 1;
	} else {
		if (initTouch.x < visualRelFrame.origin.x)
			location = -2;
		else if (initTouch.x < visualRelFrame.origin.x + visualRelFrame.size.width)
			location = 0;
		else
			location = 2;
	}
}
-(void)fireAutoShift {
	CGPoint o = relativeFrame.origin;
	firedOnce = YES;
	static const float jump_reducer = 0.9375f;
	switch (location) {
		case -2:
			o.x -= relativeFrame.size.width;
			break;
		case -1:
			o.y -= relativeFrame.size.height * jump_reducer;
			break;
		case 1:
			o.y += relativeFrame.size.height * jump_reducer;
			break;
		case 2:
			o.x += relativeFrame.size.width;
			break;
		default:
			break;
	}
	
	[abstractScroller setRelativePoint:o withScale:scale animated:YES];
}

-(void)touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event {
	[abstractScroller disableFading];
	abstractScroller.gestureEnabled = NO;
	//self.exclusiveTouch = YES;
	
	isTouchDown = YES;
	savedVisualRelFrame = visualRelFrame;
	[self getLocation:[touches anyObject]];
	if (location != 0) {
		if (!scrollbar_jump_by_pages_not) {
			firedOnce = NO;
			[autoShiftTimer invalidate];
			[autoShiftTimer release];
			autoShiftTimer = [[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(fireAutoShift) userInfo:nil repeats:YES] retain];
		} else {
			CGSize delta = CGSizeZero;
			if (isVertical)
				delta.height = initTouch.y - visualRelFrame.size.height/2 - visualRelFrame.origin.y;
			else
				delta.width = initTouch.x - visualRelFrame.size.width/2 - visualRelFrame.origin.x;
			location = 0;
			[self shiftRelativeFrameVisuallyBy:delta];
			savedVisualRelFrame = visualRelFrame;
//			initTouch = visualRelFrame.origin;
		}
	}
	[self setNeedsDisplay];
}
-(void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
	if (location == 0) {
		CGPoint newTouch = [[touches anyObject] locationInView:self];
		CGSize delta = CGSizeZero;
		if (isVertical)
			delta.height = newTouch.y - initTouch.y;
		else
			delta.width = newTouch.x - initTouch.x;
		[self shiftRelativeFrameVisuallyBy:delta];
	}
}
-(void)touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event {
	isTouchDown = NO;
	if (autoShiftTimer) {
		[autoShiftTimer invalidate];
		[autoShiftTimer release];
		autoShiftTimer = nil;
		if (!firedOnce)
			[self fireAutoShift];
		firedOnce = NO;
	}
	[abstractScroller enableFading];
	[abstractScroller _didScroll];
	abstractScroller.gestureEnabled = YES;
	//self.exclusiveTouch = NO;
	[self setNeedsDisplay];
}

-(void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
	[self touchesEnded:touches withEvent:event];
}
-(void)dealloc {
	[autoShiftTimer invalidate];
	[autoShiftTimer release];
	[super dealloc];
}
@end


@interface QSScrollbarView : QSAbstractScroller {
	QSScrollbar* vertBar, *horBar;
	QSPagerView* _pager;
	BOOL _inPagerView;
	BOOL _sih, _siv;
}
@end
@implementation QSScrollbarView
-(void)removeScrollIndicators {
	if ([_scrollView isKindOfClass:[UIScrollView class]]) {
		_sih = _scrollView.showsHorizontalScrollIndicator;
		_siv = _scrollView.showsVerticalScrollIndicator;
		_scrollView.showsHorizontalScrollIndicator = NO;
		_scrollView.showsVerticalScrollIndicator = NO;
	} else {
		_sih = ((UIScroller*)_scrollView).showScrollerIndicators;
		((UIScroller*)_scrollView).showScrollerIndicators = NO;
	}
}
-(void)restoreScrollIndicators {
	if ([_scrollView isKindOfClass:[UIScrollView class]]) {
		_scrollView.showsHorizontalScrollIndicator = _sih;
		_scrollView.showsVerticalScrollIndicator = _siv;
	} else {
		((UIScroller*)_scrollView).showScrollerIndicators = _sih;
	}

}
-(id)initWithScrollView:(UIScrollView*)scrollView webView:(UIWebDocumentView*)webView pdfView:(WebPDFView*)pdfView {
	if ((self = [super initWithScrollView:scrollView webView:webView pdfView:pdfView])) {
		CGRect myFr = self.bounds;
		
		[self removeScrollIndicators];
		
		vertBar = [[QSScrollbar alloc] initWithFrame:CGRectMake(myFr.size.width-handleSize.width, 0, handleSize.width, myFr.size.height-handleSize.height)
									abstractScroller:self vertical:YES button:imagesObj[QSI_2] buttonDown:imagesObj[QSI_3]];
		[self addSubview:vertBar];
		[vertBar release];
		
		horBar = [[QSScrollbar alloc] initWithFrame:CGRectMake(0, myFr.size.height-handleSize.height, myFr.size.width-handleSize.width, handleSize.height)
								   abstractScroller:self vertical:NO button:imagesObj[QSI_0] buttonDown:imagesObj[QSI_1]];
		[self addSubview:horBar];
		[horBar release];
		
		if ([self canSetPage]) {
			UIButton* btn = [[UIButton alloc] initWithFrame:CGRectMake(myFr.size.width-handleSize.width, myFr.size.height-handleSize.height, emptySize.width, emptySize.height)];
			
			[btn setImage:imagesObj[QSI_empty] forState:UIControlStateNormal];
///			[btn setImage:_UIImageWithName(@"UITableNextButtonPressed.png") forState:UIControlStateHighlighted];
			[btn addTarget:self action:@selector(togglePager) forControlEvents:UIControlEventTouchUpInside];
			[self addSubview:btn];
			[btn release];
		}
		
		_pager = [[QSPagerView alloc] initWithFrame:CGRectMake(0, 0, 75, 1)];
		_pager.hidden = YES;
		_pager.abstractScroller = self;
		[self addSubview:_pager];
		[_pager release];		
		
		[self _didScroll];
	}
	return self;
}
-(void)_didScroll {
	[super _didScroll];
	
	CGSize scaleTo = self.bounds.size;
	scaleTo.width -= handleSize.width;
	scaleTo.height -= handleSize.height;
	CGRect relFr = [self relativeFrameScaledTo:scaleTo];
	
	if (_inPagerView || relFr.size.width >= scaleTo.width)
		horBar.hidden = YES;
	else {
		horBar.hidden = NO;
		horBar.scale = scaleTo;
		horBar.relativeFrame = relFr;
		[horBar setNeedsDisplay];
	}
	if (_inPagerView || relFr.size.height >= scaleTo.height)
		vertBar.hidden = YES;
	else {
		vertBar.hidden = NO;
		vertBar.scale = scaleTo;
		vertBar.relativeFrame = relFr;
		[vertBar setNeedsDisplay];
	}
	
	if (_inPagerView && [_pager canUpdatePage])
		_pager.currentPage = [self currentPage];
}
-(void)dealloc {
	[self restoreScrollIndicators];
	[super dealloc];
}
-(void)togglePager {
	
	if (!_inPagerView) {
		CGSize sz = self.bounds.size;
		_pager.frame = CGRectMake(sz.width - 84, sz.height - 137, 84, 137);;
		[_pager sizeToFit];
		[_pager setNeedsDisplay];
		[self restoreScrollIndicators];
	} else {
		[self removeScrollIndicators];
	}

	
	[UIView beginAnimations:@"y"];
	[UIView setAnimationTransition:(_inPagerView?UIViewAnimationTransitionFlipFromLeft:UIViewAnimationTransitionFlipFromRight) forView:_pager cache:YES];
	_pager.hidden = _inPagerView;
	_inPagerView = !_inPagerView;
	[self _didScroll];
	[UIView commitAnimations];
}
@end

#pragma mark -

/*
static CGRect getScrollerRect(UIScrollView* scroller, CGSize size) {
	UIEdgeInsets insets = [scroller respondsToSelector:@selector(contentInset)] ? scroller.contentInset : UIEdgeInsetsZero;
	CGPoint origin = scroller.contentOffset;
	return CGRectMake(origin.x + insets.left, origin.y + insets.top, size.width + insets.left + insets.right, size.height + insets.top + insets.bottom);
}
 */

DefineObjCHook(void, UIWindow__sendTouchesForEvent_, UIWindow* self, SEL _cmd, UIEvent* event) {
	UIScrollView* view = nil;
	UIView* prevView = nil;

	if (event.type == UIEventTypeTouches) {
		NSSet* allTouches = [event allTouches];
		UITouch* anyTouch = [allTouches anyObject];
				
		if (anyTouch.phase == UITouchPhaseEnded && anyTouch.isTap) {
			prevView = anyTouch.view;
									
			if ((activate_by_single_tap) ||
				(activate_by_two_finger_tap && [allTouches count] == 2) ||
				(activate_by_triple_tap && anyTouch.tapCount >= 3)) {
				
				if ([prevView isKindOfClass:[UIScrollView class]] || [prevView isKindOfClass:[UIScroller class]])
					view = (UIScrollView*)prevView;
				else				
					view = [prevView _scroller];
			}
		}
	}
		
	if (view != nil) {		
		// Make sure there isn't an active scrollbar / dragger.
		WebPDFView* pdfView = nil;
		UIWebDocumentView* webView = nil;
		
		QSAbstractScroller* scroller = findAbstractScroller(view);
		if (scroller != nil)
			[scroller _didScroll];
		else {
			if ([prevView isKindOfClass:[UIWebDocumentView class]]) {
				webView = (UIWebDocumentView*)prevView;
				pdfView = WebPDF(webView);
				if (pdfView == nil)
					webView = nil;
			}
			
			scroller = use_scrollbar ? [QSScrollbarView alloc] : [QSDragScroller alloc];
			[[scroller initWithScrollView:view webView:webView pdfView:pdfView] release];
		}
	} 
	
	Original(UIWindow__sendTouchesForEvent_)(self, _cmd, event);
}

DefineObjCHook(void, UIScrollView__notifyDidScroll, UIScrollView* self, SEL _cmd) {
	if (activate_by_scrolling) {
		if (findAbstractScroller(self) == nil) {
			QSAbstractScroller* scroller = use_scrollbar ? [QSScrollbarView alloc] : [QSDragScroller alloc];
			[[scroller initWithScrollView:self webView:nil pdfView:nil] release];
		}
	}
	Original(UIScrollView__notifyDidScroll)(self, _cmd);
}
DefineObjCHook(void, UIScroller__notifyDidScroll, UIScroller* self, SEL _cmd) {
	if (activate_by_scrolling) {
		Class UIWebDocumentView_class = [UIWebDocumentView class], QSAbstractScroller_class = [QSAbstractScroller class];
		UIWebDocumentView* webDoc = nil;
		WebPDFView* pdf = nil;

		for (UIWebDocumentView* v in self.subviews) {
			if ([v isKindOfClass:QSAbstractScroller_class])
				goto ignore;
			else if ([v isKindOfClass:UIWebDocumentView_class])
				webDoc = v;
		}
		
		if (webDoc) {
			pdf = WebPDF(webDoc);
			if (pdf == nil)
				webDoc = nil;
		}
		
		QSAbstractScroller* scroller = use_scrollbar ? [QSScrollbarView alloc] : [QSDragScroller alloc];
		[[scroller initWithScrollView:(UIScrollView*)self webView:webDoc pdfView:pdf] release];
	}
	
ignore:
	Original(UIScroller__notifyDidScroll)(self, _cmd);
}


static UIImage* QSCreateStretchableImage(UIImage* img, int stfl) {
	if (stfl != 0) {
		CGSize sz = img.size;
		NSUInteger w = (stfl & 1) ? sz.width/2 : 0;
		NSUInteger h = (stfl & 2) ? sz.height/2 : 0;
	
		img = [img stretchableImageWithLeftCapWidth:w topCapHeight:h];
	}
	return [img retain];
}

__attribute__((destructor)) void QS2_finish() {
	for (int i = 0; i < sizeof(imagesObj)/sizeof(imagesObj[0]); ++ i)
		[imagesObj[i] release];
	CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), &dummy, CFSTR("hk.kennytm.quickscroll2.reload"), NULL);
}

__attribute__((constructor)) void QS2_initialize() {
	NSAutoreleasePool* pool = [NSAutoreleasePool new];
	
	for (int i = 0; i < sizeof(imagesObj)/sizeof(imagesObj[0]); ++ i) {
		UIImage* img = [UIImage imageWithContentsOfFile:[NSString stringWithFormat:RSRC@"/%@.png", imagesFn[i]]];
		imagesObj[i] = QSCreateStretchableImage(img, imagesStfl[i]);
	}
	handleSize = imagesObj[QSI_0].size;
	emptySize = imagesObj[QSI_empty].size;
	_close_height = imagesObj[QSI_K5].size.height;
	_key_height = imagesObj[QSI_K1].size.height;
	
	reload_prefs();
	
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), &dummy, (CFNotificationCallback)reload_prefs, CFSTR("hk.kennytm.quickscroll2.reload"), NULL, 0);
	
	InstallObjCInstanceHook([UIWindow class], @selector(_sendTouchesForEvent:), UIWindow__sendTouchesForEvent_);
	InstallObjCInstanceHook([UIScrollView class], @selector(_notifyDidScroll), UIScrollView__notifyDidScroll);
	InstallObjCInstanceHook([UIScroller class], @selector(_notifyDidScroll), UIScroller__notifyDidScroll);
	
	[pool drain];
}
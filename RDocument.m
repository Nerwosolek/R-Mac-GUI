/*
 *  R.app : a Cocoa front end to: "R A Computer Language for Statistical Data Analysis"
 *  
 *  R.app Copyright notes:
 *                     Copyright (C) 2004  The R Foundation
 *                     written by Stefano M. Iacus and Simon Urbanek
 *
 *                  
 *  R Copyright notes:
 *                     Copyright (C) 1995-1996   Robert Gentleman and Ross Ihaka
 *                     Copyright (C) 1998-2001   The R Development Core Team
 *                     Copyright (C) 2002-2004   The R Foundation
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  A copy of the GNU General Public License is available via WWW at
 *  http://www.gnu.org/copyleft/gpl.html.  You can also obtain it by
 *  writing to the Free Software Foundation, Inc., 59 Temple Place,
 *  Suite 330, Boston, MA  02111-1307  USA.
 */


#import "RDocument.h"
#import "RController.h"
#import "Preferences.h"
#import "REngine/REngine.h"

BOOL defaultsInitialized = NO;

NSColor *shColorNormal;
NSColor *shColorString;
NSColor *shColorNumber;
NSColor *shColorKeyword;
NSColor *shColorComment;
NSColor *shColorIdentifier;

NSArray *keywordList=nil;

@implementation RDocument

+ (void) setDefaultSyntaxHighlightingColors
{
	shColorNormal=[NSColor blackColor]; [shColorNormal retain];
	shColorString=[NSColor blueColor]; [shColorString retain];
	shColorNumber=[NSColor blueColor]; [shColorNumber retain];
	shColorKeyword=[NSColor colorWithDeviceRed:0.7 green:0.6 blue:0.0 alpha:1.0]; [shColorKeyword retain];
	shColorComment=[NSColor colorWithDeviceRed:0.6 green:0.4 blue:0.4 alpha:1.0]; [shColorComment retain];
	shColorIdentifier=[NSColor colorWithDeviceRed:0.0 green:0.0 blue:0.4 alpha:1.0]; [shColorIdentifier retain];
	
	keywordList = [[NSArray alloc] initWithObjects: @"for", @"if", @"else", @"TRUE", @"FALSE", @"while",
		@"do", @"NULL", @"Inf", @"NA", @"NaN", @"in", nil];
}

/*  Here we only break the modal loop for the R_Edit call. Wether a window
	is to be saved on exit or no, is up to Cocoa
*/ 
- (BOOL)windowShouldClose:(id)sender{
	
	if(isREdit){
		[NSApp stopModal];
		isREdit = NO;
	}
	return YES;
}

- (id)init
{
    self = [super init];
    if (self) {
		updating=NO;
		[[Preferences sharedPreferences] addDependent:self];
		execNewlineFlag=NO;
		if (!defaultsInitialized) {
			[RDocument setDefaultSyntaxHighlightingColors];
			defaultsInitialized=YES;
		}
		highlightColorAttr = [[NSDictionary alloc] initWithObjectsAndKeys:[NSColor selectedTextBackgroundColor], NSBackgroundColorAttributeName, nil];
		initialContents=nil;
		initialContentsType=nil;
		isEditable=YES;
		isREdit=NO;
    }
    return self;
}

- (void)dealloc {
	if (initialContents) [initialContents release];
	if (initialContentsType) [initialContentsType release];
	if (highlightColorAttr) [highlightColorAttr release];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[[Preferences sharedPreferences] removeDependent:self];
	[super dealloc];
}

- (NSString *)windowNibName
{
    // Override returning the nib file name of the document
    // If you need to use a subclass of NSWindowController or if your document supports multiple NSWindowControllers, you should remove this method and override -makeWindowControllers instead.
    return @"RDocument";
}

- (void) loadInitialContents
{
	if (!initialContents || !textView) return;
	if ([initialContentsType isEqual:@"rtf"])
		[textView replaceCharactersInRange:
			NSMakeRange(0, [[textView textStorage] length])
								   withRTF:initialContents];
	else
		[textView replaceCharactersInRange:
			NSMakeRange(0, [[textView textStorage] length])
								   withString:[NSString stringWithCString:[initialContents bytes] length:[initialContents length]]];
	[self updateSyntaxHighlightingForRange:NSMakeRange(0,[[textView textStorage] length])];
	[initialContents release];
	initialContents=nil;
}


- (void)windowControllerDidLoadNib:(NSWindowController *) aController
{
    [super windowControllerDidLoadNib:aController];
		
	[textView setFont:[[RController getRController] currentFont]];
	[textView setContinuousSpellCheckingEnabled:NO]; // by default no continuous spell checking
	[textView setAllowsUndo: YES];
	[self loadInitialContents];
	[textView setEditable: isEditable];
	[[NSNotificationCenter defaultCenter] 
		addObserver:self
		   selector:@selector(textDidChange:)
			   name:NSTextDidChangeNotification
			 object: textView];
	[[textView textStorage] setDelegate:self];	
	[self updatePreferences];
}


- (void) updatePreferences {
	[self setHighlighting:[Preferences flagForKey:showSyntaxColoringKey withDefault: YES]];
	showMatchingBraces = [Preferences flagForKey:showBraceHighlightingKey withDefault: YES];
	braceHighlightInterval = [[Preferences stringForKey:highlightIntervalKey withDefault: @"0.2"] doubleValue];
	[self updateSyntaxHighlightingForRange:NSMakeRange(0,[[textView textStorage] length])];
	[textView setNeedsDisplay:YES];
}

- (NSData *)dataRepresentationOfType:(NSString *)aType
{
	
	// Insert code here to write your document from the given data.  You can also choose to override -fileWrapperRepresentationOfType: or -writeToFile:ofType: instead.
	if([aType isEqual:@"rtf"])
		return [textView RTFFromRange:
			NSMakeRange(0, [[textView string] length])];			
	else
		return (NSData *)[textView string];
}

- (IBAction)printDocument:(id)sender
{
	NSPrintInfo *printInfo;
	NSPrintInfo *sharedInfo;
	NSPrintOperation *printOp;
	NSMutableDictionary *printInfoDict;
	NSMutableDictionary *sharedDict;
	
	sharedInfo = [NSPrintInfo sharedPrintInfo];
	sharedDict = [sharedInfo dictionary];
	printInfoDict = [NSMutableDictionary dictionaryWithDictionary:
		sharedDict];
	
	printInfo = [[NSPrintInfo alloc] initWithDictionary: printInfoDict];
	[printInfo setHorizontalPagination: NSFitPagination];
	[printInfo setVerticalPagination: NSAutoPagination];
	[printInfo setVerticallyCentered:NO];
	
	[textView setBackgroundColor:[NSColor whiteColor]];
	printOp = [NSPrintOperation printOperationWithView:textView 
											 printInfo:printInfo];
	[printOp setShowPanels:YES];
	[printOp runOperation];
	[self updatePreferences];
}

/* This method is implemented to allow image data file to be loaded into R using open
or drag and drop. In case of a successfull loading of image file, we don't want to
create the UI for the document.
*/
- (BOOL)readFromFile:(NSString *)fileName ofType:(NSString *)docType{
		if( [[RController getRController] isImageData:fileName] == 0){
			[[RController getRController] sendInput: [NSString stringWithFormat:@"load(\"%@\")",fileName]];
			[[NSDocumentController sharedDocumentController]  setShouldCreateUI:NO];
			return(YES);
		} else {
			[[NSDocumentController sharedDocumentController]  setShouldCreateUI:YES];
			return( [super readFromFile: fileName ofType: docType] );
		}
}

- (BOOL) loadDataRepresentation: (NSData *)data ofType:(NSString *)aType {
	if (initialContents) {
		[initialContents release];
		initialContents=nil;
	}
	
	initialContentsType = [[NSString alloc] initWithString:aType];
	initialContents = [[NSData alloc] initWithData: data];

	if (textView) [self loadInitialContents];

	return YES;	
}

+ (void) changeDocumentTitle: (NSDocument *)document Title:(NSString *)title{
		NSEnumerator *e = [[document windowControllers] objectEnumerator];
		NSWindowController *wc = nil;
		
		while (wc = [e nextObject]) {
			NSWindow *window = [wc window];
			[window setTitle: title];
		}
}

- (void) setHighlighting: (BOOL) use
{
	useHighlighting=use;
	if (textView) {
		if (use)
			[self updateSyntaxHighlightingForRange:NSMakeRange(0,[[textView textStorage] length])];
		else
			[textView setTextColor:[NSColor blackColor] range:NSMakeRange(0,[[textView textStorage] length])];
	}
}

- (void) setEditable: (BOOL) editable
{
	isEditable=editable;
	if (textView)
		[textView setEditable:editable];
}

- (void) setREditFlag: (BOOL) flag
{
	isREdit=flag;
}

- (BOOL) hasREditFlag
{
	return isREdit;
}

/* This is needed to force the NSDocument to know when edited windows are dirty */
- (void) textDidChange: (NSNotification *)notification{
	NSDocument *document = [[NSDocumentController sharedDocumentController] currentDocument];
	[ document updateChangeCount:NSChangeDone];
}

/* this method is called after editing took place - we use it for updating the syntax highlighting */
- (void)updateSyntaxHighlightingForRange: (NSRange) range
{
	NSTextStorage *ts = [textView textStorage];
	NSString *s = [ts string];
	//NSLog(@"colorize \"%@\"", [s substringWithRange:lr]);

	int i = range.location;
	int bb = i;
	int last = i+range.length;
	BOOL foundItem=NO;

	if (!keywordList) [RDocument setDefaultSyntaxHighlightingColors];
	if (showMatchingBraces) [self highlightBracesWithShift:0 andWarn:YES];
	if (updating || !useHighlighting) return;
	
	updating=YES;
	
	[ts beginEditing];
	while (i < last) {
		foundItem=NO;
		unichar c = [s characterAtIndex:i];
		if (c=='\'' || c=='"') {
			unichar lc=c;
			int ss=i;
			NSRange fr;
			if (i-bb>0) {
				fr=NSMakeRange(bb,i-bb);
				[ts addAttribute:@"shType" value:@"none" range:fr];
				[ts addAttribute:@"NSColor" value:shColorNormal range:fr];
				
				/*
					NSRange drr;
					NSDictionary *dict = [ts attributesAtIndex:fr.location effectiveRange:&drr];
					NSLog(@"dict: %@", dict);
				*/
			}
			i++;
			while (i<last && (c=[s characterAtIndex:i])!=lc) {
				if (c=='\\') { i++; if (i>=last) break; }
				i++;
			}
			fr=NSMakeRange(ss,i-ss+((i==last)?0:1));
			[ts addAttribute:@"shType" value:@"string" range:fr];
			[ts addAttribute:@"NSColor" value:shColorString range:fr];
			bb=i; if (i==last) break;
			i++; bb=i; if (i==last) break;
			c=[s characterAtIndex:i];
			foundItem=YES;
		}
		if (c>='0' && c<='9') {
			int ss=i;
			NSRange fr;
			if (i-bb>0) {
				fr=NSMakeRange(bb,i-bb);
				[ts addAttribute:@"shType" value:@"none" range:fr];
				[ts addAttribute:@"NSColor" value:shColorNormal range:fr];
			}
			i++;
			while (i<last && ((c=[s characterAtIndex:i])=='.' || (c>='0' && c<='9'))) i++;
			fr=NSMakeRange(ss,i-ss);
			[ts addAttribute:@"shType" value:@"number" range:fr];
			[ts addAttribute:@"NSColor" value:shColorNumber range:fr];
			bb=i;
			if (i==last) break;
			c=[s characterAtIndex:i];	
			foundItem=YES;
		}
		if ((c>='a' && c<='z') || (c>='A' && c<='Z') || c=='.') {
			int ss=i;
			NSRange fr;
			if (i-bb>0) {
				fr=NSMakeRange(bb,i-bb);
				[ts addAttribute:@"shType" value:@"none" range:fr];
				[ts addAttribute:@"NSColor" value:shColorNormal range:fr];
			}
			i++;
			while (i<last && ((c=[s characterAtIndex:i])=='_' || c=='.' || (c>='a' && c<='z') || (c>='A' && c<='Z'))) i++;
			fr=NSMakeRange(ss,i-ss);
			
			{
				NSString *word = [s substringWithRange:fr];
				if (word && keywordList && [keywordList containsObject:word]) {
					[ts addAttribute:@"shType" value:@"keyword" range:fr];
					[ts addAttribute:@"NSColor" value:shColorKeyword range:fr];
				} else {
					[ts addAttribute:@"shType" value:@"id" range:fr];
					[ts addAttribute:@"NSColor" value:shColorIdentifier range:fr];
				}
			}
			bb=i;
			if (i==last) break;
			c=[s characterAtIndex:i];	
			foundItem=YES;
		}
		if (c=='#') {
			int ss=i;
			NSRange fr;
			if (i-bb>0) {
				fr=NSMakeRange(bb,i-bb);
				[ts addAttribute:@"shType" value:@"none" range:fr];
				[ts addAttribute:@"NSColor" value:shColorNormal range:fr];
			}
			i++;
			while (i<last && ((c=[s characterAtIndex:i])!='\n' && c!='\r')) i++;
			fr=NSMakeRange(ss,i-ss);
			[ts addAttribute:@"shType" value:@"comment" range:fr];
			[ts addAttribute:@"NSColor" value:shColorComment range:fr];
			bb=i;
			if (i==last) break;
			c=[s characterAtIndex:i];
			foundItem=YES;
		}
		if (!foundItem) i++;
	}
	if (bb<last && i-bb>0) {
		NSRange fr=NSMakeRange(bb,i-bb);
		[ts addAttribute:@"shType" value:@"none" range:fr];
		[ts addAttribute:@"NSColor" value:shColorNormal range:fr];
	}
	[ts endEditing];
	updating=NO;
}

- (void) highlightBracesWithShift: (int) shift andWarn: (BOOL) warn
{
	NSString *completeString = [[textView textStorage] string];
	unsigned int completeStringLength = [completeString length];
	if (completeStringLength < 2) return;
	
	NSRange selRange = [textView selectedRange];
	unsigned int cursorLocation = selRange.location;
	cursorLocation+=shift; // add any shift as cursor movement guys need it
	if (cursorLocation<0 || cursorLocation>=completeStringLength) return;
	
	unichar characterToCheck;
	unichar openingChar = 0;
	characterToCheck = [completeString characterAtIndex:cursorLocation];
	int skipMatchingBrace = 0;
	
	if (characterToCheck == ')') openingChar='(';
	else if (characterToCheck == ']') openingChar='[';
	else if (characterToCheck == '}') openingChar='{';
	
	// well, this is rather simple so far, because it ignores cross-quoting, but for a first shot it's not too bad ;)
	if (openingChar) {
		while (cursorLocation--) {
			unichar c = [completeString characterAtIndex:cursorLocation];
			if (c == openingChar) {
				if (!skipMatchingBrace) {
					[[textView layoutManager] addTemporaryAttributes:highlightColorAttr forCharacterRange:NSMakeRange(cursorLocation, 1)];
					[self performSelector:@selector(resetBackgroundColor:) withObject:NSStringFromRange(NSMakeRange(cursorLocation, 1)) afterDelay:braceHighlightInterval];
					return;
				} else
					skipMatchingBrace--;
			} else if (c == characterToCheck)
				skipMatchingBrace++;
		}
		if (warn) NSBeep();
	} else { // ok, now reverse the roles and find the closing brace (if any)
		unsigned maxLimit=completeStringLength;
		//if (cursorLocation-maxLimit>4000) maxLimit=cursorLocation+4000; // just a soft limit to not search too far (but I think we're fast enough...)
		if (characterToCheck == '(') openingChar=')';
		else if (characterToCheck == '[') openingChar=']';
		else if (characterToCheck == '{') openingChar='}';		
		if (openingChar) {
			while ((++cursorLocation)<maxLimit) {
				unichar c = [completeString characterAtIndex:cursorLocation];
				if (c == openingChar) {
					if (!skipMatchingBrace) {
						[[textView layoutManager] addTemporaryAttributes:highlightColorAttr forCharacterRange:NSMakeRange(cursorLocation, 1)];
						[self performSelector:@selector(resetBackgroundColor:) withObject:NSStringFromRange(NSMakeRange(cursorLocation, 1)) afterDelay:braceHighlightInterval];
						return;
					} else
						skipMatchingBrace--;
				} else if (c == characterToCheck)
					skipMatchingBrace++;
			}
		}
	}
}

-(void)resetBackgroundColor:(id)sender
{
	// we need to clear the whole BG because the text may have changed in between and we have the old position and not NSRangeFromString(sender)
	[[textView layoutManager] removeTemporaryAttribute:NSBackgroundColorAttributeName forCharacterRange:NSMakeRange(0,[[[textView textStorage] string] length])];
}

- (void)textStorageDidProcessEditing:(NSNotification *)aNotification {
	NSTextStorage *ts = [aNotification object];
	NSString *s = [ts string];
	NSRange er = [ts editedRange];
	
	/* get all lines that span the range that was affected. this impementation updates only lines containing the change, not beyond */
	NSRange lr = [s lineRangeForRange:er];
	
	lr.length = [ts length]-lr.location; // change everything up to the end of the document ...
	
	//NSLog(@"line range %d:%d (original was %d:%d)", lr.location, lr.length, er.location, er.length);
	[self updateSyntaxHighlightingForRange:lr];
}

- (BOOL)textView:(NSTextView *)textViewSrc doCommandBySelector:(SEL)commandSelector {
    BOOL retval = NO;
	if (textViewSrc!=textView) return NO;
	//NSLog(@"RTextView commandSelector: %@\n", NSStringFromSelector(commandSelector));
    if (@selector(insertNewline:) == commandSelector && execNewlineFlag) {
		execNewlineFlag=NO;
		return YES;
	}
    if (@selector(insertNewline:) == commandSelector) {
		// handling of indentation
		// currently we just copy what we get and add tabs for additional non-matched { brackets
		NSTextStorage *ts = [textView textStorage];
		NSString *s = [ts string];
		NSRange csr = [textView selectedRange];
		NSRange ssr = NSMakeRange(csr.location, 0);
		NSRange lr = [s lineRangeForRange:ssr]; // line on which enter was pressed - this will be taken as guide
		if (csr.location>0) {
			int i=lr.location;
			int last=csr.location;
			int whiteSpaces=0, addShift=0;
			BOOL initial=YES;
			NSString *wss=@"\n";
			while (i<last) {
				unichar c=[s characterAtIndex:i];
				if (initial) {
					if (c=='\t' || c==' ') whiteSpaces++;
					else initial=NO;
				}
				if (c=='{') addShift++;
				if (c=='}' && addShift>0) addShift--;
				i++;
			}
			if (whiteSpaces>0)
				wss = [wss stringByAppendingString:[s substringWithRange:NSMakeRange(lr.location,whiteSpaces)]];
			while (addShift>0) { wss=[wss stringByAppendingString:@"\t"]; addShift--; }
			[textView insertText:wss];
			return YES;
		}
	}
    if (showMatchingBraces) {
		if (commandSelector == @selector(moveLeft:))
			[self highlightBracesWithShift: -2 andWarn:NO];
		if(commandSelector == @selector(moveRight:))
			[self highlightBracesWithShift: 0 andWarn:NO];
	}
	
	return retval;
}

- (IBAction)executeSelection:(id)sender
{
	NSRange sr = [textView selectedRange];
	if (sr.length>0) {
		NSString *stx = [[[textView textStorage] string] substringWithRange:sr];
		[[RController getRController] sendInput:stx];
	}
	execNewlineFlag=YES;
}

- (IBAction)sourceCurrentDocument:(id)sender
{
	if ([self isDocumentEdited]) {
		RSEXP *x=[[REngine mainEngine] evaluateString:@"tempfile()"];
		NSString *fn=nil;
		if (x && (fn=[x string])) {
			if ([self writeToFile:fn ofType:@"R"]) {
				[[RController getRController] sendInput:[NSString stringWithFormat:@"source(\"%@\")\nunlink(\"%@\")", fn, fn]];
			}
		}
	} else {
		NSString *fn=[self fileName];
		if (fn) {
			[[RController getRController] sendInput:[NSString stringWithFormat:@"source(\"%@\")", fn]];
		}
	}
}

@end


/*****************************************************************************
 * MainWindow.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2002-2012 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Felix Paul Kühne <fkuehne -at- videolan -dot- org>
 *          Jon Lech Johansen <jon-vl@nanocrew.net>
 *          Christophe Massiot <massiot@via.ecp.fr>
 *          Derk-Jan Hartman <hartman at videolan.org>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "CompatibilityFixes.h"
#import "MainWindow.h"
#import "intf.h"
#import "CoreInteraction.h"
#import "AudioEffects.h"
#import "MainMenu.h"
#import "open.h"
#import "controls.h" // TODO: remove me
#import "playlist.h"
#import "SideBarItem.h"
#import <math.h>
#import <vlc_playlist.h>
#import <vlc_aout_intf.h>
#import <vlc_url.h>
#import <vlc_strings.h>
#import <vlc_services_discovery.h>
#import <vlc_aout_intf.h>

#import "ControlsBar.h"


@interface VLCMainWindow ()
- (void)resizePlaylistAfterCollapse;
- (void)makeSplitViewVisible;
- (void)makeSplitViewHidden;

@end

@implementation VLCMainWindow
static const float f_min_video_height = 70.0;

static VLCMainWindow *_o_sharedInstance = nil;

+ (VLCMainWindow *)sharedInstance
{
    return _o_sharedInstance ? _o_sharedInstance : [[self alloc] init];
}

#pragma mark -
#pragma mark Initialization

- (id)init
{
    if (_o_sharedInstance) {
        [self dealloc];
        return _o_sharedInstance;
    } else
        _o_sharedInstance = [super init];

    return _o_sharedInstance;
}

- (id)initWithContentRect:(NSRect)contentRect styleMask:(NSUInteger)styleMask
                  backing:(NSBackingStoreType)backingType defer:(BOOL)flag
{
    self = [super initWithContentRect:contentRect styleMask:styleMask
                              backing:backingType defer:flag];
    _o_sharedInstance = self;

    [[VLCMain sharedInstance] updateTogglePlaylistState];

    return self;
}

- (BOOL)isEvent:(NSEvent *)o_event forKey:(const char *)keyString
{
    char *key;
    NSString *o_key;

    key = config_GetPsz(VLCIntf, keyString);
    o_key = [NSString stringWithFormat:@"%s", key];
    FREENULL(key);

    unsigned int i_keyModifiers = [[VLCStringUtility sharedInstance] VLCModifiersToCocoa:o_key];

    NSString * characters = [o_event charactersIgnoringModifiers];
    if ([characters length] > 0) {
        return [[characters lowercaseString] isEqualToString: [[VLCStringUtility sharedInstance] VLCKeyToString: o_key]] &&
                (i_keyModifiers & NSShiftKeyMask)     == ([o_event modifierFlags] & NSShiftKeyMask) &&
                (i_keyModifiers & NSControlKeyMask)   == ([o_event modifierFlags] & NSControlKeyMask) &&
                (i_keyModifiers & NSAlternateKeyMask) == ([o_event modifierFlags] & NSAlternateKeyMask) &&
                (i_keyModifiers & NSCommandKeyMask)   == ([o_event modifierFlags] & NSCommandKeyMask);
    }
    return NO;
}

- (BOOL)performKeyEquivalent:(NSEvent *)o_event
{
    BOOL b_force = NO;
    // these are key events which should be handled by vlc core, but are attached to a main menu item
    if (![self isEvent: o_event forKey: "key-vol-up"] &&
        ![self isEvent: o_event forKey: "key-vol-down"] &&
        ![self isEvent: o_event forKey: "key-vol-mute"]) {
        /* We indeed want to prioritize some Cocoa key equivalent against libvlc,
         so we perform the menu equivalent now. */
        if ([[NSApp mainMenu] performKeyEquivalent:o_event])
            return TRUE;
    }
    else
        b_force = YES;

    return [[VLCMain sharedInstance] hasDefinedShortcutKey:o_event force:b_force] ||
           [(VLCControls *)[[VLCMain sharedInstance] controls] keyEvent:o_event];
}

- (void)dealloc
{
    if (b_dark_interface)
        [o_color_backdrop release];

    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [o_sidebaritems release];

    if (o_extra_video_window) {
        [o_extra_video_window release];
        o_extra_video_window = nil;
    }

    [super dealloc];
}

- (void)awakeFromNib
{
    BOOL b_splitviewShouldBeHidden = NO;

    /* setup the styled interface */
    b_nativeFullscreenMode = NO;
#ifdef MAC_OS_X_VERSION_10_7
    if (!OSX_SNOW_LEOPARD)
        b_nativeFullscreenMode = var_InheritBool(VLCIntf, "macosx-nativefullscreenmode");
#endif
    t_hide_mouse_timer = nil;
    [self useOptimizedDrawing: YES];
    
    [[o_search_fld cell] setPlaceholderString: _NS("Search")];
    [[o_search_fld cell] accessibilitySetOverrideValue:_NS("Enter a term to search the playlist. Results will be selected in the table.") forAttribute:NSAccessibilityDescriptionAttribute];

    [o_dropzone_btn setTitle: _NS("Open media...")];
    [[o_dropzone_btn cell] accessibilitySetOverrideValue:_NS("Click to open an advanced dialog to select the media to play. You can also drop files here to play.") forAttribute:NSAccessibilityDescriptionAttribute];
    [o_dropzone_lbl setStringValue: _NS("Drop media here")];

    [o_podcast_add_btn setTitle: _NS("Subscribe")];
    [o_podcast_remove_btn setTitle: _NS("Unsubscribe")];
    [o_podcast_subscribe_title_lbl setStringValue: _NS("Subscribe to a podcast")];
    [o_podcast_subscribe_subtitle_lbl setStringValue: _NS("Enter URL of the podcast to subscribe to:")];
    [o_podcast_subscribe_cancel_btn setTitle: _NS("Cancel")];
    [o_podcast_subscribe_ok_btn setTitle: _NS("Subscribe")];
    [o_podcast_unsubscribe_title_lbl setStringValue: _NS("Unsubscribe from a podcast")];
    [o_podcast_unsubscribe_subtitle_lbl setStringValue: _NS("Select the podcast you would like to unsubscribe from:")];
    [o_podcast_unsubscribe_ok_btn setTitle: _NS("Unsubscribe")];
    [o_podcast_unsubscribe_cancel_btn setTitle: _NS("Cancel")];

    /* interface builder action */
    float f_threshold_height = f_min_video_height + [[o_controls_bar bottomBarView] frame].size.height;
    if (b_dark_interface)
        f_threshold_height += [o_titlebar_view frame].size.height;
    if ([[self contentView] frame].size.height < f_threshold_height)
        b_splitviewShouldBeHidden = YES;

    [self setDelegate: self];
    [self setExcludedFromWindowsMenu: YES];
    [self setAcceptsMouseMovedEvents: YES];
    // Set that here as IB seems to be buggy
    if (b_dark_interface) {
        [self setContentMinSize:NSMakeSize(604., 288. + [o_titlebar_view frame].size.height)];
    } else {
        [self setContentMinSize:NSMakeSize(604., 288.)];
    }

    [self setTitle: _NS("VLC media player")];

    b_dropzone_active = YES;
    o_temp_view = [[NSView alloc] init];
    [o_temp_view setAutoresizingMask:NSViewHeightSizable | NSViewWidthSizable];
    [o_dropzone_view setFrame: [o_playlist_table frame]];
    [o_left_split_view setFrame: [o_sidebar_view frame]];
    
    if (b_nativeFullscreenMode) {
        [self setCollectionBehavior: NSWindowCollectionBehaviorFullScreenPrimary];
    } else {
        [o_titlebar_view setFullscreenButtonHidden: YES];
    }

    if (!OSX_SNOW_LEOPARD) {
        /* the default small size of the search field is slightly different on Lion, let's work-around that */
        NSRect frame;
        frame = [o_search_fld frame];
        frame.origin.y = frame.origin.y + 2.0;
        frame.size.height = frame.size.height - 1.0;
        [o_search_fld setFrame: frame];
    }

    /* create the sidebar */
    o_sidebaritems = [[NSMutableArray alloc] init];
    SideBarItem *libraryItem = [SideBarItem itemWithTitle:_NS("LIBRARY") identifier:@"library"];
    SideBarItem *playlistItem = [SideBarItem itemWithTitle:_NS("Playlist") identifier:@"playlist"];
    [playlistItem setIcon: [NSImage imageNamed:@"sidebar-playlist"]];
    SideBarItem *medialibraryItem = [SideBarItem itemWithTitle:_NS("Media Library") identifier:@"medialibrary"];
    [medialibraryItem setIcon: [NSImage imageNamed:@"sidebar-playlist"]];
    SideBarItem *mycompItem = [SideBarItem itemWithTitle:_NS("MY COMPUTER") identifier:@"mycomputer"];
    SideBarItem *devicesItem = [SideBarItem itemWithTitle:_NS("DEVICES") identifier:@"devices"];
    SideBarItem *lanItem = [SideBarItem itemWithTitle:_NS("LOCAL NETWORK") identifier:@"localnetwork"];
    SideBarItem *internetItem = [SideBarItem itemWithTitle:_NS("INTERNET") identifier:@"internet"];

    /* SD subnodes, inspired by the Qt4 intf */
    char **ppsz_longnames;
    int *p_categories;
    char **ppsz_names = vlc_sd_GetNames(pl_Get(VLCIntf), &ppsz_longnames, &p_categories);
    if (!ppsz_names)
        msg_Err(VLCIntf, "no sd item found"); //TODO
    char **ppsz_name = ppsz_names, **ppsz_longname = ppsz_longnames;
    int *p_category = p_categories;
    NSMutableArray *internetItems = [[NSMutableArray alloc] init];
    NSMutableArray *devicesItems = [[NSMutableArray alloc] init];
    NSMutableArray *lanItems = [[NSMutableArray alloc] init];
    NSMutableArray *mycompItems = [[NSMutableArray alloc] init];
    NSString *o_identifier;
    for (; *ppsz_name; ppsz_name++, ppsz_longname++, p_category++) {
        o_identifier = [NSString stringWithCString: *ppsz_name encoding: NSUTF8StringEncoding];
        switch (*p_category) {
            case SD_CAT_INTERNET:
                    [internetItems addObject: [SideBarItem itemWithTitle: _NS(*ppsz_longname) identifier: o_identifier]];
                    if (!strncmp(*ppsz_name, "podcast", 7))
                        [[internetItems lastObject] setIcon: [NSImage imageNamed:@"sidebar-podcast"]];
                    else
                        [[internetItems lastObject] setIcon: [NSImage imageNamed:@"NSApplicationIcon"]];
                    [[internetItems lastObject] setSdtype: SD_CAT_INTERNET];
                    [[internetItems lastObject] setUntranslatedTitle: [NSString stringWithUTF8String: *ppsz_longname]];
                break;
            case SD_CAT_DEVICES:
                    [devicesItems addObject: [SideBarItem itemWithTitle: _NS(*ppsz_longname) identifier: o_identifier]];
                    [[devicesItems lastObject] setIcon: [NSImage imageNamed:@"NSApplicationIcon"]];
                    [[devicesItems lastObject] setSdtype: SD_CAT_DEVICES];
                    [[devicesItems lastObject] setUntranslatedTitle: [NSString stringWithUTF8String: *ppsz_longname]];
                break;
            case SD_CAT_LAN:
                    [lanItems addObject: [SideBarItem itemWithTitle: _NS(*ppsz_longname) identifier: o_identifier]];
                    [[lanItems lastObject] setIcon: [NSImage imageNamed:@"sidebar-local"]];
                    [[lanItems lastObject] setSdtype: SD_CAT_LAN];
                    [[lanItems lastObject] setUntranslatedTitle: [NSString stringWithUTF8String: *ppsz_longname]];
                break;
            case SD_CAT_MYCOMPUTER:
                    [mycompItems addObject: [SideBarItem itemWithTitle: _NS(*ppsz_longname) identifier: o_identifier]];
                    if (!strncmp(*ppsz_name, "video_dir", 9))
                        [[mycompItems lastObject] setIcon: [NSImage imageNamed:@"sidebar-movie"]];
                    else if (!strncmp(*ppsz_name, "audio_dir", 9))
                        [[mycompItems lastObject] setIcon: [NSImage imageNamed:@"sidebar-music"]];
                    else if (!strncmp(*ppsz_name, "picture_dir", 11))
                        [[mycompItems lastObject] setIcon: [NSImage imageNamed:@"sidebar-pictures"]];
                    else
                        [[mycompItems lastObject] setIcon: [NSImage imageNamed:@"NSApplicationIcon"]];
                    [[mycompItems lastObject] setUntranslatedTitle: [NSString stringWithUTF8String: *ppsz_longname]];
                    [[mycompItems lastObject] setSdtype: SD_CAT_MYCOMPUTER];
                break;
            default:
                msg_Warn(VLCIntf, "unknown SD type found, skipping (%s)", *ppsz_name);
                break;
        }

        free(*ppsz_name);
        free(*ppsz_longname);
    }
    [mycompItem setChildren: [NSArray arrayWithArray: mycompItems]];
    [devicesItem setChildren: [NSArray arrayWithArray: devicesItems]];
    [lanItem setChildren: [NSArray arrayWithArray: lanItems]];
    [internetItem setChildren: [NSArray arrayWithArray: internetItems]];
    [mycompItems release];
    [devicesItems release];
    [lanItems release];
    [internetItems release];
    free(ppsz_names);
    free(ppsz_longnames);
    free(p_categories);

    [libraryItem setChildren: [NSArray arrayWithObjects: playlistItem, medialibraryItem, nil]];
    [o_sidebaritems addObject: libraryItem];
    if ([mycompItem hasChildren])
        [o_sidebaritems addObject: mycompItem];
    if ([devicesItem hasChildren])
        [o_sidebaritems addObject: devicesItem];
    if ([lanItem hasChildren])
        [o_sidebaritems addObject: lanItem];
    if ([internetItem hasChildren])
        [o_sidebaritems addObject: internetItem];

    [o_sidebar_view reloadData];
    [o_sidebar_view selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
    [o_sidebar_view setDropItem:playlistItem dropChildIndex:NSOutlineViewDropOnItemIndex];
    [o_sidebar_view registerForDraggedTypes:[NSArray arrayWithObjects: NSFilenamesPboardType, @"VLCPlaylistItemPboardType", nil]];

    [o_sidebar_view setAutosaveName:@"mainwindow-sidebar"];
    [(PXSourceList *)o_sidebar_view setDataSource:self];
    [o_sidebar_view setDelegate:self];
    [o_sidebar_view setAutosaveExpandedItems:YES];

    [o_sidebar_view expandItem: libraryItem expandChildren: YES];

    /* make sure we display the desired default appearance when VLC launches for the first time */
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults objectForKey:@"VLCFirstRun"]) {
        [defaults setObject:[NSDate date] forKey:@"VLCFirstRun"];

        NSUInteger i_sidebaritem_count = [o_sidebaritems count];
        for (NSUInteger x = 0; x < i_sidebaritem_count; x++)
            [o_sidebar_view expandItem: [o_sidebaritems objectAtIndex: x] expandChildren: YES];
    }

    if (b_dark_interface) {
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(windowResizedOrMoved:) name: NSWindowDidResizeNotification object: nil];
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(windowResizedOrMoved:) name: NSWindowDidMoveNotification object: nil];

        [self setBackgroundColor: [NSColor clearColor]];
        [self setOpaque: NO];
        [self display];
        [self setHasShadow:NO];
        [self setHasShadow:YES];

        NSRect winrect = [self frame];
        CGFloat f_titleBarHeight = [o_titlebar_view frame].size.height;

        [o_titlebar_view setFrame: NSMakeRect(0, winrect.size.height - f_titleBarHeight,
                                              winrect.size.width, f_titleBarHeight)];
        [[self contentView] addSubview: o_titlebar_view positioned: NSWindowAbove relativeTo: o_split_view];

        if (winrect.size.height > 100) {
            [self setFrame: winrect display:YES animate:YES];
            previousSavedFrame = winrect;
        }

        winrect = [o_split_view frame];
        winrect.size.height = winrect.size.height - f_titleBarHeight;
        [o_split_view setFrame: winrect];
        [o_video_view setFrame: winrect];

        o_color_backdrop = [[VLCColorView alloc] initWithFrame: [o_split_view frame]];
        [[self contentView] addSubview: o_color_backdrop positioned: NSWindowBelow relativeTo: o_split_view];
        [o_color_backdrop setAutoresizingMask:NSViewHeightSizable | NSViewWidthSizable];
        
    } else {
        [o_video_view setFrame: [o_split_view frame]];
        [o_playlist_table setBorderType: NSNoBorder];
        [o_sidebar_scrollview setBorderType: NSNoBorder];
    }

    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(someWindowWillClose:) name: NSWindowWillCloseNotification object: nil];
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(someWindowWillMiniaturize:) name: NSWindowWillMiniaturizeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(applicationWillTerminate:) name: NSApplicationWillTerminateNotification object: nil];

    [o_split_view setAutosaveName:@"10thanniversary-splitview"];
    if (b_splitviewShouldBeHidden) {
        [self hideSplitView];
        i_lastSplitViewHeight = 300;
    }

    /* sanity check for the window size */
    NSRect frame = [self frame];
    NSSize screenSize = [[self screen] frame].size;
    if (screenSize.width <= frame.size.width || screenSize.height <= frame.size.height) {
        nativeVideoSize = screenSize;
        [self resizeWindow];
    }
}

#pragma mark -

- (VLCMainWindowControlsBar *)controlsBar;
{
    return (VLCMainWindowControlsBar *)o_controls_bar;
}

- (void)resizePlaylistAfterCollapse
{
    NSRect plrect;
    plrect = [o_playlist_table frame];
    plrect.size.height = i_lastSplitViewHeight - 20.0; // actual pl top bar height, which differs from its frame
    [[o_playlist_table animator] setFrame: plrect];

    NSRect rightSplitRect;
    rightSplitRect = [o_right_split_view frame];
    plrect = [o_dropzone_box frame];
    plrect.origin.x = (rightSplitRect.size.width - plrect.size.width) / 2;
    plrect.origin.y = (rightSplitRect.size.height - plrect.size.height) / 2;
    [[o_dropzone_box animator] setFrame: plrect];
}

- (void)makeSplitViewVisible
{
    if (b_dark_interface)
        [self setContentMinSize: NSMakeSize(604., 288. + [o_titlebar_view frame].size.height)];
    else
        [self setContentMinSize: NSMakeSize(604., 288.)];

    NSRect old_frame = [self frame];
    float newHeight = [self minSize].height;
    if (old_frame.size.height < newHeight) {
        NSRect new_frame = old_frame;
        new_frame.origin.y = old_frame.origin.y + old_frame.size.height - newHeight;
        new_frame.size.height = newHeight;

        [[self animator] setFrame: new_frame display: YES animate: YES];
    }

    [o_video_view setHidden: YES];
    [o_split_view setHidden: NO];
    [self makeFirstResponder: nil];

}

- (void)makeSplitViewHidden
{
    if (b_dark_interface)
        [self setContentMinSize: NSMakeSize(604., f_min_video_height + [o_titlebar_view frame].size.height)];
    else
        [self setContentMinSize: NSMakeSize(604., f_min_video_height)];

    [o_split_view setHidden: YES];
    [o_video_view setHidden: NO];

    if ([[o_video_view subviews] count] > 0)
        [self makeFirstResponder: [[o_video_view subviews] objectAtIndex:0]];
}

// only exception for an controls bar button action
- (IBAction)togglePlaylist:(id)sender
{
    if (![self isVisible] && sender != nil) {
        [self makeKeyAndOrderFront: sender];
        return;
    }

    BOOL b_activeVideo = [[VLCMain sharedInstance] activeVideoPlayback];
    BOOL b_restored = NO;

    // TODO: implement toggle playlist in this situation (triggerd via menu item).
    // but for now we block this case, to avoid displaying only the half
    if (b_nativeFullscreenMode && b_fullscreen && b_activeVideo && sender != nil)
        return;

    if (b_dropzone_active && ([[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask) != 0) {
        [self hideDropZone];
        return;
    }

    if (!(b_nativeFullscreenMode && b_fullscreen) && !b_splitview_removed && ((([[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask) != 0 && b_activeVideo)
                                                                              || (b_nonembedded && sender != nil)
                                                                              || (!b_activeVideo && sender != nil)
                                                                              || b_minimized_view))
        [self hideSplitView];
    else {
        if (b_splitview_removed) {
            if (!b_nonembedded || (sender != nil && b_nonembedded))
                [self showSplitView];

            if (sender == nil)
                b_minimized_view = YES;
            else
                b_minimized_view = NO;

            if (b_activeVideo)
                b_restored = YES;
        }

        if (!b_nonembedded) {
            if (([o_video_view isHidden] && b_activeVideo) || b_restored || (b_activeVideo && sender == nil))
                [self makeSplitViewHidden];
            else
                [self makeSplitViewVisible];
        } else {
            [o_split_view setHidden: NO];
            [o_playlist_table setHidden: NO];
            [o_video_view setHidden: !b_activeVideo];
            if (b_activeVideo && [[o_video_view subviews] count] > 0)
                [[o_video_view window] makeFirstResponder: [[o_video_view subviews] objectAtIndex:0]];
        }
    }
}

- (IBAction)dropzoneButtonAction:(id)sender
{
    [[[VLCMain sharedInstance] open] openFileGeneric];
}

#pragma mark -
#pragma mark overwritten default functionality

- (void)windowResizedOrMoved:(NSNotification *)notification
{
    [self saveFrameUsingName: [self frameAutosaveName]];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [self saveFrameUsingName: [self frameAutosaveName]];
}


- (void)someWindowWillClose:(NSNotification *)notification
{
    id obj = [notification object];
    if (obj == o_detached_video_window || obj == o_extra_video_window || (obj == self && !b_nonembedded)) {
        if ([[VLCMain sharedInstance] activeVideoPlayback])
            [[VLCCoreInteraction sharedInstance] stop];
    }
}

- (void)someWindowWillMiniaturize:(NSNotification *)notification
{
    if (config_GetInt(VLCIntf, "macosx-pause-minimized")) {
        id obj = [notification object];
        if (obj == o_detached_video_window || obj == o_extra_video_window || (obj == self && !b_nonembedded)) {
            if ([[VLCMain sharedInstance] activeVideoPlayback])
                [[VLCCoreInteraction sharedInstance] pause];
        }
    }
}

- (NSSize)windowWillResize:(NSWindow *)window toSize:(NSSize)proposedFrameSize
{
    id videoWindow = [o_video_view window];
    if (![[VLCMain sharedInstance] activeVideoPlayback] || nativeVideoSize.width == 0. || nativeVideoSize.height == 0. || window != videoWindow)
        return proposedFrameSize;

    // needed when entering lion fullscreen mode
    if (b_fullscreen)
        return proposedFrameSize;

    if ([[VLCCoreInteraction sharedInstance] aspectRatioIsLocked]) {
        NSRect videoWindowFrame = [videoWindow frame];
        NSRect viewRect = [o_video_view convertRect:[o_video_view bounds] toView: nil];
        NSRect contentRect = [videoWindow contentRectForFrameRect:videoWindowFrame];
        float marginy = viewRect.origin.y + videoWindowFrame.size.height - contentRect.size.height;
        float marginx = contentRect.size.width - viewRect.size.width;
        if (b_dark_interface)// && b_video_deco)
            marginy += [o_titlebar_view frame].size.height;

        proposedFrameSize.height = (proposedFrameSize.width - marginx) * nativeVideoSize.height / nativeVideoSize.width + marginy;
    }

    return proposedFrameSize;
}

#pragma mark -
#pragma mark Update interface and respond to foreign events
- (void)showDropZone
{
    b_dropzone_active = YES;
    [o_right_split_view addSubview: o_dropzone_view positioned:NSWindowAbove relativeTo:o_playlist_table];
    [o_dropzone_view setFrame: [o_playlist_table frame]];
    [[o_playlist_table animator] setHidden:YES];
}

- (void)hideDropZone
{
    b_dropzone_active = NO;
    [o_dropzone_view removeFromSuperview];
    [[o_playlist_table animator] setHidden: NO];
}

- (void)hideSplitView
{
    NSRect winrect = [self frame];
    i_lastSplitViewHeight = [o_split_view frame].size.height;
    winrect.size.height = winrect.size.height - i_lastSplitViewHeight;
    winrect.origin.y = winrect.origin.y + i_lastSplitViewHeight;
    [self setFrame: winrect display: YES animate: YES];
    [self performSelector:@selector(hideDropZone) withObject:nil afterDelay:0.1];
    if (b_dark_interface) {
        [self setContentMinSize: NSMakeSize(604., [[o_controls_bar bottomBarView] frame].size.height + [o_titlebar_view frame].size.height)];
        [self setContentMaxSize: NSMakeSize(FLT_MAX, [[o_controls_bar bottomBarView] frame].size.height + [o_titlebar_view frame].size.height)];
    } else {
        [self setContentMinSize: NSMakeSize(604., [[o_controls_bar bottomBarView] frame].size.height)];
        [self setContentMaxSize: NSMakeSize(FLT_MAX, [[o_controls_bar bottomBarView] frame].size.height)];
    }

    b_splitview_removed = YES;
}

- (void)showSplitView
{
    [self updateWindow];
    if (b_dark_interface)
        [self setContentMinSize:NSMakeSize(604., 288. + [o_titlebar_view frame].size.height)];
    else
        [self setContentMinSize:NSMakeSize(604., 288.)];
    [self setContentMaxSize: NSMakeSize(FLT_MAX, FLT_MAX)];

    NSRect winrect;
    winrect = [self frame];
    winrect.size.height = winrect.size.height + i_lastSplitViewHeight;
    winrect.origin.y = winrect.origin.y - i_lastSplitViewHeight;
    [self setFrame: winrect display: YES animate: YES];

    [self performSelector:@selector(resizePlaylistAfterCollapse) withObject: nil afterDelay:0.75];

    b_splitview_removed = NO;
}

- (void)updateTimeSlider
{
    [o_controls_bar updateTimeSlider];
    [[self controlsBar] updatePosAndTimeInFSPanel:o_fspanel];
    if (o_detached_video_window)
        [[o_detached_video_window controlsBar] updateTimeSlider];
}

- (void)updateName
{
    input_thread_t * p_input;
    p_input = pl_CurrentInput(VLCIntf);
    if (p_input) {
        NSString *aString;
        char *format = var_InheritString(VLCIntf, "input-title-format");
        char *formated = str_format_meta(pl_Get(VLCIntf), format);
        free(format);
        aString = [NSString stringWithUTF8String:formated];
        free(formated);

        char *uri = input_item_GetURI(input_GetItem(p_input));

        NSURL * o_url = [NSURL URLWithString: [NSString stringWithUTF8String: uri]];
        if ([o_url isFileURL]) {
            [self setRepresentedURL: o_url];
            if (o_detached_video_window)
                [o_detached_video_window setRepresentedURL: o_url];
        } else {
            [self setRepresentedURL: nil];
            if (o_detached_video_window)
                [o_detached_video_window setRepresentedURL: nil];
        }
        free(uri);

        if ([aString isEqualToString:@""]) {
            if ([o_url isFileURL])
                aString = [[NSFileManager defaultManager] displayNameAtPath: [o_url path]];
            else
                aString = [o_url absoluteString];
        }

        [self setTitle: aString];
        if (b_nonembedded && o_detached_video_window && [[VLCMain sharedInstance] activeVideoPlayback])
            [o_detached_video_window setTitle: aString];

        [o_fspanel setStreamTitle: aString];
        vlc_object_release(p_input);
    } else {
        [self setTitle: _NS("VLC media player")];
        [self setRepresentedURL: nil];
    }
}

- (void)updateWindow
{
    [o_controls_bar updateControls];
    if (o_detached_video_window)
        [[o_detached_video_window controlsBar] updateControls];

    bool b_seekable = false;

    playlist_t * p_playlist = pl_Get(VLCIntf);
    input_thread_t * p_input = playlist_CurrentInput(p_playlist);
    if (p_input) {
        /* seekable streams */
        b_seekable = var_GetBool(p_input, "can-seek");

        vlc_object_release(p_input);
    }

    [self updateTimeSlider];
    [o_fspanel setSeekable: b_seekable];

    PL_LOCK;
    if ([[[VLCMain sharedInstance] playlist] currentPlaylistRoot] != p_playlist->p_local_category || p_playlist->p_local_category->i_children > 0)
        [self hideDropZone];
    else
        [self showDropZone];
    PL_UNLOCK;
    [o_sidebar_view setNeedsDisplay:YES];
}

- (void)setPause
{
    [o_controls_bar setPause];
    if (o_detached_video_window)
        [[o_detached_video_window controlsBar] setPause];
    [o_fspanel setPause];
}

- (void)setPlay
{
    [o_controls_bar setPlay];
    if (o_detached_video_window)
        [[o_detached_video_window controlsBar] setPlay];
    [o_fspanel setPlay];
}

- (void)updateVolumeSlider
{
    [[self controlsBar] updateVolumeSlider];
    [o_fspanel setVolumeLevel: [[VLCCoreInteraction sharedInstance] volume]];
}

#pragma mark -
#pragma mark Video Output handling
- (id)videoView
{
    return o_video_view;
}

- (void)setupVideoView
{
    BOOL b_video_deco = var_InheritBool(VLCIntf, "video-deco");
    BOOL b_video_wallpaper = var_InheritBool(VLCIntf, "video-wallpaper");

    // TODO: make lion fullscreen compatible with video-wallpaper and !embedded-video
    if ((b_video_wallpaper || !b_video_deco) && !b_nativeFullscreenMode) {
        // b_video_wallpaper is priorized over !b_video_deco

        msg_Dbg(VLCIntf, "Creating background / blank window");
        NSScreen *screen = [NSScreen screenWithDisplayID:(CGDirectDisplayID)var_InheritInteger(VLCIntf, "macosx-vdev")];
        if (!screen)
            screen = [self screen];

        NSRect window_rect;
        if (b_video_wallpaper)
            window_rect = [screen frame];
        else
            window_rect = [self frame];

        if (o_extra_video_window)
            [o_extra_video_window release];

        NSUInteger mask = NSBorderlessWindowMask;
        if (!OSX_SNOW_LEOPARD && !b_video_deco)
            mask |= NSResizableWindowMask;

        BOOL b_no_video_deco_only = !b_video_wallpaper;
        o_extra_video_window = [[VLCVideoWindowCommon alloc] initWithContentRect:window_rect styleMask:mask backing:NSBackingStoreBuffered defer:YES];
        [o_extra_video_window setDelegate:self];

        if (b_video_wallpaper)
            [o_extra_video_window setLevel:CGWindowLevelForKey(kCGDesktopWindowLevelKey) + 1];

        [o_extra_video_window setBackgroundColor: [NSColor blackColor]];
        [o_extra_video_window setCanBecomeKeyWindow: !b_video_wallpaper];
        [o_extra_video_window setCanBecomeMainWindow: !b_video_wallpaper];
        [o_extra_video_window setAcceptsMouseMovedEvents:!b_video_wallpaper];
        [o_extra_video_window setMovableByWindowBackground: !b_video_wallpaper];
        [o_extra_video_window useOptimizedDrawing: YES];

        [o_video_view retain];
        if ([o_video_view superview] != NULL)
            [o_video_view removeFromSuperviewWithoutNeedingDisplay];
        window_rect.origin.x = window_rect.origin.y = 0;
        [o_video_view setFrame: window_rect];
        [[o_extra_video_window contentView] addSubview: o_video_view positioned:NSWindowAbove relativeTo:nil];
        [o_video_view release];

        if (b_video_wallpaper)
            [o_extra_video_window orderBack:nil];
        else {
            [o_extra_video_window center];
            [o_extra_video_window setFrameAutosaveName:@"extra-videowindow"];
            [o_extra_video_window setContentMinSize: NSMakeSize(f_min_video_height, f_min_video_height)];
        }

        b_nonembedded = YES;
    } else {
        if (var_InheritBool(VLCIntf, "embedded-video") || b_nativeFullscreenMode) {
            if ([o_video_view window] != self) {
                [o_video_view removeFromSuperviewWithoutNeedingDisplay];
                [o_video_view setFrame: [o_split_view frame]];
                [[self contentView] addSubview:o_video_view positioned:NSWindowAbove relativeTo:nil];
            }
            b_nonembedded = NO;
        } else {
            if ([o_video_view superview] != NULL)
                [o_video_view removeFromSuperviewWithoutNeedingDisplay];

            if (!o_detached_video_window) {
                NSWindowController *o_controller = [[NSWindowController alloc] initWithWindowNibName:@"DetachedVideoWindow"];
                [o_controller loadWindow];
                o_detached_video_window = (VLCDetachedVideoWindow *)[o_controller window];
                [o_controller release];

                // event occurs before window is created, so call again
                [[VLCMain sharedInstance] playbackStatusUpdated];
            }

            [o_detached_video_window setDelegate: self];
            if (b_dark_interface) {
                [o_detached_video_window setContentMinSize: NSMakeSize(363., f_min_video_height + [[[o_detached_video_window controlsBar] bottomBarView] frame].size.height + [o_titlebar_view frame].size.height)];
            } else {
                [o_detached_video_window setContentMinSize: NSMakeSize(363., f_min_video_height + [[[o_detached_video_window controlsBar] bottomBarView] frame].size.height)];
            }

            NSRect videoFrame;
            videoFrame.size = [[o_detached_video_window contentView] frame].size;
            videoFrame.size.height -= [[[o_detached_video_window controlsBar] bottomBarView] frame].size.height;
            if (b_dark_interface)
                videoFrame.size.height -= [o_titlebar_view frame].size.height;

            videoFrame.origin.x = .0;
            videoFrame.origin.y = [[[o_detached_video_window controlsBar] bottomBarView] frame].size.height;

            [o_video_view setFrame: videoFrame];
            [[o_detached_video_window contentView] addSubview: o_video_view positioned:NSWindowAbove relativeTo:nil];
            [o_detached_video_window setLevel:NSNormalWindowLevel];
            [o_detached_video_window useOptimizedDrawing: YES];

            b_nonembedded = YES;
        }
    }

    if (!b_video_wallpaper) {
        [[o_video_view window] makeKeyAndOrderFront: self];

        vout_thread_t *p_vout = getVout();
        if (p_vout) {
            if (var_GetBool(p_vout, "video-on-top"))
                [[o_video_view window] setLevel: NSStatusWindowLevel];
            else
                [[o_video_view window] setLevel: NSNormalWindowLevel];
            vlc_object_release(p_vout);
        }
    }

    [[o_video_view window] setAlphaValue: config_GetFloat(VLCIntf, "macosx-opaqueness")];
}

- (void)setVideoplayEnabled
{
    BOOL b_videoPlayback = [[VLCMain sharedInstance] activeVideoPlayback];

    if (b_videoPlayback) {
        frameBeforePlayback = [self frame];

        // look for 'start at fullscreen'
        [[VLCMain sharedInstance] fullscreenChanged];
    } else {
        if (!b_nonembedded)
            [[self animator] setFrame:frameBeforePlayback display:YES];

        [self makeFirstResponder: nil];
        if (o_detached_video_window)
            [o_detached_video_window orderOut: nil];
        if (o_extra_video_window)
            [o_extra_video_window orderOut: nil];

        if ([self level] != NSNormalWindowLevel)
            [self setLevel: NSNormalWindowLevel];
        if (o_detached_video_window && [o_detached_video_window level] != NSNormalWindowLevel)
            [o_detached_video_window setLevel: NSNormalWindowLevel];

        // restore alpha value to 1 for the case that macosx-opaqueness is set to < 1
        [self setAlphaValue:1.0];
    }

    if (b_nativeFullscreenMode) {
        if ([NSApp presentationOptions] & NSApplicationPresentationFullScreen)
            [[o_controls_bar bottomBarView] setHidden: b_videoPlayback];
        else
            [[o_controls_bar bottomBarView] setHidden: NO];
        if (b_videoPlayback && b_fullscreen)
            [o_fspanel setActive: nil];
        if (!b_videoPlayback)
            [o_fspanel setNonActive: nil];
    }

    if (!b_videoPlayback && b_fullscreen) {
        if (!b_nativeFullscreenMode)
            [[VLCCoreInteraction sharedInstance] toggleFullscreen];
    }
}

- (void)resizeWindow
{
    if (b_fullscreen || (b_nativeFullscreenMode && [NSApp presentationOptions] & NSApplicationPresentationFullScreen))
        return;

    id o_videoWindow = [o_video_view window];
    NSSize windowMinSize = [o_videoWindow minSize];
    NSRect screenFrame = [[o_videoWindow screen] visibleFrame];

    NSPoint topleftbase = NSMakePoint(0, [o_videoWindow frame].size.height);
    NSPoint topleftscreen = [o_videoWindow convertBaseToScreen: topleftbase];

    unsigned int i_width = nativeVideoSize.width;
    unsigned int i_height = nativeVideoSize.height;
    if (i_width < windowMinSize.width)
        i_width = windowMinSize.width;
    if (i_height < f_min_video_height)
        i_height = f_min_video_height;

    /* Calculate the window's new size */
    NSRect new_frame;
    new_frame.size.width = [o_videoWindow frame].size.width - [o_video_view frame].size.width + i_width;
    new_frame.size.height = [o_videoWindow frame].size.height - [o_video_view frame].size.height + i_height;
    new_frame.origin.x = topleftscreen.x;
    new_frame.origin.y = topleftscreen.y - new_frame.size.height;

    /* make sure the window doesn't exceed the screen size the window is on */
    if (new_frame.size.width > screenFrame.size.width) {
        new_frame.size.width = screenFrame.size.width;
        new_frame.origin.x = screenFrame.origin.x;
    }
    if (new_frame.size.height > screenFrame.size.height) {
        new_frame.size.height = screenFrame.size.height;
        new_frame.origin.y = screenFrame.origin.y;
    }
    if (new_frame.origin.y < screenFrame.origin.y)
        new_frame.origin.y = screenFrame.origin.y;

    CGFloat right_screen_point = screenFrame.origin.x + screenFrame.size.width;
    CGFloat right_window_point = new_frame.origin.x + new_frame.size.width;
    if (right_window_point > right_screen_point)
        new_frame.origin.x -= (right_window_point - right_screen_point);

    [[o_videoWindow animator] setFrame:new_frame display:YES];
}

- (void)setNativeVideoSize:(NSSize)size
{
    nativeVideoSize = size;

    if (var_InheritBool(VLCIntf, "macosx-video-autoresize") && !b_fullscreen && !var_InheritBool(VLCIntf, "video-wallpaper"))
        [self performSelectorOnMainThread:@selector(resizeWindow) withObject:nil waitUntilDone:NO];
}

//  Called automatically if window's acceptsMouseMovedEvents property is true
- (void)mouseMoved:(NSEvent *)theEvent
{
    if (b_fullscreen)
        [self recreateHideMouseTimer];

    [super mouseMoved: theEvent];
}

- (void)recreateHideMouseTimer
{
    if (t_hide_mouse_timer != nil) {
        [t_hide_mouse_timer invalidate];
        [t_hide_mouse_timer release];
    }

    t_hide_mouse_timer = [NSTimer scheduledTimerWithTimeInterval:2
                                                          target:self
                                                        selector:@selector(hideMouseCursor:)
                                                        userInfo:nil
                                                         repeats:NO];
    [t_hide_mouse_timer retain];
}

//  NSTimer selectors require this function signature as per Apple's docs
- (void)hideMouseCursor:(NSTimer *)timer
{
    [NSCursor setHiddenUntilMouseMoves: YES];
}

#pragma mark -
#pragma mark Fullscreen support
- (void)showFullscreenController
{
     if (b_fullscreen && [[VLCMain sharedInstance] activeVideoPlayback])
        [o_fspanel fadeIn];
}

- (BOOL)fullscreen
{
    return b_fullscreen;
}

- (void)lockFullscreenAnimation
{
    [o_animation_lock lock];
}

- (void)unlockFullscreenAnimation
{
    [o_animation_lock unlock];
}

- (void)enterFullscreen
{
    NSMutableDictionary *dict1, *dict2;
    NSScreen *screen;
    NSRect screen_rect;
    NSRect rect;
    BOOL blackout_other_displays = var_InheritBool(VLCIntf, "macosx-black");
    o_current_video_window = [o_video_view window];

    screen = [NSScreen screenWithDisplayID:(CGDirectDisplayID)var_InheritInteger(VLCIntf, "macosx-vdev")];
    [self lockFullscreenAnimation];

    if (!screen) {
        msg_Dbg(VLCIntf, "chosen screen isn't present, using current screen for fullscreen mode");
        screen = [o_current_video_window screen];
    }
    if (!screen) {
        msg_Dbg(VLCIntf, "Using deepest screen");
        screen = [NSScreen deepestScreen];
    }

    screen_rect = [screen frame];

    [o_controls_bar setFullscreenState:YES];
    if (o_detached_video_window)
        [[o_detached_video_window controlsBar] setFullscreenState:YES];

    [self recreateHideMouseTimer];

    if (blackout_other_displays)
        [screen blackoutOtherScreens];

    /* Make sure we don't see the window flashes in float-on-top mode */
    i_originalLevel = [o_current_video_window level];
    [o_current_video_window setLevel:NSNormalWindowLevel];

    /* Only create the o_fullscreen_window if we are not in the middle of the zooming animation */
    if (!o_fullscreen_window) {
        /* We can't change the styleMask of an already created NSWindow, so we create another window, and do eye catching stuff */

        rect = [[o_video_view superview] convertRect: [o_video_view frame] toView: nil]; /* Convert to Window base coord */
        rect.origin.x += [o_current_video_window frame].origin.x;
        rect.origin.y += [o_current_video_window frame].origin.y;
        o_fullscreen_window = [[VLCWindow alloc] initWithContentRect:rect styleMask: NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:YES];
        [o_fullscreen_window setBackgroundColor: [NSColor blackColor]];
        [o_fullscreen_window setCanBecomeKeyWindow: YES];
        [o_fullscreen_window setCanBecomeMainWindow: YES];

        if (![o_current_video_window isVisible] || [o_current_video_window alphaValue] == 0.0) {
            /* We don't animate if we are not visible, instead we
             * simply fade the display */
            CGDisplayFadeReservationToken token;

            if (blackout_other_displays) {
                CGAcquireDisplayFadeReservation(kCGMaxDisplayReservationInterval, &token);
                CGDisplayFade(token, 0.5, kCGDisplayBlendNormal, kCGDisplayBlendSolidColor, 0, 0, 0, YES);
            }

            if ([screen mainScreen])
                [NSApp setPresentationOptions:(NSApplicationPresentationAutoHideDock | NSApplicationPresentationAutoHideMenuBar)];

            [[o_video_view superview] replaceSubview:o_video_view with:o_temp_view];
            [o_temp_view setFrame:[o_video_view frame]];
            [o_fullscreen_window setContentView:o_video_view];

            [o_fullscreen_window makeKeyAndOrderFront:self];
            [o_fullscreen_window orderFront:self animate:YES];

            [o_fullscreen_window setFrame:screen_rect display:YES animate:YES];
            [o_fullscreen_window setLevel:NSNormalWindowLevel];

            if (blackout_other_displays) {
                CGDisplayFade(token, 0.3, kCGDisplayBlendSolidColor, kCGDisplayBlendNormal, 0, 0, 0, NO);
                CGReleaseDisplayFadeReservation(token);
            }

            /* Will release the lock */
            [self hasBecomeFullscreen];

            return;
        }

        /* Make sure we don't see the o_video_view disappearing of the screen during this operation */
        NSDisableScreenUpdates();
        [[o_video_view superview] replaceSubview:o_video_view with:o_temp_view];
        [o_temp_view setFrame:[o_video_view frame]];
        [o_fullscreen_window setContentView:o_video_view];
        [o_fullscreen_window makeKeyAndOrderFront:self];
        NSEnableScreenUpdates();
    }

    /* We are in fullscreen (and no animation is running) */
    if (b_fullscreen) {
        /* Make sure we are hidden */
        [o_current_video_window orderOut: self];

        [self unlockFullscreenAnimation];
        return;
    }

    if (o_fullscreen_anim1) {
        [o_fullscreen_anim1 stopAnimation];
        [o_fullscreen_anim1 release];
    }
    if (o_fullscreen_anim2) {
        [o_fullscreen_anim2 stopAnimation];
        [o_fullscreen_anim2 release];
    }

    if ([screen mainScreen])
        [NSApp setPresentationOptions:(NSApplicationPresentationAutoHideDock | NSApplicationPresentationAutoHideMenuBar)];

    dict1 = [[NSMutableDictionary alloc] initWithCapacity:2];
    dict2 = [[NSMutableDictionary alloc] initWithCapacity:3];

    [dict1 setObject:o_current_video_window forKey:NSViewAnimationTargetKey];
    [dict1 setObject:NSViewAnimationFadeOutEffect forKey:NSViewAnimationEffectKey];

    [dict2 setObject:o_fullscreen_window forKey:NSViewAnimationTargetKey];
    [dict2 setObject:[NSValue valueWithRect:[o_fullscreen_window frame]] forKey:NSViewAnimationStartFrameKey];
    [dict2 setObject:[NSValue valueWithRect:screen_rect] forKey:NSViewAnimationEndFrameKey];

    /* Strategy with NSAnimation allocation:
     - Keep at most 2 animation at a time
     - leaveFullscreen/enterFullscreen are the only responsible for releasing and alloc-ing
     */
    o_fullscreen_anim1 = [[NSViewAnimation alloc] initWithViewAnimations:[NSArray arrayWithObject:dict1]];
    o_fullscreen_anim2 = [[NSViewAnimation alloc] initWithViewAnimations:[NSArray arrayWithObject:dict2]];

    [dict1 release];
    [dict2 release];

    [o_fullscreen_anim1 setAnimationBlockingMode: NSAnimationNonblocking];
    [o_fullscreen_anim1 setDuration: 0.3];
    [o_fullscreen_anim1 setFrameRate: 30];
    [o_fullscreen_anim2 setAnimationBlockingMode: NSAnimationNonblocking];
    [o_fullscreen_anim2 setDuration: 0.2];
    [o_fullscreen_anim2 setFrameRate: 30];

    [o_fullscreen_anim2 setDelegate: self];
    [o_fullscreen_anim2 startWhenAnimation: o_fullscreen_anim1 reachesProgress: 1.0];

    [o_fullscreen_anim1 startAnimation];
    /* fullscreenAnimation will be unlocked when animation ends */
}

- (void)hasBecomeFullscreen
{
    if ([[o_video_view subviews] count] > 0)
        [o_fullscreen_window makeFirstResponder: [[o_video_view subviews] objectAtIndex:0]];

    [o_fullscreen_window makeKeyWindow];
    [o_fullscreen_window setAcceptsMouseMovedEvents: YES];

    /* tell the fspanel to move itself to front next time it's triggered */
    [o_fspanel setVoutWasUpdated: (int)[[o_fullscreen_window screen] displayID]];
    [o_fspanel setActive: nil];

    if ([o_current_video_window isVisible])
        [o_current_video_window orderOut: self];

    b_fullscreen = YES;
    [self unlockFullscreenAnimation];
}

- (void)leaveFullscreen
{
    [self leaveFullscreenAndFadeOut: NO];
}

- (void)leaveFullscreenAndFadeOut: (BOOL)fadeout
{
    NSMutableDictionary *dict1, *dict2;
    NSRect frame;
    BOOL blackout_other_displays = var_InheritBool(VLCIntf, "macosx-black");

    if (!o_current_video_window)
        return;

    [self lockFullscreenAnimation];

    [o_controls_bar setFullscreenState:NO];
    if (o_detached_video_window)
        [[o_detached_video_window controlsBar] setFullscreenState:NO];

    /* We always try to do so */
    [NSScreen unblackoutScreens];

    vout_thread_t *p_vout = getVout();
    if (p_vout) {
        if (var_GetBool(p_vout, "video-on-top"))
            [[o_video_view window] setLevel: NSStatusWindowLevel];
        else
            [[o_video_view window] setLevel: NSNormalWindowLevel];
        vlc_object_release(p_vout);
    }
    [[o_video_view window] makeKeyAndOrderFront: nil];

    /* Don't do anything if o_fullscreen_window is already closed */
    if (!o_fullscreen_window) {
        [self unlockFullscreenAnimation];
        return;
    }

    if (fadeout) {
        /* We don't animate if we are not visible, instead we
         * simply fade the display */
        CGDisplayFadeReservationToken token;

        if (blackout_other_displays) {
            CGAcquireDisplayFadeReservation(kCGMaxDisplayReservationInterval, &token);
            CGDisplayFade(token, 0.3, kCGDisplayBlendNormal, kCGDisplayBlendSolidColor, 0, 0, 0, YES);
        }

        [o_fspanel setNonActive: nil];
        [NSApp setPresentationOptions: NSApplicationPresentationDefault];

        /* Will release the lock */
        [self hasEndedFullscreen];

        /* Our window is hidden, and might be faded. We need to workaround that, so note it
         * here */
        b_window_is_invisible = YES;

        if (blackout_other_displays) {
            CGDisplayFade(token, 0.5, kCGDisplayBlendSolidColor, kCGDisplayBlendNormal, 0, 0, 0, NO);
            CGReleaseDisplayFadeReservation(token);
        }

        return;
    }

    [o_current_video_window setAlphaValue: 0.0];
    [o_current_video_window orderFront: self];
    [[o_video_view window] orderFront: self];

    [o_fspanel setNonActive: nil];
    [NSApp setPresentationOptions:(NSApplicationPresentationDefault)];

    if (o_fullscreen_anim1) {
        [o_fullscreen_anim1 stopAnimation];
        [o_fullscreen_anim1 release];
    }
    if (o_fullscreen_anim2) {
        [o_fullscreen_anim2 stopAnimation];
        [o_fullscreen_anim2 release];
    }

    frame = [[o_temp_view superview] convertRect: [o_temp_view frame] toView: nil]; /* Convert to Window base coord */
    frame.origin.x += [o_current_video_window frame].origin.x;
    frame.origin.y += [o_current_video_window frame].origin.y;

    dict2 = [[NSMutableDictionary alloc] initWithCapacity:2];
    [dict2 setObject:o_current_video_window forKey:NSViewAnimationTargetKey];
    [dict2 setObject:NSViewAnimationFadeInEffect forKey:NSViewAnimationEffectKey];

    o_fullscreen_anim2 = [[NSViewAnimation alloc] initWithViewAnimations:[NSArray arrayWithObjects:dict2, nil]];
    [dict2 release];

    [o_fullscreen_anim2 setAnimationBlockingMode: NSAnimationNonblocking];
    [o_fullscreen_anim2 setDuration: 0.3];
    [o_fullscreen_anim2 setFrameRate: 30];

    [o_fullscreen_anim2 setDelegate: self];

    dict1 = [[NSMutableDictionary alloc] initWithCapacity:3];

    [dict1 setObject:o_fullscreen_window forKey:NSViewAnimationTargetKey];
    [dict1 setObject:[NSValue valueWithRect:[o_fullscreen_window frame]] forKey:NSViewAnimationStartFrameKey];
    [dict1 setObject:[NSValue valueWithRect:frame] forKey:NSViewAnimationEndFrameKey];

    o_fullscreen_anim1 = [[NSViewAnimation alloc] initWithViewAnimations:[NSArray arrayWithObjects:dict1, nil]];
    [dict1 release];

    [o_fullscreen_anim1 setAnimationBlockingMode: NSAnimationNonblocking];
    [o_fullscreen_anim1 setDuration: 0.2];
    [o_fullscreen_anim1 setFrameRate: 30];
    [o_fullscreen_anim2 startWhenAnimation: o_fullscreen_anim1 reachesProgress: 1.0];

    /* Make sure o_fullscreen_window is the frontmost window */
    [o_fullscreen_window orderFront: self];

    [o_fullscreen_anim1 startAnimation];
    /* fullscreenAnimation will be unlocked when animation ends */
}

- (void)hasEndedFullscreen
{
    b_fullscreen = NO;

    /* This function is private and should be only triggered at the end of the fullscreen change animation */
    /* Make sure we don't see the o_video_view disappearing of the screen during this operation */
    NSDisableScreenUpdates();
    [o_video_view retain];
    [o_video_view removeFromSuperviewWithoutNeedingDisplay];
    [[o_temp_view superview] replaceSubview:o_temp_view with:o_video_view];
    [o_video_view release];
    [o_video_view setFrame:[o_temp_view frame]];
    if ([[o_video_view subviews] count] > 0)
        [[o_video_view window] makeFirstResponder: [[o_video_view subviews] objectAtIndex:0]];
    if (!b_nonembedded)
            [super makeKeyAndOrderFront:self]; /* our version contains a workaround */
    else
        [[o_video_view window] makeKeyAndOrderFront: self];
    [o_fullscreen_window orderOut: self];
    NSEnableScreenUpdates();

    [o_fullscreen_window release];
    o_fullscreen_window = nil;
    [[o_video_view window] setLevel:i_originalLevel];
    [[o_video_view window] setAlphaValue: config_GetFloat(VLCIntf, "macosx-opaqueness")];

    // if we quit fullscreen because there is no video anymore, make sure non-embedded window is not visible
    if (![[VLCMain sharedInstance] activeVideoPlayback] && b_nonembedded)
        [o_current_video_window orderOut: self];

    o_current_video_window = nil;
    [self unlockFullscreenAnimation];
}

- (void)animationDidEnd:(NSAnimation*)animation
{
    NSArray *viewAnimations;
    if (o_makekey_anim == animation) {
        [o_makekey_anim release];
        return;
    }
    if ([animation currentValue] < 1.0)
        return;

    /* Fullscreen ended or started (we are a delegate only for leaveFullscreen's/enterFullscren's anim2) */
    viewAnimations = [o_fullscreen_anim2 viewAnimations];
    if ([viewAnimations count] >=1 &&
        [[[viewAnimations objectAtIndex: 0] objectForKey: NSViewAnimationEffectKey] isEqualToString:NSViewAnimationFadeInEffect]) {
        /* Fullscreen ended */
        [self hasEndedFullscreen];
    } else
        /* Fullscreen started */
        [self hasBecomeFullscreen];
}

- (void)makeKeyAndOrderFront: (id)sender
{
    /* Hack
     * when we exit fullscreen and fade out, we may endup in
     * having a window that is faded. We can't have it fade in unless we
     * animate again. */

    if (!b_window_is_invisible) {
        /* Make sure we don't do it too much */
        [super makeKeyAndOrderFront: sender];
        return;
    }

    [super setAlphaValue:0.0f];
    [super makeKeyAndOrderFront: sender];

    NSMutableDictionary * dict = [[NSMutableDictionary alloc] initWithCapacity:2];
    [dict setObject:self forKey:NSViewAnimationTargetKey];
    [dict setObject:NSViewAnimationFadeInEffect forKey:NSViewAnimationEffectKey];

    o_makekey_anim = [[NSViewAnimation alloc] initWithViewAnimations:[NSArray arrayWithObject:dict]];
    [dict release];

    [o_makekey_anim setAnimationBlockingMode: NSAnimationNonblocking];
    [o_makekey_anim setDuration: 0.1];
    [o_makekey_anim setFrameRate: 30];
    [o_makekey_anim setDelegate: self];

    [o_makekey_anim startAnimation];
    b_window_is_invisible = NO;

    /* fullscreenAnimation will be unlocked when animation ends */
}

#pragma mark -
#pragma mark Lion native fullscreen handling
- (void)windowWillEnterFullScreen:(NSNotification *)notification
{
    // workaround, see #6668
    [NSApp setPresentationOptions:(NSApplicationPresentationFullScreen | NSApplicationPresentationAutoHideDock | NSApplicationPresentationAutoHideMenuBar)];

    var_SetBool(pl_Get(VLCIntf), "fullscreen", true);

    vout_thread_t *p_vout = getVout();
    if (p_vout) {
        var_SetBool(p_vout, "fullscreen", true);
        vlc_object_release(p_vout);
    }

    [o_video_view setFrame: [[self contentView] frame]];
    b_fullscreen = YES;

    [self recreateHideMouseTimer];
    i_originalLevel = [self level];
    [self setLevel:NSNormalWindowLevel];

    if (b_dark_interface) {
        [o_titlebar_view removeFromSuperviewWithoutNeedingDisplay];

        NSRect winrect;
        CGFloat f_titleBarHeight = [o_titlebar_view frame].size.height;
        winrect = [self frame];

        winrect.size.height = winrect.size.height - f_titleBarHeight;
        [self setFrame: winrect display:NO animate:NO];
        winrect = [o_split_view frame];
        winrect.size.height = winrect.size.height + f_titleBarHeight;
        [o_split_view setFrame: winrect];
    }

    if ([[VLCMain sharedInstance] activeVideoPlayback])
        [[o_controls_bar bottomBarView] setHidden: YES];

    [self setMovableByWindowBackground: NO];
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification
{
    // Indeed, we somehow can have an "inactive" fullscreen (but a visible window!).
    // But this creates some problems when leaving fs over remote intfs, so activate app here.
    [NSApp activateIgnoringOtherApps:YES];

    [o_fspanel setVoutWasUpdated: (int)[[self screen] displayID]];
    [o_fspanel setActive: nil];
}

- (void)windowWillExitFullScreen:(NSNotification *)notification
{

    var_SetBool(pl_Get(VLCIntf), "fullscreen", false);

    vout_thread_t *p_vout = getVout();
    if (p_vout) {
        var_SetBool(p_vout, "fullscreen", false);
        vlc_object_release(p_vout);
    }

    [o_video_view setFrame: [o_split_view frame]];
    [NSCursor setHiddenUntilMouseMoves: NO];
    [o_fspanel setNonActive: nil];
    [self setLevel:i_originalLevel];
    b_fullscreen = NO;

    if (b_dark_interface) {
        NSRect winrect;
        CGFloat f_titleBarHeight = [o_titlebar_view frame].size.height;
        winrect = [self frame];

        [o_titlebar_view setFrame: NSMakeRect(0, winrect.size.height - f_titleBarHeight,
                                              winrect.size.width, f_titleBarHeight)];
        [[self contentView] addSubview: o_titlebar_view];

        winrect.size.height = winrect.size.height + f_titleBarHeight;
        [self setFrame: winrect display:NO animate:NO];
        winrect = [o_split_view frame];
        winrect.size.height = winrect.size.height - f_titleBarHeight;
        [o_split_view setFrame: winrect];
        [o_video_view setFrame: winrect];
    }

    if ([[VLCMain sharedInstance] activeVideoPlayback])
        [[o_controls_bar bottomBarView] setHidden: NO];

    [self setMovableByWindowBackground: YES];
}

#pragma mark -
#pragma mark split view delegate
- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)dividerIndex
{
    if (dividerIndex == 0)
        return 300.;
    else
        return proposedMax;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)dividerIndex
{
    if (dividerIndex == 0)
        return 100.;
    else
        return proposedMin;
}

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview
{
    return ([subview isEqual:o_left_split_view]);
}

- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)subview
{
    if ([subview isEqual:o_left_split_view])
        return NO;
    return YES;
}

#pragma mark -
#pragma mark Side Bar Data handling
/* taken under BSD-new from the PXSourceList sample project, adapted for VLC */
- (NSUInteger)sourceList:(PXSourceList*)sourceList numberOfChildrenOfItem:(id)item
{
    //Works the same way as the NSOutlineView data source: `nil` means a parent item
    if (item==nil)
        return [o_sidebaritems count];
    else
        return [[item children] count];
}


- (id)sourceList:(PXSourceList*)aSourceList child:(NSUInteger)index ofItem:(id)item
{
    //Works the same way as the NSOutlineView data source: `nil` means a parent item
    if (item==nil)
        return [o_sidebaritems objectAtIndex:index];
    else
        return [[item children] objectAtIndex:index];
}


- (id)sourceList:(PXSourceList*)aSourceList objectValueForItem:(id)item
{
    return [item title];
}

- (void)sourceList:(PXSourceList*)aSourceList setObjectValue:(id)object forItem:(id)item
{
    [item setTitle:object];
}

- (BOOL)sourceList:(PXSourceList*)aSourceList isItemExpandable:(id)item
{
    return [item hasChildren];
}


- (BOOL)sourceList:(PXSourceList*)aSourceList itemHasBadge:(id)item
{
    if ([[item identifier] isEqualToString: @"playlist"] || [[item identifier] isEqualToString: @"medialibrary"])
        return YES;

    return [item hasBadge];
}


- (NSInteger)sourceList:(PXSourceList*)aSourceList badgeValueForItem:(id)item
{
    playlist_t * p_playlist = pl_Get(VLCIntf);
    NSInteger i_playlist_size;

    if ([[item identifier] isEqualToString: @"playlist"]) {
        PL_LOCK;
        i_playlist_size = p_playlist->p_local_category->i_children;
        PL_UNLOCK;

        return i_playlist_size;
    }
    if ([[item identifier] isEqualToString: @"medialibrary"]) {
        PL_LOCK;
        i_playlist_size = p_playlist->p_ml_category->i_children;
        PL_UNLOCK;

        return i_playlist_size;
    }

    return [item badgeValue];
}


- (BOOL)sourceList:(PXSourceList*)aSourceList itemHasIcon:(id)item
{
    return [item hasIcon];
}


- (NSImage*)sourceList:(PXSourceList*)aSourceList iconForItem:(id)item
{
    return [item icon];
}

- (NSMenu*)sourceList:(PXSourceList*)aSourceList menuForEvent:(NSEvent*)theEvent item:(id)item
{
    if ([theEvent type] == NSRightMouseDown || ([theEvent type] == NSLeftMouseDown && ([theEvent modifierFlags] & NSControlKeyMask) == NSControlKeyMask)) {
        if (item != nil) {
            NSMenu * m;
            if ([item sdtype] > 0)
            {
                m = [[NSMenu alloc] init];
                playlist_t * p_playlist = pl_Get(VLCIntf);
                BOOL sd_loaded = playlist_IsServicesDiscoveryLoaded(p_playlist, [[item identifier] UTF8String]);
                if (!sd_loaded)
                    [m addItemWithTitle:_NS("Enable") action:@selector(sdmenuhandler:) keyEquivalent:@""];
                else
                    [m addItemWithTitle:_NS("Disable") action:@selector(sdmenuhandler:) keyEquivalent:@""];
                [[m itemAtIndex:0] setRepresentedObject: [item identifier]];
            }
            return [m autorelease];
        }
    }

    return nil;
}

- (IBAction)sdmenuhandler:(id)sender
{
    NSString * identifier = [sender representedObject];
    if ([identifier length] > 0 && ![identifier isEqualToString:@"lua{sd='freebox',longname='Freebox TV'}"]) {
        playlist_t * p_playlist = pl_Get(VLCIntf);
        BOOL sd_loaded = playlist_IsServicesDiscoveryLoaded(p_playlist, [identifier UTF8String]);

        if (!sd_loaded)
            playlist_ServicesDiscoveryAdd(p_playlist, [identifier UTF8String]);
        else
            playlist_ServicesDiscoveryRemove(p_playlist, [identifier UTF8String]);
    }
}

#pragma mark -
#pragma mark Side Bar Delegate Methods
/* taken under BSD-new from the PXSourceList sample project, adapted for VLC */
- (BOOL)sourceList:(PXSourceList*)aSourceList isGroupAlwaysExpanded:(id)group
{
    if ([[group identifier] isEqualToString:@"library"])
        return YES;

    return NO;
}

- (void)sourceListSelectionDidChange:(NSNotification *)notification
{
    playlist_t * p_playlist = pl_Get(VLCIntf);

    NSIndexSet *selectedIndexes = [o_sidebar_view selectedRowIndexes];
    id item = [o_sidebar_view itemAtRow:[selectedIndexes firstIndex]];


    //Set the label text to represent the new selection
    if ([item sdtype] > -1 && [[item identifier] length] > 0) {
        BOOL sd_loaded = playlist_IsServicesDiscoveryLoaded(p_playlist, [[item identifier] UTF8String]);
        if (!sd_loaded)
            playlist_ServicesDiscoveryAdd(p_playlist, [[item identifier] UTF8String]);
    }

    [o_chosen_category_lbl setStringValue:[item title]];

    if ([[item identifier] isEqualToString:@"playlist"]) {
        [[[VLCMain sharedInstance] playlist] setPlaylistRoot:p_playlist->p_local_category];
    } else if ([[item identifier] isEqualToString:@"medialibrary"]) {
        [[[VLCMain sharedInstance] playlist] setPlaylistRoot:p_playlist->p_ml_category];
    } else {
        playlist_item_t * pl_item;
        PL_LOCK;
        pl_item = playlist_ChildSearchName(p_playlist->p_root, [[item untranslatedTitle] UTF8String]);
        PL_UNLOCK;
        [[[VLCMain sharedInstance] playlist] setPlaylistRoot: pl_item];
    }

    PL_LOCK;
    if ([[[VLCMain sharedInstance] playlist] currentPlaylistRoot] != p_playlist->p_local_category || p_playlist->p_local_category->i_children > 0)
        [self hideDropZone];
    else
        [self showDropZone];
    PL_UNLOCK;

    if ([[item identifier] isEqualToString:@"podcast{longname=\"Podcasts\"}"])
        [self showPodcastControls];
    else
        [self hidePodcastControls];
}

- (NSDragOperation)sourceList:(PXSourceList *)aSourceList validateDrop:(id <NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)index
{
    if ([[item identifier] isEqualToString:@"playlist"] || [[item identifier] isEqualToString:@"medialibrary"]) {
        NSPasteboard *o_pasteboard = [info draggingPasteboard];
        if ([[o_pasteboard types] containsObject: @"VLCPlaylistItemPboardType"] || [[o_pasteboard types] containsObject: NSFilenamesPboardType])
            return NSDragOperationGeneric;
    }
    return NSDragOperationNone;
}

- (BOOL)sourceList:(PXSourceList *)aSourceList acceptDrop:(id <NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)index
{
    NSPasteboard *o_pasteboard = [info draggingPasteboard];

    playlist_t * p_playlist = pl_Get(VLCIntf);
    playlist_item_t *p_node;

    if ([[item identifier] isEqualToString:@"playlist"])
        p_node = p_playlist->p_local_category;
    else
        p_node = p_playlist->p_ml_category;

    if ([[o_pasteboard types] containsObject: NSFilenamesPboardType]) {
        NSArray *o_values = [[o_pasteboard propertyListForType: NSFilenamesPboardType] sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)];
        NSUInteger count = [o_values count];
        NSMutableArray *o_array = [NSMutableArray arrayWithCapacity:count];

        for(NSUInteger i = 0; i < count; i++) {
            NSDictionary *o_dic;
            char *psz_uri = vlc_path2uri([[o_values objectAtIndex:i] UTF8String], NULL);
            if (!psz_uri)
                continue;

            o_dic = [NSDictionary dictionaryWithObject:[NSString stringWithCString:psz_uri encoding:NSUTF8StringEncoding] forKey:@"ITEM_URL"];

            free(psz_uri);

            [o_array addObject: o_dic];
        }

        [[[VLCMain sharedInstance] playlist] appendNodeArray:o_array inNode: p_node atPos:-1 enqueue:YES];
        return YES;
    }
    else if ([[o_pasteboard types] containsObject: @"VLCPlaylistItemPboardType"]) {
        NSArray * array = [[[VLCMain sharedInstance] playlist] draggedItems];

        NSUInteger count = [array count];
        playlist_item_t * p_item = NULL;

        PL_LOCK;
        for(NSUInteger i = 0; i < count; i++) {
            p_item = [[array objectAtIndex:i] pointerValue];
            if (!p_item) continue;
            playlist_NodeAddCopy(p_playlist, p_item, p_node, PLAYLIST_END);
        }
        PL_UNLOCK;

        return YES;
    }
    return NO;
}

- (id)sourceList:(PXSourceList *)aSourceList persistentObjectForItem:(id)item
{
    return [item identifier];
}

- (id)sourceList:(PXSourceList *)aSourceList itemForPersistentObject:(id)object
{
    /* the following code assumes for sakes of simplicity that only the top level
     * items are allowed to have children */

    NSArray * array = [NSArray arrayWithArray: o_sidebaritems]; // read-only arrays are noticebly faster
    NSUInteger count = [array count];
    if (count < 1)
        return nil;

    for (NSUInteger x = 0; x < count; x++) {
        id item = [array objectAtIndex: x]; // save one objc selector call
        if ([[item identifier] isEqualToString:object])
            return item;
    }

    return nil;
}

#pragma mark -
#pragma mark Podcast

- (IBAction)addPodcast:(id)sender
{
    [NSApp beginSheet:o_podcast_subscribe_window modalForWindow:self modalDelegate:self didEndSelector:NULL contextInfo:nil];
}

- (IBAction)addPodcastWindowAction:(id)sender
{
    [o_podcast_subscribe_window orderOut:sender];
    [NSApp endSheet: o_podcast_subscribe_window];

    if (sender == o_podcast_subscribe_ok_btn && [[o_podcast_subscribe_url_fld stringValue] length] > 0) {
        NSMutableString * podcastConf = [[NSMutableString alloc] init];
        if (config_GetPsz(VLCIntf, "podcast-urls") != NULL)
            [podcastConf appendFormat:@"%s|", config_GetPsz(VLCIntf, "podcast-urls")];

        [podcastConf appendString: [o_podcast_subscribe_url_fld stringValue]];
        config_PutPsz(VLCIntf, "podcast-urls", [podcastConf UTF8String]);

        vlc_object_t *p_obj = (vlc_object_t*)vlc_object_find_name(VLCIntf->p_libvlc, "podcast");
        if (p_obj) {
            var_SetString(p_obj, "podcast-urls", [podcastConf UTF8String]);
            vlc_object_release(p_obj);
        }
        [podcastConf release];
    }
}

- (IBAction)removePodcast:(id)sender
{
    if (config_GetPsz(VLCIntf, "podcast-urls") != NULL) {
        [o_podcast_unsubscribe_pop removeAllItems];
        [o_podcast_unsubscribe_pop addItemsWithTitles:[[NSString stringWithUTF8String:config_GetPsz(VLCIntf, "podcast-urls")] componentsSeparatedByString:@"|"]];
        [NSApp beginSheet:o_podcast_unsubscribe_window modalForWindow:self modalDelegate:self didEndSelector:NULL contextInfo:nil];
    }
}

- (IBAction)removePodcastWindowAction:(id)sender
{
    [o_podcast_unsubscribe_window orderOut:sender];
    [NSApp endSheet: o_podcast_unsubscribe_window];

    if (sender == o_podcast_unsubscribe_ok_btn) {
        NSMutableArray * urls = [[NSMutableArray alloc] initWithArray:[[NSString stringWithUTF8String:config_GetPsz(VLCIntf, "podcast-urls")] componentsSeparatedByString:@"|"]];
        [urls removeObjectAtIndex: [o_podcast_unsubscribe_pop indexOfSelectedItem]];
        config_PutPsz(VLCIntf, "podcast-urls", [[urls componentsJoinedByString:@"|"] UTF8String]);
        [urls release];

        vlc_object_t *p_obj = (vlc_object_t*)vlc_object_find_name(VLCIntf->p_libvlc, "podcast");
        if (p_obj) {
            var_SetString(p_obj, "podcast-urls", config_GetPsz(VLCIntf, "podcast-urls"));
            vlc_object_release(p_obj);
        }

        /* reload the podcast module, since it won't update its list when removing podcasts */
        playlist_t * p_playlist = pl_Get(VLCIntf);
        if (playlist_IsServicesDiscoveryLoaded(p_playlist, "podcast{longname=\"Podcasts\"}")) {
            playlist_ServicesDiscoveryRemove(p_playlist, "podcast{longname=\"Podcasts\"}");
            playlist_ServicesDiscoveryAdd(p_playlist, "podcast{longname=\"Podcasts\"}");
            [o_playlist_table reloadData];
        }

    }
}

- (void)showPodcastControls
{
    NSRect podcastViewDimensions = [o_podcast_view frame];
    NSRect rightSplitRect = [o_right_split_view frame];
    NSRect playlistTableRect = [o_playlist_table frame];

    podcastViewDimensions.size.width = rightSplitRect.size.width;
    podcastViewDimensions.origin.x = podcastViewDimensions.origin.y = .0;
    [o_podcast_view setFrame:podcastViewDimensions];

    playlistTableRect.origin.y = playlistTableRect.origin.y + podcastViewDimensions.size.height;
    playlistTableRect.size.height = playlistTableRect.size.height - podcastViewDimensions.size.height;
    [o_playlist_table setFrame:playlistTableRect];
    [o_playlist_table setNeedsDisplay:YES];

    [o_right_split_view addSubview: o_podcast_view positioned: NSWindowAbove relativeTo: o_right_split_view];
    b_podcastView_displayed = YES;
}

- (void)hidePodcastControls
{
    if (b_podcastView_displayed) {
        NSRect podcastViewDimensions = [o_podcast_view frame];
        NSRect playlistTableRect = [o_playlist_table frame];

        playlistTableRect.origin.y = playlistTableRect.origin.y - podcastViewDimensions.size.height;
        playlistTableRect.size.height = playlistTableRect.size.height + podcastViewDimensions.size.height;

        [o_podcast_view removeFromSuperviewWithoutNeedingDisplay];
        [o_playlist_table setFrame: playlistTableRect];
        b_podcastView_displayed = NO;
    }
}

@end

@implementation VLCDetachedVideoWindow

- (void)awakeFromNib
{
    [self setAcceptsMouseMovedEvents: YES];

    if (b_dark_interface) {
        [self setBackgroundColor: [NSColor clearColor]];
        [self setOpaque: NO];
        [self display];
        [self setHasShadow:NO];
        [self setHasShadow:YES];

        NSRect winrect = [self frame];
        CGFloat f_titleBarHeight = [o_titlebar_view frame].size.height;

        [self setTitle: _NS("VLC media player")];
        [o_titlebar_view setFrame: NSMakeRect(0, winrect.size.height - f_titleBarHeight, winrect.size.width, f_titleBarHeight)];
        [[self contentView] addSubview: o_titlebar_view positioned: NSWindowAbove relativeTo: nil];

        // native fs not supported with detached view yet
        [o_titlebar_view setFullscreenButtonHidden: YES];

    }
}

@end

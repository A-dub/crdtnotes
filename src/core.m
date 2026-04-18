/**
 * core.m — Framework initialization, Core Data, CRDT, and utility helpers
 */

#import "cider.h"

// ─────────────────────────────────────────────────────────────────────────────
// Global state
// ─────────────────────────────────────────────────────────────────────────────

id g_ctx = nil;
id g_moc = nil;

// ─────────────────────────────────────────────────────────────────────────────
// Framework init
// ─────────────────────────────────────────────────────────────────────────────

BOOL initNotesContext(void) {
    void *handle = dlopen(
        "/System/Library/PrivateFrameworks/NotesShared.framework/NotesShared",
        RTLD_NOW);
    if (!handle) {
        fprintf(stderr, "Error: Could not load NotesShared.framework: %s\n",
                dlerror());
        return NO;
    }

    Class NoteContext = NSClassFromString(@"ICNoteContext");
    if (!NoteContext) {
        fprintf(stderr, "Error: ICNoteContext class not found. "
                "Is this macOS with Apple Notes?\n");
        return NO;
    }

    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(
        NoteContext,
        NSSelectorFromString(@"startSharedContextWithOptions:"),
        0);

    g_ctx = ((id (*)(id, SEL))objc_msgSend)(
        NoteContext, NSSelectorFromString(@"sharedContext"));
    if (!g_ctx) {
        fprintf(stderr, "Error: Could not get shared ICNoteContext\n");
        return NO;
    }

    g_moc = ((id (*)(id, SEL))objc_msgSend)(
        g_ctx, NSSelectorFromString(@"managedObjectContext"));
    if (!g_moc) {
        fprintf(stderr, "Error: Could not get managed object context\n");
        return NO;
    }

    // Set up cross-process change coordinator for CloudKit sync notifications
    @try {
        ((void (*)(id, SEL))objc_msgSend)(
            g_ctx, NSSelectorFromString(@"setupCrossProcessChangeCoordinator"));
    } @catch (NSException *e) {}

    // Verify we can actually read from the store (detect Full Disk Access issues)
    NSFetchRequest *testReq = [NSFetchRequest fetchRequestWithEntityName:@"ICNote"];
    testReq.fetchLimit = 1;
    NSError *testErr = nil;
    NSArray *testResult = [g_moc executeFetchRequest:testReq error:&testErr];
    if (testErr || !testResult) {
        NSString *errDesc = [testErr localizedDescription] ?: @"unknown error";
        if ([errDesc containsString:@"256"] ||
            [errDesc containsString:@"couldn't be opened"] ||
            [errDesc containsString:@"failure to access"]) {
            fprintf(stderr,
                "\n"
                "Error: Cannot access the Notes database.\n"
                "\n"
                "This is usually a macOS permissions issue. To fix it:\n"
                "\n"
                "  1. Open System Settings → Privacy & Security → Full Disk Access\n"
                "  2. Click + and add your terminal app\n"
                "     (Terminal.app, iTerm, Warp, etc.)\n"
                "  3. Restart your terminal\n"
                "\n");
        } else {
            fprintf(stderr, "Error: Failed to read Notes database: %s\n",
                    [errDesc UTF8String]);
        }
        return NO;
    }

    return YES;
}

// ─────────────────────────────────────────────────────────────────────────────
// Core Data helpers
// ─────────────────────────────────────────────────────────────────────────────

NSArray *fetchNotes(NSPredicate *predicate) {
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"ICNote"];
    NSPredicate *notDeleted = [NSPredicate predicateWithFormat:@"markedForDeletion == NO"];
    req.predicate = predicate
        ? [NSCompoundPredicate andPredicateWithSubpredicates:@[notDeleted, predicate]]
        : notDeleted;
    req.sortDescriptors = @[
        [NSSortDescriptor sortDescriptorWithKey:@"modificationDate"
                                      ascending:NO]
    ];
    NSError *err = nil;
    NSArray *results = [g_moc executeFetchRequest:req error:&err];
    if (err) {
        fprintf(stderr, "Fetch error: %s\n", [[err localizedDescription] UTF8String]);
        return nil;
    }
    return results ?: @[];
}

NSArray *fetchAllNotes(void) {
    return fetchNotes([NSPredicate predicateWithFormat:@"markedForDeletion == NO"]);
}

NSArray *fetchFolders(void) {
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"ICFolder"];
    req.predicate = [NSPredicate predicateWithFormat:@"markedForDeletion == NO"];
    req.sortDescriptors = @[
        [NSSortDescriptor sortDescriptorWithKey:@"title" ascending:YES]
    ];
    NSError *err = nil;
    NSArray *results = [g_moc executeFetchRequest:req error:&err];
    if (err) {
        fprintf(stderr, "Fetch folders error: %s\n",
                [[err localizedDescription] UTF8String]);
        return nil;
    }
    return results ?: @[];
}

id findOrCreateFolder(NSString *title, BOOL create) {
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"ICFolder"];
    req.predicate = [NSPredicate predicateWithFormat:@"title == %@ AND markedForDeletion == NO", title];
    NSArray *results = [g_moc executeFetchRequest:req error:nil];
    if (results.count > 0) return results.firstObject;
    if (!create) return nil;

    NSFetchRequest *fReq = [NSFetchRequest fetchRequestWithEntityName:@"ICFolder"];
    fReq.predicate = [NSPredicate predicateWithFormat:@"markedForDeletion == NO"];
    NSArray *allFolders = [g_moc executeFetchRequest:fReq error:nil];
    id account = nil;
    for (id f in allFolders) {
        account = [f valueForKey:@"account"];
        if (account) break;
    }
    if (!account) return nil;

    id newFolder = [NSEntityDescription
        insertNewObjectForEntityForName:@"ICFolder"
                 inManagedObjectContext:g_moc];
    ((void (*)(id, SEL, id))objc_msgSend)(
        newFolder, NSSelectorFromString(@"setTitle:"), title);
    [newFolder setValue:account forKey:@"account"];
    return newFolder;
}

id defaultFolder(void) {
    id folder = findOrCreateFolder(@"Notes", NO);
    if (folder) return folder;
    NSArray *all = fetchFolders();
    for (id f in all) {
        NSString *t = [f valueForKey:@"title"];
        if (t && t.length > 0) return f;
    }
    return nil;
}

// ─────────────────────────────────────────────────────────────────────────────
// Note access helpers
// ─────────────────────────────────────────────────────────────────────────────

NSString *noteURIString(id note) {
    id objID = ((id (*)(id, SEL))objc_msgSend)(
        note, NSSelectorFromString(@"objectID"));
    NSURL *uri = ((NSURL *(*)(id, SEL))objc_msgSend)(
        objID, NSSelectorFromString(@"URIRepresentation"));
    return [uri absoluteString];
}

NSString *noteIdentifier(id note) {
    return [note valueForKey:@"identifier"];
}

id findNoteByIdentifier(NSString *identifier) {
    if (!identifier || identifier.length == 0) return nil;
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"ICNote"];
    req.predicate = [NSPredicate predicateWithFormat:
        @"markedForDeletion == NO AND identifier ==[c] %@", identifier];
    req.fetchLimit = 1;
    NSArray *results = [g_moc executeFetchRequest:req error:nil];
    return results.count > 0 ? results.firstObject : nil;
}

NSInteger noteIntPK(id note) {
    NSString *uri = noteURIString(note);
    NSRange pRange = [uri rangeOfString:@"/p" options:NSBackwardsSearch];
    if (pRange.location == NSNotFound) return -1;
    return [[uri substringFromIndex:pRange.location + 2] integerValue];
}

NSString *noteTitle(id note) {
    NSString *t = ((id (*)(id, SEL))objc_msgSend)(
        note, NSSelectorFromString(@"title"));
    return t ?: @"(untitled)";
}

NSString *folderName(id note) {
    id folder = [note valueForKey:@"folder"];
    if (!folder) return @"Notes";
    id title = [folder valueForKey:@"title"];
    if (title && [title isKindOfClass:[NSString class]]) return (NSString *)title;
    id locTitle = ((id (*)(id, SEL))objc_msgSend)(
        folder, NSSelectorFromString(@"localizedTitle"));
    return (locTitle && [locTitle isKindOfClass:[NSString class]])
        ? (NSString *)locTitle : @"Notes";
}

id noteVisibleAttachments(id note) {
    return ((id (*)(id, SEL))objc_msgSend)(
        note, NSSelectorFromString(@"visibleAttachments"));
}

NSUInteger noteAttachmentCount(id note) {
    id atts = noteVisibleAttachments(note);
    return atts ? [atts count] : 0;
}

NSArray *attachmentsAsArray(id attsObj) {
    if (!attsObj) return @[];
    if ([attsObj isKindOfClass:[NSArray class]]) return (NSArray *)attsObj;
    if ([attsObj respondsToSelector:@selector(allObjects)]) {
        return [(NSSet *)attsObj allObjects];
    }
    if ([attsObj respondsToSelector:@selector(array)]) {
        return [(NSOrderedSet *)attsObj array];
    }
    return @[];
}

NSArray *noteAttachmentNames(id note) {
    id attsObj = noteVisibleAttachments(note);
    NSArray *atts = attachmentsAsArray(attsObj);
    if (atts.count == 0) return @[];

    NSMutableArray *names = [NSMutableArray array];
    for (id att in atts) {
        NSString *name = nil;
        id ut = [att valueForKey:@"userTitle"];
        if (ut && [ut isKindOfClass:[NSString class]] && [(NSString *)ut length] > 0) {
            name = (NSString *)ut;
        } else {
            id t = [att valueForKey:@"title"];
            if (t && [t isKindOfClass:[NSString class]] && [(NSString *)t length] > 0) {
                name = (NSString *)t;
            }
        }
        if (!name || name.length == 0) {
            id uti = [att valueForKey:@"typeUTI"];
            if (uti && [uti isKindOfClass:[NSString class]]) {
                name = [NSString stringWithFormat:@"[%@]", uti];
            } else {
                name = @"attachment";
            }
        }
        [names addObject:name];
    }
    return names;
}

// ─────────────────────────────────────────────────────────────────────────────
// CRDT / mergeableString helpers
// ─────────────────────────────────────────────────────────────────────────────

id noteMergeableString(id note) {
    return ((id (*)(id, SEL))objc_msgSend)(
        note, NSSelectorFromString(@"mergeableString"));
}

NSString *noteRawText(id note) {
    id mergeStr = noteMergeableString(note);
    if (!mergeStr) return @"";

    id attrStr = ((id (*)(id, SEL))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"string"));
    if (!attrStr) return @"";

    if ([attrStr isKindOfClass:[NSAttributedString class]]) {
        return [(NSAttributedString *)attrStr string];
    }
    return (NSString *)attrStr ?: @"";
}

NSString *noteTextForDisplay(id note) {
    NSString *raw = noteRawText(note);
    NSArray *names = noteAttachmentNames(note);
    NSMutableString *buf = [NSMutableString stringWithCapacity:[raw length]];
    NSUInteger ai = 0;

    for (NSUInteger i = 0; i < [raw length]; i++) {
        unichar c = [raw characterAtIndex:i];
        if (c == ATTACHMENT_MARKER) {
            NSString *aname = (ai < names.count) ? names[ai] : @"attachment";
            [buf appendFormat:@"[📎 %@]", aname];
            ai++;
        } else {
            [buf appendFormat:@"%C", c];
        }
    }
    return buf;
}

NSString *rawTextToEditable(NSString *raw, NSArray *names) {
    NSMutableString *buf = [NSMutableString stringWithCapacity:[raw length]];
    NSUInteger ai = 0;

    for (NSUInteger i = 0; i < [raw length]; i++) {
        unichar c = [raw characterAtIndex:i];
        if (c == ATTACHMENT_MARKER) {
            NSString *aname = (ai < names.count) ? names[ai] : @"attachment";
            [buf appendFormat:@"%%%%ATTACHMENT_%lu_%@%%%%",
             (unsigned long)ai, aname];
            ai++;
        } else {
            [buf appendFormat:@"%C", c];
        }
    }
    return buf;
}

NSString *editableToRawText(NSString *edited) {
    NSMutableString *result = [NSMutableString stringWithString:edited];
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"%%ATTACHMENT_\\d+_[^%]*%%"
                             options:0
                               error:nil];
    NSArray *matches = [regex matchesInString:result
                                      options:0
                                        range:NSMakeRange(0, [result length])];
    for (NSInteger i = (NSInteger)matches.count - 1; i >= 0; i--) {
        NSTextCheckingResult *match = matches[(NSUInteger)i];
        [result replaceCharactersInRange:match.range
                              withString:@"\uFFFC"];
    }
    return result;
}

BOOL saveContext(void) {
    // Use saveImmediately — the no-arg save on ICNoteContext preserves CloudKit
    // dirty flags (needsToBePushedToCloud), while save: can clear them.
    //
    // Cross-process sync: the NoteStore.sqlite is opened with both
    // NSPersistentHistoryTrackingKey and NSPersistentStoreRemoteChangeNotificationPostOptionKey
    // enabled. CoreData automatically posts NSPersistentStoreRemoteChangeNotification
    // to Notes.app's ICManagedObjectContextUpdater after our write, which fetches
    // the persistent history and merges our changes into Notes.app's in-memory model.
    // Notes.app's CloudKit engine then sees the updated objects and pushes to iCloud.
    BOOL ok = ((BOOL (*)(id, SEL))objc_msgSend)(
        g_ctx, NSSelectorFromString(@"saveImmediately"));
    if (!ok) {
        // Fallback to save: with error reporting
        NSError *err = nil;
        ok = ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(
            g_ctx, NSSelectorFromString(@"save:"), &err);
        if (err) {
            fprintf(stderr, "Save error: %s\n",
                    [[err localizedDescription] UTF8String]);
        }
    }

    // Belt-and-suspenders: also post the editor extension notification,
    // which triggers Notes.app's registered handler to call requestUpdate
    // on its ICManagedObjectContextUpdater.
    if (ok) {
        notify_post("ICEditorExtensionDidSaveNotification");
        id coord = ((id (*)(id, SEL))objc_msgSend)(
            g_ctx, NSSelectorFromString(@"crossProcessChangeCoordinator"));
        if (coord) {
            ((void (*)(id, SEL))objc_msgSend)(
                coord,
                NSSelectorFromString(@"postEditorExtensionDidSaveNotification"));
        }
    }
    return ok;
}

BOOL applyCRDTEdit(id note, NSString *oldText, NSString *newText) {
    if ([oldText isEqualToString:newText]) {
        printf("No changes detected.\n");
        return YES;
    }

    id mergeStr = noteMergeableString(note);
    if (!mergeStr) {
        fprintf(stderr, "Error: Could not get mergeableString for note\n");
        return NO;
    }

    NSUInteger oldLen = [oldText length];
    NSUInteger newLen = [newText length];

    NSUInteger prefix = 0;
    while (prefix < oldLen && prefix < newLen &&
           [oldText characterAtIndex:prefix] ==
               [newText characterAtIndex:prefix]) {
        prefix++;
    }

    NSUInteger suffix = 0;
    while (suffix < (oldLen - prefix) && suffix < (newLen - prefix) &&
           [oldText characterAtIndex:oldLen - 1 - suffix] ==
               [newText characterAtIndex:newLen - 1 - suffix]) {
        suffix++;
    }

    NSRange replaceRange = NSMakeRange(prefix, oldLen - prefix - suffix);
    NSString *replaceWith = [newText substringWithRange:
                             NSMakeRange(prefix, newLen - prefix - suffix)];

    ((void (*)(id, SEL))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"beginEditing"));

    ((void (*)(id, SEL, NSRange, id))objc_msgSend)(
        mergeStr,
        NSSelectorFromString(@"replaceCharactersInRange:withString:"),
        replaceRange,
        replaceWith);

    ((void (*)(id, SEL))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"endEditing"));

    ((void (*)(id, SEL))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"generateIdsForLocalChanges"));

    ((void (*)(id, SEL))objc_msgSend)(
        note, NSSelectorFromString(@"updateDerivedAttributesIfNeeded"));

    return YES;
}

// ─────────────────────────────────────────────────────────────────────────────
// Note listing helpers
// ─────────────────────────────────────────────────────────────────────────────

NSArray *filteredNotes(NSString *filterFolder) {
    NSArray *all = fetchAllNotes();
    if (!all) return @[];

    NSMutableArray *result = [NSMutableArray array];
    for (id note in all) {
        id folder = [note valueForKey:@"folder"];
        if (folder) {
            BOOL isTrash = ((BOOL (*)(id, SEL))objc_msgSend)(
                folder, NSSelectorFromString(@"isTrashFolder"));
            if (isTrash && !filterFolder) continue;
        }

        if (!filterFolder) {
            [result addObject:note];
        } else {
            NSString *fn = folderName(note);
            if ([fn caseInsensitiveCompare:filterFolder] == NSOrderedSame) {
                [result addObject:note];
            }
        }
    }
    return result;
}

id noteAtIndex(NSUInteger idx, NSString *folder) {
    NSArray *notes = filteredNotes(folder);
    for (id note in notes) {
        if ((NSUInteger)noteIntPK(note) == idx) return note;
    }
    return nil;
}

// ─────────────────────────────────────────────────────────────────────────────
// JSON helpers
// ─────────────────────────────────────────────────────────────────────────────

NSString *jsonEscapeString(NSString *s) {
    if (!s) return @"";
    NSMutableString *r = [NSMutableString stringWithString:s];
    [r replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, r.length)];
    [r replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, r.length)];
    [r replaceOccurrencesOfString:@"\n" withString:@"\\n"  options:0 range:NSMakeRange(0, r.length)];
    [r replaceOccurrencesOfString:@"\r" withString:@"\\r"  options:0 range:NSMakeRange(0, r.length)];
    [r replaceOccurrencesOfString:@"\t" withString:@"\\t"  options:0 range:NSMakeRange(0, r.length)];
    return r;
}

// ─────────────────────────────────────────────────────────────────────────────
// Date helpers
// ─────────────────────────────────────────────────────────────────────────────

NSString *isoDateString(NSDate *date) {
    if (!date) return @"";
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    fmt.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    return [fmt stringFromDate:date];
}

NSDate *parseDateString(NSString *str) {
    if (!str) return nil;
    NSString *lower = [str lowercaseString];

    // Relative dates
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *now = [NSDate date];

    if ([lower isEqualToString:@"today"]) {
        return [cal startOfDayForDate:now];
    }
    if ([lower isEqualToString:@"yesterday"]) {
        NSDate *yesterday = [cal dateByAddingUnit:NSCalendarUnitDay value:-1
                                           toDate:now options:0];
        return [cal startOfDayForDate:yesterday];
    }

    // "N days/weeks/months ago"
    NSRegularExpression *relRe = [NSRegularExpression
        regularExpressionWithPattern:@"^(\\d+)\\s+(day|week|month|year)s?\\s+ago$"
        options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *m = [relRe firstMatchInString:lower options:0
                                range:NSMakeRange(0, lower.length)];
    if (m) {
        NSInteger n = [[lower substringWithRange:[m rangeAtIndex:1]] integerValue];
        NSString *unit = [lower substringWithRange:[m rangeAtIndex:2]];
        NSCalendarUnit calUnit = NSCalendarUnitDay;
        if ([unit isEqualToString:@"week"])  { calUnit = NSCalendarUnitDay; n *= 7; }
        else if ([unit isEqualToString:@"month"]) calUnit = NSCalendarUnitMonth;
        else if ([unit isEqualToString:@"year"])  calUnit = NSCalendarUnitYear;
        NSDate *d = [cal dateByAddingUnit:calUnit value:-n toDate:now options:0];
        return [cal startOfDayForDate:d];
    }

    // ISO 8601 with time
    NSDateFormatter *isoFull = [[NSDateFormatter alloc] init];
    isoFull.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss";
    isoFull.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    NSDate *d = [isoFull dateFromString:str];
    if (d) return d;

    // ISO 8601 date only
    NSDateFormatter *isoDate = [[NSDateFormatter alloc] init];
    isoDate.dateFormat = @"yyyy-MM-dd";
    isoDate.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    d = [isoDate dateFromString:str];
    if (d) return d;

    return nil;
}

// ─────────────────────────────────────────────────────────────────────────────
// Cider Settings helpers
// ─────────────────────────────────────────────────────────────────────────────

static NSString *kSettingsFolder = @"Cider Templates";
static NSString *kSettingsTitle = @"Cider Settings";

static id findSettingsNote(void) {
    NSArray *notes = filteredNotes(kSettingsFolder);
    for (id note in notes) {
        if ([noteTitle(note) isEqualToString:kSettingsTitle]) {
            return note;
        }
    }
    return nil;
}

NSDictionary *loadCiderSettings(void) {
    id note = findSettingsNote();
    if (!note) return @{};

    NSString *raw = noteRawText(note);
    if (!raw) return @{};

    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    NSArray *lines = [raw componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSRange colonRange = [line rangeOfString:@": "];
        if (colonRange.location == NSNotFound) continue;
        NSString *key = [[line substringToIndex:colonRange.location]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *value = [[line substringFromIndex:colonRange.location + 2]
                            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (key.length > 0 && ![key isEqualToString:kSettingsTitle]) {
            settings[[key lowercaseString]] = value;
        }
    }
    return settings;
}

NSString *getCiderSetting(NSString *key) {
    NSDictionary *settings = loadCiderSettings();
    return settings[[key lowercaseString]];
}

int setCiderSetting(NSString *key, NSString *value) {
    id note = findSettingsNote();
    NSString *normalizedKey = [key lowercaseString];

    if (!note) {
        // Create settings note
        id folder = findOrCreateFolder(kSettingsFolder, YES);
        if (!folder) return 1;
        id account = [folder valueForKey:@"account"];

        note = [NSEntityDescription
            insertNewObjectForEntityForName:@"ICNote"
                     inManagedObjectContext:g_moc];
        ((void (*)(id, SEL, id))objc_msgSend)(
            note, NSSelectorFromString(@"setFolder:"), folder);
        if (account) {
            ((void (*)(id, SEL, id))objc_msgSend)(
                note, NSSelectorFromString(@"setAccount:"), account);
        }
        [note setValue:[NSDate date] forKey:@"creationDate"];
        [note setValue:[NSDate date] forKey:@"modificationDate"];

        id noteDataEntity = [NSEntityDescription
            insertNewObjectForEntityForName:@"ICNoteData"
                     inManagedObjectContext:g_moc];
        [note setValue:noteDataEntity forKey:@"noteData"];

        NSString *content = [NSString stringWithFormat:@"%@\n%@: %@",
                             kSettingsTitle, normalizedKey, value];
        id mergeStr = noteMergeableString(note);
        if (!mergeStr) return 1;
        ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"beginEditing"));
        ((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(
            mergeStr, NSSelectorFromString(@"insertString:atIndex:"),
            content, (NSUInteger)0);
        ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"endEditing"));
        ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"generateIdsForLocalChanges"));
        ((void (*)(id, SEL))objc_msgSend)(note, NSSelectorFromString(@"saveNoteData"));
        ((void (*)(id, SEL))objc_msgSend)(note, NSSelectorFromString(@"updateDerivedAttributesIfNeeded"));
        return saveContext() ? 0 : 1;
    }

    // Update existing settings note
    NSString *raw = noteRawText(note);
    NSString *linePattern = [NSString stringWithFormat:@"%@: ", normalizedKey];
    NSMutableArray *lines = [[raw componentsSeparatedByString:@"\n"] mutableCopy];
    BOOL found = NO;
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = lines[i];
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceCharacterSet]];
        if ([[trimmed lowercaseString] hasPrefix:[linePattern lowercaseString]]) {
            lines[i] = [NSString stringWithFormat:@"%@: %@", normalizedKey, value];
            found = YES;
            break;
        }
    }
    if (!found) {
        [lines addObject:[NSString stringWithFormat:@"%@: %@", normalizedKey, value]];
    }
    NSString *newText = [lines componentsJoinedByString:@"\n"];
    if (!applyCRDTEdit(note, raw, newText)) return 1;
    return saveContext() ? 0 : 1;
}

// ─────────────────────────────────────────────────────────────────────────────
// AppleScript helper
// ─────────────────────────────────────────────────────────────────────────────

NSAppleEventDescriptor *runAppleScript(NSString *src, NSString **errMsg) {
    NSDictionary *err = nil;
    NSAppleScript *as = [[NSAppleScript alloc] initWithSource:src];
    NSAppleEventDescriptor *res = [as executeAndReturnError:&err];
    if (!res && errMsg) {
        *errMsg = [err[@"NSAppleScriptErrorMessage"]
                   ?: [err description] ?: @"Unknown AppleScript error"
                   copy];
    }
    return res;
}

// ─────────────────────────────────────────────────────────────────────────────
// Column formatting helpers
// ─────────────────────────────────────────────────────────────────────────────

NSString *truncStr(NSString *s, NSUInteger maxLen) {
    if ([s length] <= maxLen) return s;
    return [[s substringToIndex:maxLen - 2] stringByAppendingString:@".."];
}

NSString *padRight(NSString *s, NSUInteger width) {
    if ([s length] >= width) return [s substringToIndex:width];
    NSMutableString *padded = [NSMutableString stringWithString:s];
    while ([padded length] < width) [padded appendString:@" "];
    return padded;
}

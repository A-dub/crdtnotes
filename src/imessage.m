/**
 * imessage.m — iMessage commands for cider
 *
 * Reads from ~/Library/Messages/chat.db (SQLite).
 * Sends via AppleScript (tell application "Messages").
 */

#import "cider.h"
#include <sqlite3.h>

static sqlite3 *g_msgDB = NULL;

// ─────────────────────────────────────────────────────────────────────────────
// Hanging-indent helper: continuation lines align with first line's text
// ─────────────────────────────────────────────────────────────────────────────

static void printHanging(const char *prefix, const char *body) {
    int indent = (int)strlen(prefix);
    const char *p = body;
    BOOL first = YES;
    while (*p) {
        const char *nl = strchr(p, '\n');
        int len = nl ? (int)(nl - p) : (int)strlen(p);
        if (first) {
            printf("%s%.*s\n", prefix, len, p);
            first = NO;
        } else {
            printf("%*s%.*s\n", indent, "", len, p);
        }
        if (!nl) break;
        p = nl + 1;
    }
}

static NSString *describeAttachmentForMessage(int64_t rowid) {
    if (rowid <= 0 || !g_msgDB) return @"attachment";

    const char *sql =
        "SELECT a.transfer_name, a.filename, a.mime_type, a.uti "
        "FROM attachment a "
        "JOIN message_attachment_join maj ON maj.attachment_id = a.ROWID "
        "WHERE maj.message_id = ? "
        "ORDER BY a.ROWID ASC LIMIT 1";

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(g_msgDB, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return @"attachment";
    }

    sqlite3_bind_int64(stmt, 1, rowid);

    NSString *label = @"attachment";
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const char *transferName = (const char *)sqlite3_column_text(stmt, 0);
        const char *filename = (const char *)sqlite3_column_text(stmt, 1);
        const char *mime = (const char *)sqlite3_column_text(stmt, 2);
        const char *uti = (const char *)sqlite3_column_text(stmt, 3);

        NSString *name = nil;
        if (transferName && strlen(transferName) > 0) {
            name = [NSString stringWithUTF8String:transferName];
        } else if (filename && strlen(filename) > 0) {
            name = [[NSString stringWithUTF8String:filename] lastPathComponent];
        }

        NSString *kind = nil;
        if (mime && strncmp(mime, "image/", 6) == 0) kind = @"image";
        else if (mime && strncmp(mime, "video/", 6) == 0) kind = @"video";
        else if (mime && strncmp(mime, "audio/", 6) == 0) kind = @"audio";
        else if (mime && strcmp(mime, "application/pdf") == 0) kind = @"pdf";
        else if (uti && strstr(uti, "contact") != NULL) kind = @"contact";
        else if (uti && strstr(uti, "vcard") != NULL) kind = @"contact";
        else if (uti && strstr(uti, "calendar") != NULL) kind = @"calendar";
        else if (mime && strlen(mime) > 0) kind = [NSString stringWithUTF8String:mime];
        else if (uti && strlen(uti) > 0) kind = [NSString stringWithUTF8String:uti];

        if (name.length > 0) {
            // Transfer names often include an internal GUID prefix; keep the human part.
            NSRange space = [name rangeOfString:@" "];
            if (space.location != NSNotFound && space.location + 1 < name.length) {
                NSString *tail = [name substringFromIndex:space.location + 1];
                if ([tail rangeOfString:@"."] .location != NSNotFound) {
                    name = tail;
                }
            }
        }

        if (name.length > 0 && kind.length > 0) {
            label = [NSString stringWithFormat:@"%@: %@", kind, name];
        } else if (name.length > 0) {
            label = name;
        } else if (kind.length > 0) {
            label = kind;
        }
    }

    sqlite3_finalize(stmt);
    return label;
}

static NSString *displayMsgText(NSString *text, BOOL hasAttach, int64_t rowid) {
    NSString *attachmentLabel = hasAttach ?
        [NSString stringWithFormat:@"[%@]", describeAttachmentForMessage(rowid)] : nil;
    if (!text || text.length == 0) {
        return attachmentLabel ?: @"";
    }

    NSString *objectReplacement = @"\uFFFC";
    if ([text isEqualToString:objectReplacement]) {
        return attachmentLabel ?: @"[object]";
    }

    // Some attachment messages include replacement chars plus private-use junk.
    if (hasAttach) {
        NSString *trimmed = [[text stringByReplacingOccurrencesOfString:objectReplacement
                                                             withString:@""]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0 || [trimmed canBeConvertedToEncoding:NSASCIIStringEncoding] == NO) {
            return attachmentLabel;
        }
        NSString *rendered = [[text stringByReplacingOccurrencesOfString:objectReplacement
                                                              withString:attachmentLabel]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([rendered rangeOfString:@"<U+"].location != NSNotFound) {
            return attachmentLabel;
        }
        return rendered;
    }

    return [text stringByReplacingOccurrencesOfString:objectReplacement
                                           withString:@"[object]"];
}

// ─────────────────────────────────────────────────────────────────────────────
// Database access
// ─────────────────────────────────────────────────────────────────────────────

static NSString *messagesDBPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Messages/chat.db"];
}

BOOL openMessagesDB(void) {
    if (g_msgDB) return YES;
    NSString *path = messagesDBPath();
    int rc = sqlite3_open_v2([path UTF8String], &g_msgDB,
                             SQLITE_OPEN_READONLY, NULL);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Cannot open Messages database: %s\n",
                sqlite3_errmsg(g_msgDB));
        fprintf(stderr, "Path: %s\n", [path UTF8String]);
        fprintf(stderr, "Make sure Terminal/cider has Full Disk Access "
                        "in System Preferences > Privacy & Security.\n");
        g_msgDB = NULL;
        return NO;
    }
    return YES;
}

void closeMessagesDB(void) {
    if (g_msgDB) {
        sqlite3_close(g_msgDB);
        g_msgDB = NULL;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Date helpers — Messages uses Apple Cocoa epoch (2001-01-01) in nanoseconds
// ─────────────────────────────────────────────────────────────────────────────

static NSDate *dateFromChatDB(int64_t val) {
    if (val == 0) return nil;
    // After ~2017 Apple switched to nanoseconds
    double seconds = (val > 1000000000000) ? (double)val / 1e9 : (double)val;
    return [NSDate dateWithTimeIntervalSinceReferenceDate:seconds];
}

static NSString *formatMsgDate(NSDate *date) {
    if (!date) return @"";
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    [fmt setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    return [fmt stringFromDate:date];
}

static NSString *formatMsgDateShort(NSDate *date) {
    if (!date) return @"";
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    NSDate *today = [NSDate date];
    NSCalendar *cal = [NSCalendar currentCalendar];
    if ([cal isDate:date inSameDayAsDate:today]) {
        [fmt setDateFormat:@"HH:mm"];
    } else if ([[cal components:NSCalendarUnitDay
                 fromDate:date toDate:today options:0] day] < 7) {
        [fmt setDateFormat:@"EEE HH:mm"];
    } else if ([cal component:NSCalendarUnitYear fromDate:date] ==
               [cal component:NSCalendarUnitYear fromDate:today]) {
        [fmt setDateFormat:@"MMM d"];
    } else {
        [fmt setDateFormat:@"MMM d, yyyy"];
    }
    return [fmt stringFromDate:date];
}

// ─────────────────────────────────────────────────────────────────────────────
// Chat GUID helpers
// ─────────────────────────────────────────────────────────────────────────────

// Resolve a chat identifier — accepts:
//   - Full GUID: "iMessage;-;+1234567890"
//   - Phone number: "+1234567890"
//   - Email: "user@example.com"
//   - Chat index from list: "1", "2", etc.
static NSString *resolveChatGUID(const char *input) {
    NSString *s = [NSString stringWithUTF8String:input];

    // Already a full GUID
    if ([s containsString:@";"])
        return s;

    // Numeric index — look up from chat list
    int idx = atoi(input);
    if (idx > 0) {
        sqlite3_stmt *stmt;
        const char *sql =
            "SELECT c.guid FROM chat c "
            "JOIN chat_message_join cmj ON cmj.chat_id = c.ROWID "
            "JOIN message m ON m.ROWID = cmj.message_id "
            "GROUP BY c.ROWID "
            "ORDER BY MAX(m.date) DESC "
            "LIMIT 1 OFFSET ?";
        if (sqlite3_prepare_v2(g_msgDB, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_int(stmt, 1, idx - 1);
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                NSString *guid = [NSString stringWithUTF8String:
                    (const char *)sqlite3_column_text(stmt, 0)];
                sqlite3_finalize(stmt);
                return guid;
            }
            sqlite3_finalize(stmt);
        }
        return nil;
    }

    // Phone/email — try to find matching chat
    sqlite3_stmt *stmt;
    const char *sql =
        "SELECT guid FROM chat WHERE chat_identifier = ? "
        "ORDER BY ROWID DESC LIMIT 1";
    if (sqlite3_prepare_v2(g_msgDB, sql, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, [s UTF8String], -1, SQLITE_STATIC);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            NSString *guid = [NSString stringWithUTF8String:
                (const char *)sqlite3_column_text(stmt, 0)];
            sqlite3_finalize(stmt);
            return guid;
        }
        sqlite3_finalize(stmt);
    }

    // Try with iMessage prefix
    NSString *tryGUID = [NSString stringWithFormat:@"iMessage;-;%@", s];
    sql = "SELECT guid FROM chat WHERE guid = ?";
    if (sqlite3_prepare_v2(g_msgDB, sql, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, [tryGUID UTF8String], -1, SQLITE_STATIC);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            sqlite3_finalize(stmt);
            return tryGUID;
        }
        sqlite3_finalize(stmt);
    }

    // Try SMS
    tryGUID = [NSString stringWithFormat:@"SMS;-;%@", s];
    sql = "SELECT guid FROM chat WHERE guid = ?";
    if (sqlite3_prepare_v2(g_msgDB, sql, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, [tryGUID UTF8String], -1, SQLITE_STATIC);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            sqlite3_finalize(stmt);
            return tryGUID;
        }
        sqlite3_finalize(stmt);
    }

    return nil;
}

// Get display name for a chat
static NSString *chatDisplayName(const char *guid, const char *chatIdent,
                                  const char *displayName, const char *service) {
    // Use display_name if available (group chats)
    if (displayName && strlen(displayName) > 0)
        return [NSString stringWithUTF8String:displayName];

    // Try to get contact name from Contacts
    if (chatIdent && strlen(chatIdent) > 0) {
        NSString *ident = [NSString stringWithUTF8String:chatIdent];
        // Look up in handle table for a better name — but chat.db
        // doesn't store contact names. Return the identifier.
        return ident;
    }

    return [NSString stringWithUTF8String:guid];
}

// ─────────────────────────────────────────────────────────────────────────────
// msg list — list conversations
// ─────────────────────────────────────────────────────────────────────────────

void cmdMsgList(NSUInteger limit, BOOL jsonOutput, NSString *service) {
    if (!openMessagesDB()) return;

    NSMutableString *sql = [NSMutableString stringWithString:
        @"SELECT c.ROWID, c.guid, c.chat_identifier, c.display_name, "
        @"c.service_name, c.style, "
        @"(SELECT COUNT(*) FROM chat_message_join WHERE chat_id = c.ROWID) as msg_count, "
        @"(SELECT MAX(m2.date) FROM message m2 "
        @" JOIN chat_message_join cmj2 ON cmj2.message_id = m2.ROWID "
        @" WHERE cmj2.chat_id = c.ROWID) as last_date, "
        @"(SELECT m3.text FROM message m3 "
        @" JOIN chat_message_join cmj3 ON cmj3.message_id = m3.ROWID "
        @" WHERE cmj3.chat_id = c.ROWID ORDER BY m3.date DESC LIMIT 1) as last_msg, "
        @"(SELECT COUNT(*) FROM chat_handle_join WHERE chat_id = c.ROWID) as participant_count "
        @"FROM chat c "];

    if (service) {
        [sql appendFormat:@"WHERE c.service_name = '%@' ", service];
    }

    [sql appendString:@"ORDER BY last_date DESC "];

    if (limit > 0) {
        [sql appendFormat:@"LIMIT %lu", (unsigned long)limit];
    } else {
        [sql appendString:@"LIMIT 50"];
    }

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(g_msgDB, [sql UTF8String], -1, &stmt, NULL) != SQLITE_OK) {
        fprintf(stderr, "Query failed: %s\n", sqlite3_errmsg(g_msgDB));
        return;
    }

    if (jsonOutput) {
        printf("[\n");
        int idx = 0;
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            if (idx > 0) printf(",\n");
            const char *guid = (const char *)sqlite3_column_text(stmt, 1);
            const char *chatIdent = (const char *)sqlite3_column_text(stmt, 2);
            const char *displayName = (const char *)sqlite3_column_text(stmt, 3);
            const char *svc = (const char *)sqlite3_column_text(stmt, 4);
            int style = sqlite3_column_int(stmt, 5);
            int msgCount = sqlite3_column_int(stmt, 6);
            int64_t lastDate = sqlite3_column_int64(stmt, 7);
            const char *lastMsg = (const char *)sqlite3_column_text(stmt, 8);
            int participantCount = sqlite3_column_int(stmt, 9);

            NSDate *date = dateFromChatDB(lastDate);
            NSString *name = chatDisplayName(guid, chatIdent, displayName, svc);

            printf("  {\n");
            printf("    \"index\": %d,\n", idx + 1);
            printf("    \"guid\": \"%s\",\n", guid ?: "");
            printf("    \"chat_identifier\": \"%s\",\n", chatIdent ?: "");
            printf("    \"display_name\": \"%s\",\n",
                   [jsonEscapeString(name) UTF8String]);
            printf("    \"service\": \"%s\",\n", svc ?: "");
            printf("    \"is_group\": %s,\n", style == 43 ? "true" : "false");
            printf("    \"message_count\": %d,\n", msgCount);
            printf("    \"participant_count\": %d,\n", participantCount);
            printf("    \"last_message_date\": \"%s\",\n",
                   date ? [isoDateString(date) UTF8String] : "");
            printf("    \"last_message\": \"%s\"\n",
                   lastMsg ? [jsonEscapeString([NSString stringWithUTF8String:lastMsg]) UTF8String] : "");
            printf("  }");
            idx++;
        }
        printf("\n]\n");
    } else {
        int idx = 0;
        printf("%-4s  %-7s  %-25s  %-6s  %-12s  %s\n",
               "#", "Service", "Name", "Msgs", "Last Active", "Preview");
        printf("────  ───────  ─────────────────────────  ──────  ────────────  ─────────\n");

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const char *guid = (const char *)sqlite3_column_text(stmt, 1);
            const char *chatIdent = (const char *)sqlite3_column_text(stmt, 2);
            const char *displayName = (const char *)sqlite3_column_text(stmt, 3);
            const char *svc = (const char *)sqlite3_column_text(stmt, 4);
            int style = sqlite3_column_int(stmt, 5);
            int msgCount = sqlite3_column_int(stmt, 6);
            int64_t lastDate = sqlite3_column_int64(stmt, 7);
            const char *lastMsg = (const char *)sqlite3_column_text(stmt, 8);

            NSDate *date = dateFromChatDB(lastDate);
            NSString *name = chatDisplayName(guid, chatIdent, displayName, svc);
            NSString *svcShort = nil;
            if (svc) {
                NSString *svcStr = [NSString stringWithUTF8String:svc];
                if ([svcStr isEqualToString:@"iMessage"]) svcShort = @"iMsg";
                else if ([svcStr isEqualToString:@"SMS"]) svcShort = @"SMS";
                else svcShort = svcStr;
            }
            if (style == 43) {
                name = [NSString stringWithFormat:@"[G] %@", name];
            }

            NSString *preview = @"";
            if (lastMsg) {
                preview = [NSString stringWithUTF8String:lastMsg];
                preview = [preview stringByReplacingOccurrencesOfString:@"\n"
                                                            withString:@" "];
                preview = truncStr(preview, 40);
            }

            printf("%-4d  %-7s  %-25s  %-6d  %-12s  %s\n",
                   idx + 1,
                   svcShort ? [svcShort UTF8String] : "?",
                   [truncStr(name, 25) UTF8String],
                   msgCount,
                   [formatMsgDateShort(date) UTF8String],
                   [preview UTF8String]);
            idx++;
        }
        printf("\n%d conversations shown.\n", idx);
    }

    sqlite3_finalize(stmt);
}

// ─────────────────────────────────────────────────────────────────────────────
// msg show — view messages in a conversation
// ─────────────────────────────────────────────────────────────────────────────

void cmdMsgShow(const char *chatRef, NSUInteger limit, BOOL jsonOutput,
                NSString *afterStr, NSString *beforeStr, BOOL sortAsc) {
    if (!openMessagesDB()) return;

    NSString *chatGUID = resolveChatGUID(chatRef);
    if (!chatGUID) {
        fprintf(stderr, "Chat not found: %s\n", chatRef);
        return;
    }

    NSMutableString *sql = [NSMutableString stringWithString:
        @"SELECT m.ROWID, m.guid, m.text, m.date, m.is_from_me, "
        @"m.handle_id, m.cache_has_attachments, m.associated_message_type, "
        @"m.associated_message_guid, m.subject, m.date_read, "
        @"m.date_delivered, m.is_read, m.is_sent, m.is_delivered, "
        @"m.date_edited, m.date_retracted, m.item_type, m.group_title, "
        @"m.group_action_type, m.service, m.error, "
        @"m.expressive_send_style_id, m.thread_originator_guid, "
        @"m.reply_to_guid, m.associated_message_emoji, "
        @"h.id as handle_address "
        @"FROM message m "
        @"JOIN chat_message_join cmj ON cmj.message_id = m.ROWID "
        @"JOIN chat c ON c.ROWID = cmj.chat_id "
        @"LEFT JOIN handle h ON h.ROWID = m.handle_id "
        @"WHERE c.guid = ? "];

    if (afterStr) {
        NSDate *afterDate = parseDateString(afterStr);
        if (afterDate) {
            int64_t ts = (int64_t)([afterDate timeIntervalSinceReferenceDate] * 1e9);
            [sql appendFormat:@"AND m.date >= %lld ", ts];
        }
    }
    if (beforeStr) {
        NSDate *beforeDate = parseDateString(beforeStr);
        if (beforeDate) {
            int64_t ts = (int64_t)([beforeDate timeIntervalSinceReferenceDate] * 1e9);
            [sql appendFormat:@"AND m.date <= %lld ", ts];
        }
    }

    [sql appendFormat:@"ORDER BY m.date %s ", sortAsc ? "ASC" : "DESC"];

    if (limit > 0) {
        [sql appendFormat:@"LIMIT %lu", (unsigned long)limit];
    } else {
        [sql appendString:@"LIMIT 50"];
    }

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(g_msgDB, [sql UTF8String], -1, &stmt, NULL) != SQLITE_OK) {
        fprintf(stderr, "Query failed: %s\n", sqlite3_errmsg(g_msgDB));
        return;
    }

    sqlite3_bind_text(stmt, 1, [chatGUID UTF8String], -1, SQLITE_STATIC);

    // Collect messages (they're in DESC order, we want chronological)
    NSMutableArray *messages = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        NSMutableDictionary *msg = [NSMutableDictionary dictionary];

        int64_t rowid = sqlite3_column_int64(stmt, 0);
        const char *guid = (const char *)sqlite3_column_text(stmt, 1);
        const char *text = (const char *)sqlite3_column_text(stmt, 2);
        int64_t date = sqlite3_column_int64(stmt, 3);
        int isFromMe = sqlite3_column_int(stmt, 4);
        // column 5 = handle_id (used for join, not needed directly)
        int hasAttach = sqlite3_column_int(stmt, 6);
        int assocType = sqlite3_column_int(stmt, 7);
        const char *assocGuid = (const char *)sqlite3_column_text(stmt, 8);
        const char *subject = (const char *)sqlite3_column_text(stmt, 9);
        int64_t dateRead = sqlite3_column_int64(stmt, 10);
        int64_t dateDelivered = sqlite3_column_int64(stmt, 11);
        int isRead = sqlite3_column_int(stmt, 12);
        int isSent = sqlite3_column_int(stmt, 13);
        int isDelivered = sqlite3_column_int(stmt, 14);
        int64_t dateEdited = sqlite3_column_int64(stmt, 15);
        int64_t dateRetracted = sqlite3_column_int64(stmt, 16);
        int itemType = sqlite3_column_int(stmt, 17);
        const char *groupTitle = (const char *)sqlite3_column_text(stmt, 18);
        int groupAction = sqlite3_column_int(stmt, 19);
        const char *svc = (const char *)sqlite3_column_text(stmt, 20);
        int error = sqlite3_column_int(stmt, 21);
        const char *effect = (const char *)sqlite3_column_text(stmt, 22);
        const char *threadGuid = (const char *)sqlite3_column_text(stmt, 23);
        const char *replyGuid = (const char *)sqlite3_column_text(stmt, 24);
        const char *emoji = (const char *)sqlite3_column_text(stmt, 25);
        const char *handleAddr = (const char *)sqlite3_column_text(stmt, 26);

        msg[@"rowid"] = @(rowid);
        if (guid) msg[@"guid"] = [NSString stringWithUTF8String:guid];
        if (text) msg[@"text"] = [NSString stringWithUTF8String:text];
        msg[@"date"] = dateFromChatDB(date) ?: [NSNull null];
        msg[@"is_from_me"] = @(isFromMe);
        msg[@"has_attachments"] = @(hasAttach);
        msg[@"associated_message_type"] = @(assocType);
        if (assocGuid) msg[@"associated_message_guid"] = [NSString stringWithUTF8String:assocGuid];
        if (subject) msg[@"subject"] = [NSString stringWithUTF8String:subject];
        msg[@"date_read"] = dateFromChatDB(dateRead) ?: [NSNull null];
        msg[@"date_delivered"] = dateFromChatDB(dateDelivered) ?: [NSNull null];
        msg[@"is_read"] = @(isRead);
        msg[@"is_sent"] = @(isSent);
        msg[@"is_delivered"] = @(isDelivered);
        msg[@"date_edited"] = dateFromChatDB(dateEdited) ?: [NSNull null];
        msg[@"date_retracted"] = dateFromChatDB(dateRetracted) ?: [NSNull null];
        msg[@"item_type"] = @(itemType);
        if (groupTitle) msg[@"group_title"] = [NSString stringWithUTF8String:groupTitle];
        msg[@"group_action_type"] = @(groupAction);
        if (svc) msg[@"service"] = [NSString stringWithUTF8String:svc];
        msg[@"error"] = @(error);
        if (effect) msg[@"effect"] = [NSString stringWithUTF8String:effect];
        if (threadGuid) msg[@"thread_originator_guid"] = [NSString stringWithUTF8String:threadGuid];
        if (replyGuid) msg[@"reply_to_guid"] = [NSString stringWithUTF8String:replyGuid];
        if (emoji) msg[@"associated_emoji"] = [NSString stringWithUTF8String:emoji];
        if (handleAddr) msg[@"sender"] = [NSString stringWithUTF8String:handleAddr];

        [messages addObject:msg];
    }
    sqlite3_finalize(stmt);

    // When DESC (default), reverse for chronological display
    NSArray *chrono = sortAsc ? messages :
        [[messages reverseObjectEnumerator] allObjects];

    if (jsonOutput) {
        printf("[\n");
        for (NSUInteger i = 0; i < chrono.count; i++) {
            NSDictionary *msg = chrono[i];
            if (i > 0) printf(",\n");
            printf("  {\n");
            printf("    \"guid\": \"%s\",\n",
                   [jsonEscapeString(msg[@"guid"] ?: @"") UTF8String]);
            printf("    \"text\": \"%s\",\n",
                   [jsonEscapeString(msg[@"text"] ?: @"") UTF8String]);
            NSDate *d = msg[@"date"];
            printf("    \"date\": \"%s\",\n",
                   (d && ![d isEqual:[NSNull null]]) ? [isoDateString(d) UTF8String] : "");
            printf("    \"is_from_me\": %s,\n",
                   [msg[@"is_from_me"] boolValue] ? "true" : "false");
            printf("    \"sender\": \"%s\",\n",
                   [jsonEscapeString(msg[@"sender"] ?: @"Me") UTF8String]);
            printf("    \"has_attachments\": %s,\n",
                   [msg[@"has_attachments"] boolValue] ? "true" : "false");
            printf("    \"is_read\": %s,\n",
                   [msg[@"is_read"] boolValue] ? "true" : "false");
            printf("    \"is_delivered\": %s,\n",
                   [msg[@"is_delivered"] boolValue] ? "true" : "false");
            printf("    \"service\": \"%s\",\n",
                   [jsonEscapeString(msg[@"service"] ?: @"") UTF8String]);
            printf("    \"error\": %d,\n", [msg[@"error"] intValue]);
            if (msg[@"subject"])
                printf("    \"subject\": \"%s\",\n",
                       [jsonEscapeString(msg[@"subject"]) UTF8String]);
            if (msg[@"thread_originator_guid"])
                printf("    \"thread_originator_guid\": \"%s\",\n",
                       [jsonEscapeString(msg[@"thread_originator_guid"]) UTF8String]);
            if (msg[@"associated_emoji"])
                printf("    \"associated_emoji\": \"%s\",\n",
                       [jsonEscapeString(msg[@"associated_emoji"]) UTF8String]);
            printf("    \"associated_message_type\": %d\n",
                   [msg[@"associated_message_type"] intValue]);
            printf("  }");
        }
        printf("\n]\n");
    } else {
        printf("Chat: %s  (%lu messages)\n\n",
               [chatGUID UTF8String], (unsigned long)chrono.count);

        for (NSDictionary *msg in chrono) {
            int assocType = [msg[@"associated_message_type"] intValue];
            int itemType = [msg[@"item_type"] intValue];

            // System/group events
            if (itemType == 1) {
                NSString *groupTitle = msg[@"group_title"];
                if (groupTitle) {
                    NSDate *d = msg[@"date"];
                    printf("  --- Group renamed to \"%s\" (%s) ---\n",
                           [groupTitle UTF8String],
                           (d && ![d isEqual:[NSNull null]]) ?
                               [formatMsgDateShort(d) UTF8String] : "");
                }
                continue;
            }
            if (itemType == 3) {
                printf("  --- Participant change ---\n");
                continue;
            }

            // Tapback/reaction
            if (assocType >= 2000 && assocType < 4000) {
                NSString *reactEmoji = msg[@"associated_emoji"];
                NSString *sender = [msg[@"is_from_me"] boolValue] ?
                    @"You" : (msg[@"sender"] ?: @"?");
                const char *tapback = "";
                switch (assocType) {
                    case 2000: tapback = "♥️"; break;  // love
                    case 2001: tapback = "👍"; break;  // like
                    case 2002: tapback = "👎"; break;  // dislike
                    case 2003: tapback = "😂"; break;  // laugh
                    case 2004: tapback = "‼️"; break;  // emphasize
                    case 2005: tapback = "❓"; break;  // question
                    case 3000: tapback = "-♥️"; break; // remove love
                    case 3001: tapback = "-👍"; break;
                    case 3002: tapback = "-👎"; break;
                    case 3003: tapback = "-😂"; break;
                    case 3004: tapback = "-‼️"; break;
                    case 3005: tapback = "-❓"; break;
                    default: break;
                }
                if (reactEmoji) {
                    printf("  %s reacted %s\n",
                           [sender UTF8String],
                           [reactEmoji UTF8String]);
                } else if (strlen(tapback) > 0) {
                    printf("  %s reacted %s\n", [sender UTF8String], tapback);
                }
                continue;
            }

            // Regular message
            BOOL fromMe = [msg[@"is_from_me"] boolValue];
            NSDate *d = msg[@"date"];
            NSString *text = displayMsgText(msg[@"text"], [msg[@"has_attachments"] boolValue], [msg[@"rowid"] longLongValue]);
            NSString *sender = fromMe ? @"You" : (msg[@"sender"] ?: @"?");
            BOOL hasAttach = [msg[@"has_attachments"] boolValue];

            // Retracted
            if (msg[@"date_retracted"] && ![msg[@"date_retracted"] isEqual:[NSNull null]]) {
                printf("  [%s] %s: (unsent)\n",
                       (d && ![d isEqual:[NSNull null]]) ?
                           [formatMsgDateShort(d) UTF8String] : "",
                       [sender UTF8String]);
                continue;
            }

            // Edited indicator
            BOOL edited = msg[@"date_edited"] && ![msg[@"date_edited"] isEqual:[NSNull null]];

            {
                NSString *suffix = [NSString stringWithFormat:@"%s%s",
                    hasAttach ? " 📎" : "", edited ? " (edited)" : ""];
                NSString *body = [text stringByAppendingString:suffix];
                NSString *prefix = [NSString stringWithFormat:@"  [%s] %s: ",
                    (d && ![d isEqual:[NSNull null]]) ?
                        [formatMsgDateShort(d) UTF8String] : "",
                    [sender UTF8String]];
                printHanging([prefix UTF8String], [body UTF8String]);
            }
        }
        printf("\n");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// msg context — show messages around a specific message in its conversation
// ─────────────────────────────────────────────────────────────────────────────

void cmdMsgContext(const char *msgGuid, NSUInteger context, BOOL jsonOutput,
                   const char *direction) {
    if (!openMessagesDB()) return;

    if (!context) context = 10;

    // 1. Find the target message's ROWID and its chat
    //    Accepts full GUID or partial (prefix match, min 8 chars)
    NSString *guidStr = [NSString stringWithUTF8String:msgGuid];
    const char *lookupSql;
    if ([guidStr length] < 36) {
        // Partial GUID — prefix match
        lookupSql =
            "SELECT m.ROWID, m.date, c.guid as chat_guid, c.chat_identifier, "
            "c.display_name, c.service_name "
            "FROM message m "
            "JOIN chat_message_join cmj ON cmj.message_id = m.ROWID "
            "JOIN chat c ON c.ROWID = cmj.chat_id "
            "WHERE m.guid LIKE ? LIMIT 1";
    } else {
        lookupSql =
            "SELECT m.ROWID, m.date, c.guid as chat_guid, c.chat_identifier, "
            "c.display_name, c.service_name "
            "FROM message m "
            "JOIN chat_message_join cmj ON cmj.message_id = m.ROWID "
            "JOIN chat c ON c.ROWID = cmj.chat_id "
            "WHERE m.guid = ?";
    }

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(g_msgDB, lookupSql, -1, &stmt, NULL) != SQLITE_OK) {
        fprintf(stderr, "Query failed: %s\n", sqlite3_errmsg(g_msgDB));
        return;
    }
    if ([guidStr length] < 36) {
        NSString *pattern = [NSString stringWithFormat:@"%@%%", guidStr];
        sqlite3_bind_text(stmt, 1, [pattern UTF8String], -1, SQLITE_STATIC);
    } else {
        sqlite3_bind_text(stmt, 1, msgGuid, -1, SQLITE_STATIC);
    }

    if (sqlite3_step(stmt) != SQLITE_ROW) {
        fprintf(stderr, "Message not found: %s\n", msgGuid);
        sqlite3_finalize(stmt);
        return;
    }

    int64_t targetRowid = sqlite3_column_int64(stmt, 0);
    int64_t targetDate = sqlite3_column_int64(stmt, 1);
    NSString *chatGuid = [NSString stringWithUTF8String:
        (const char *)sqlite3_column_text(stmt, 2)];
    const char *_chatIdent = (const char *)sqlite3_column_text(stmt, 3);
    const char *_displayName = (const char *)sqlite3_column_text(stmt, 4);
    NSString *chatName = (_displayName && strlen(_displayName) > 0) ?
        [NSString stringWithUTF8String:_displayName] :
        (_chatIdent ? [NSString stringWithUTF8String:_chatIdent] : chatGuid);
    sqlite3_finalize(stmt);

    // 2. Build query based on direction
    //    "before" = older messages, "after" = newer messages, default = both
    NSString *sql;
    BOOL showBefore = !direction || strcmp(direction, "before") == 0;
    BOOL showAfter = !direction || strcmp(direction, "after") == 0;

    if (direction && strcmp(direction, "before") == 0) {
        // Only older messages
        sql = [NSString stringWithFormat:
            @"SELECT m.ROWID, m.guid, m.text, m.date, m.is_from_me, "
            @"m.cache_has_attachments, m.associated_message_type, "
            @"m.date_edited, m.date_retracted, m.item_type, "
            @"m.group_title, m.associated_message_emoji, "
            @"h.id as handle_address "
            @"FROM message m "
            @"JOIN chat_message_join cmj ON cmj.message_id = m.ROWID "
            @"JOIN chat c ON c.ROWID = cmj.chat_id "
            @"LEFT JOIN handle h ON h.ROWID = m.handle_id "
            @"WHERE c.guid = ? AND m.date < %lld "
            @"ORDER BY m.date DESC LIMIT %lu",
            targetDate, (unsigned long)context];
    } else if (direction && strcmp(direction, "after") == 0) {
        // Only newer messages
        sql = [NSString stringWithFormat:
            @"SELECT m.ROWID, m.guid, m.text, m.date, m.is_from_me, "
            @"m.cache_has_attachments, m.associated_message_type, "
            @"m.date_edited, m.date_retracted, m.item_type, "
            @"m.group_title, m.associated_message_emoji, "
            @"h.id as handle_address "
            @"FROM message m "
            @"JOIN chat_message_join cmj ON cmj.message_id = m.ROWID "
            @"JOIN chat c ON c.ROWID = cmj.chat_id "
            @"LEFT JOIN handle h ON h.ROWID = m.handle_id "
            @"WHERE c.guid = ? AND m.date > %lld "
            @"ORDER BY m.date ASC LIMIT %lu",
            targetDate, (unsigned long)context];
    } else {
        // Both directions — union of before + target + after
        sql = [NSString stringWithFormat:
            @"SELECT * FROM ("
            @"  SELECT m.ROWID, m.guid, m.text, m.date, m.is_from_me, "
            @"  m.cache_has_attachments, m.associated_message_type, "
            @"  m.date_edited, m.date_retracted, m.item_type, "
            @"  m.group_title, m.associated_message_emoji, "
            @"  h.id as handle_address "
            @"  FROM message m "
            @"  JOIN chat_message_join cmj ON cmj.message_id = m.ROWID "
            @"  JOIN chat c ON c.ROWID = cmj.chat_id "
            @"  LEFT JOIN handle h ON h.ROWID = m.handle_id "
            @"  WHERE c.guid = ? AND m.date <= %lld "
            @"  ORDER BY m.date DESC LIMIT %lu"
            @") "
            @"UNION ALL "
            @"SELECT * FROM ("
            @"  SELECT m.ROWID, m.guid, m.text, m.date, m.is_from_me, "
            @"  m.cache_has_attachments, m.associated_message_type, "
            @"  m.date_edited, m.date_retracted, m.item_type, "
            @"  m.group_title, m.associated_message_emoji, "
            @"  h.id as handle_address "
            @"  FROM message m "
            @"  JOIN chat_message_join cmj ON cmj.message_id = m.ROWID "
            @"  JOIN chat c ON c.ROWID = cmj.chat_id "
            @"  LEFT JOIN handle h ON h.ROWID = m.handle_id "
            @"  WHERE c.guid = ? AND m.date > %lld "
            @"  ORDER BY m.date ASC LIMIT %lu"
            @") ORDER BY date ASC",
            targetDate, (unsigned long)(context + 1),
            targetDate, (unsigned long)context];
    }

    if (sqlite3_prepare_v2(g_msgDB, [sql UTF8String], -1, &stmt, NULL) != SQLITE_OK) {
        fprintf(stderr, "Query failed: %s\n", sqlite3_errmsg(g_msgDB));
        return;
    }

    // Bind chat_guid — once for single-direction, twice for both
    sqlite3_bind_text(stmt, 1, [chatGuid UTF8String], -1, SQLITE_STATIC);
    if (!direction) {
        sqlite3_bind_text(stmt, 2, [chatGuid UTF8String], -1, SQLITE_STATIC);
    }

    // Collect results
    NSMutableArray *rows = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        NSMutableDictionary *r = [NSMutableDictionary dictionary];
        int64_t rowid = sqlite3_column_int64(stmt, 0);
        const char *guid = (const char *)sqlite3_column_text(stmt, 1);
        const char *text = (const char *)sqlite3_column_text(stmt, 2);
        int64_t date = sqlite3_column_int64(stmt, 3);
        int isFromMe = sqlite3_column_int(stmt, 4);
        int hasAttach = sqlite3_column_int(stmt, 5);
        int assocType = sqlite3_column_int(stmt, 6);
        int64_t dateEdited = sqlite3_column_int64(stmt, 7);
        int64_t dateRetracted = sqlite3_column_int64(stmt, 8);
        int itemType = sqlite3_column_int(stmt, 9);
        const char *groupTitle = (const char *)sqlite3_column_text(stmt, 10);
        const char *emoji = (const char *)sqlite3_column_text(stmt, 11);
        const char *handle = (const char *)sqlite3_column_text(stmt, 12);

        r[@"rowid"] = @(rowid);
        if (guid) r[@"guid"] = [NSString stringWithUTF8String:guid];
        if (text) r[@"text"] = [NSString stringWithUTF8String:text];
        r[@"date"] = dateFromChatDB(date) ?: [NSNull null];
        r[@"is_from_me"] = @(isFromMe);
        r[@"has_attachments"] = @(hasAttach);
        r[@"associated_message_type"] = @(assocType);
        r[@"date_edited"] = dateFromChatDB(dateEdited) ?: [NSNull null];
        r[@"date_retracted"] = dateFromChatDB(dateRetracted) ?: [NSNull null];
        r[@"item_type"] = @(itemType);
        if (groupTitle) r[@"group_title"] = [NSString stringWithUTF8String:groupTitle];
        if (emoji) r[@"associated_emoji"] = [NSString stringWithUTF8String:emoji];
        if (handle) r[@"sender"] = [NSString stringWithUTF8String:handle];
        r[@"is_target"] = @(rowid == targetRowid);

        [rows addObject:r];
    }
    sqlite3_finalize(stmt);

    // Sort by date for display (before-only results come in DESC)
    if (direction && strcmp(direction, "before") == 0) {
        rows = [[[[rows reverseObjectEnumerator] allObjects] mutableCopy] mutableCopy];
    }

    if (jsonOutput) {
        printf("{\n");
        printf("  \"chat\": \"%s\",\n", [jsonEscapeString(chatGuid) UTF8String]);
        printf("  \"chat_name\": \"%s\",\n", [jsonEscapeString(chatName) UTF8String]);
        printf("  \"target_guid\": \"%s\",\n", msgGuid);
        printf("  \"messages\": [\n");
        for (NSUInteger i = 0; i < rows.count; i++) {
            NSDictionary *r = rows[i];
            if (i > 0) printf(",\n");
            NSDate *d = r[@"date"];
            printf("    {\n");
            printf("      \"guid\": \"%s\",\n",
                   [jsonEscapeString(r[@"guid"] ?: @"") UTF8String]);
            printf("      \"text\": \"%s\",\n",
                   [jsonEscapeString(r[@"text"] ?: @"") UTF8String]);
            printf("      \"date\": \"%s\",\n",
                   (d && ![d isEqual:[NSNull null]]) ? [isoDateString(d) UTF8String] : "");
            printf("      \"is_from_me\": %s,\n",
                   [r[@"is_from_me"] boolValue] ? "true" : "false");
            printf("      \"sender\": \"%s\",\n",
                   [jsonEscapeString(r[@"sender"] ?: @"Me") UTF8String]);
            printf("      \"is_target\": %s\n",
                   [r[@"is_target"] boolValue] ? "true" : "false");
            printf("    }");
        }
        printf("\n  ]\n");
        printf("}\n");
    } else {
        printf("Chat: %s\n", [chatName UTF8String]);
        if (showBefore && rows.count > 0) {
            NSDictionary *first = rows[0];
            printf("  ↑ use --before for older messages (guid: %s)\n",
                   [first[@"guid"] UTF8String]);
        }
        printf("\n");

        for (NSDictionary *r in rows) {
            BOOL isTarget = [r[@"is_target"] boolValue];
            int assocType = [r[@"associated_message_type"] intValue];
            int itemType = [r[@"item_type"] intValue];

            // Skip system/group events for brevity
            if (itemType == 1 || itemType == 3) continue;

            // Skip tapbacks
            if (assocType >= 2000 && assocType < 4000) continue;

            BOOL fromMe = [r[@"is_from_me"] boolValue];
            NSDate *d = r[@"date"];
            NSString *text = displayMsgText(r[@"text"], [r[@"has_attachments"] boolValue], [r[@"rowid"] longLongValue]);
            NSString *sender = fromMe ? @"You" : (r[@"sender"] ?: @"?");
            BOOL hasAttach = [r[@"has_attachments"] boolValue];
            BOOL retracted = r[@"date_retracted"] && ![r[@"date_retracted"] isEqual:[NSNull null]];
            BOOL edited = r[@"date_edited"] && ![r[@"date_edited"] isEqual:[NSNull null]];

            if (retracted) text = @"(unsent)";

            {
                NSString *suffix = [NSString stringWithFormat:@"%s%s",
                    hasAttach ? " 📎" : "", edited ? " (edited)" : ""];
                NSString *body = [text stringByAppendingString:suffix];
                NSString *prefix = [NSString stringWithFormat:@"%s  [%s] %s: ",
                    isTarget ? ">>>" : "   ",
                    (d && ![d isEqual:[NSNull null]]) ?
                        [formatMsgDateShort(d) UTF8String] : "",
                    [sender UTF8String]];
                printHanging([prefix UTF8String], [body UTF8String]);
            }
        }

        printf("\n");
        if (showAfter && rows.count > 0) {
            NSDictionary *last = rows[rows.count - 1];
            printf("  ↓ use --after for newer messages (guid: %s)\n",
                   [last[@"guid"] UTF8String]);
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// msg search — search messages
// ─────────────────────────────────────────────────────────────────────────────

void cmdMsgSearch(NSString *query, NSUInteger limit, BOOL jsonOutput,
                  BOOL sortAsc, BOOL fzfOutput) {
    if (!openMessagesDB()) return;

    NSString *sql = [NSString stringWithFormat:
        @"SELECT m.ROWID, m.guid, m.text, m.date, m.is_from_me, "
        @"m.cache_has_attachments, h.id as handle_address, c.guid as chat_guid, "
        @"c.chat_identifier, c.display_name, c.service_name "
        @"FROM message m "
        @"JOIN chat_message_join cmj ON cmj.message_id = m.ROWID "
        @"JOIN chat c ON c.ROWID = cmj.chat_id "
        @"LEFT JOIN handle h ON h.ROWID = m.handle_id "
        @"WHERE m.text LIKE ? "
        @"ORDER BY m.date %@ "
        @"LIMIT ?", sortAsc ? @"ASC" : @"DESC"];

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(g_msgDB, [sql UTF8String], -1, &stmt, NULL) != SQLITE_OK) {
        fprintf(stderr, "Query failed: %s\n", sqlite3_errmsg(g_msgDB));
        return;
    }

    NSString *pattern = [NSString stringWithFormat:@"%%%@%%", query];
    sqlite3_bind_text(stmt, 1, [pattern UTF8String], -1, SQLITE_STATIC);
    sqlite3_bind_int(stmt, 2, limit > 0 ? (int)limit : 50);

    if (fzfOutput) {
        // Tab-delimited: GUID<tab>display line
        // Pipe to fzf, then: cut -f1 to get the GUID
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            int64_t rowid = sqlite3_column_int64(stmt, 0);
            const char *guid = (const char *)sqlite3_column_text(stmt, 1);
            const char *text = (const char *)sqlite3_column_text(stmt, 2);
            int64_t date = sqlite3_column_int64(stmt, 3);
            int isFromMe = sqlite3_column_int(stmt, 4);
            int hasAttach = sqlite3_column_int(stmt, 5);
            const char *handle = (const char *)sqlite3_column_text(stmt, 6);
            const char *chatIdent = (const char *)sqlite3_column_text(stmt, 8);
            const char *displayName = (const char *)sqlite3_column_text(stmt, 9);

            NSDate *d = dateFromChatDB(date);
            NSString *sender = isFromMe ? @"You" :
                (handle ? [NSString stringWithUTF8String:handle] : @"?");
            NSString *chatName = (displayName && strlen(displayName) > 0) ?
                [NSString stringWithUTF8String:displayName] :
                (chatIdent ? [NSString stringWithUTF8String:chatIdent] : @"?");
            NSString *msgText = displayMsgText(text ?
                [NSString stringWithUTF8String:text] : nil, hasAttach, rowid);
            if (msgText.length == 0) msgText = @"(no text)";
            msgText = [msgText stringByReplacingOccurrencesOfString:@"\n"
                                                        withString:@" "];
            msgText = truncStr(msgText, 80);

            printf("%s\t[%s] %s → %s: %s\n",
                   guid ?: "",
                   [formatMsgDateShort(d) UTF8String],
                   [truncStr(chatName, 20) UTF8String],
                   [truncStr(sender, 15) UTF8String],
                   [msgText UTF8String]);
        }
        sqlite3_finalize(stmt);
        return;
    }

    if (jsonOutput) {
        printf("[\n");
        int idx = 0;
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            if (idx > 0) printf(",\n");
            int64_t rowid = sqlite3_column_int64(stmt, 0);
            const char *guid = (const char *)sqlite3_column_text(stmt, 1);
            const char *text = (const char *)sqlite3_column_text(stmt, 2);
            int64_t date = sqlite3_column_int64(stmt, 3);
            int isFromMe = sqlite3_column_int(stmt, 4);
            int hasAttach = sqlite3_column_int(stmt, 5);
            const char *handle = (const char *)sqlite3_column_text(stmt, 6);
            const char *chatGuid = (const char *)sqlite3_column_text(stmt, 7);
            const char *chatIdent = (const char *)sqlite3_column_text(stmt, 8);
            const char *displayName = (const char *)sqlite3_column_text(stmt, 9);

            NSDate *d = dateFromChatDB(date);
            NSString *msgText = displayMsgText(text ?
                [NSString stringWithUTF8String:text] : nil, hasAttach, rowid);

            printf("  {\n");
            printf("    \"guid\": \"%s\",\n", guid ?: "");
            printf("    \"text\": \"%s\",\n",
                   [jsonEscapeString(msgText) UTF8String]);
            printf("    \"date\": \"%s\",\n",
                   d ? [isoDateString(d) UTF8String] : "");
            printf("    \"is_from_me\": %s,\n", isFromMe ? "true" : "false");
            printf("    \"sender\": \"%s\",\n",
                   isFromMe ? "Me" : (handle ?: "?"));
            printf("    \"chat_guid\": \"%s\",\n", chatGuid ?: "");
            printf("    \"chat_name\": \"%s\"\n",
                   displayName && strlen(displayName) > 0 ? displayName :
                   (chatIdent ?: ""));
            printf("  }");
            idx++;
        }
        printf("\n]\n");
    } else {
        int idx = 0;
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            int64_t rowid = sqlite3_column_int64(stmt, 0);
            const char *guid = (const char *)sqlite3_column_text(stmt, 1);
            const char *text = (const char *)sqlite3_column_text(stmt, 2);
            int64_t date = sqlite3_column_int64(stmt, 3);
            int isFromMe = sqlite3_column_int(stmt, 4);
            int hasAttach = sqlite3_column_int(stmt, 5);
            const char *handle = (const char *)sqlite3_column_text(stmt, 6);
            const char *chatIdent = (const char *)sqlite3_column_text(stmt, 8);
            const char *displayName = (const char *)sqlite3_column_text(stmt, 9);

            NSDate *d = dateFromChatDB(date);
            NSString *sender = isFromMe ? @"You" :
                (handle ? [NSString stringWithUTF8String:handle] : @"?");
            NSString *chatName = (displayName && strlen(displayName) > 0) ?
                [NSString stringWithUTF8String:displayName] :
                (chatIdent ? [NSString stringWithUTF8String:chatIdent] : @"?");
            NSString *msgText = displayMsgText(text ?
                [NSString stringWithUTF8String:text] : nil, hasAttach, rowid);
            if (msgText.length == 0) msgText = @"(no text)";
            msgText = [msgText stringByReplacingOccurrencesOfString:@"\n"
                                                        withString:@" "];
            msgText = truncStr(msgText, 60);

            printf("[%s] %s → %s: %s\n  guid: %s\n",
                   [formatMsgDateShort(d) UTF8String],
                   [truncStr(chatName, 20) UTF8String],
                   [truncStr(sender, 15) UTF8String],
                   [msgText UTF8String],
                   guid ?: "");
            idx++;
        }
        if (idx == 0) {
            printf("No messages found matching \"%s\"\n",
                   [query UTF8String]);
        } else {
            printf("\n%d messages found.\n", idx);
        }
    }

    sqlite3_finalize(stmt);
}

// ─────────────────────────────────────────────────────────────────────────────
// msg count — message statistics
// ─────────────────────────────────────────────────────────────────────────────

void cmdMsgCount(const char *chatRef, BOOL jsonOutput) {
    if (!openMessagesDB()) return;

    if (chatRef) {
        // Count for a specific chat
        NSString *chatGUID = resolveChatGUID(chatRef);
        if (!chatGUID) {
            fprintf(stderr, "Chat not found: %s\n", chatRef);
            return;
        }

        const char *sql =
            "SELECT "
            "(SELECT COUNT(*) FROM message m "
            " JOIN chat_message_join cmj ON cmj.message_id = m.ROWID "
            " JOIN chat c ON c.ROWID = cmj.chat_id WHERE c.guid = ?1), "
            "(SELECT COUNT(*) FROM message m "
            " JOIN chat_message_join cmj ON cmj.message_id = m.ROWID "
            " JOIN chat c ON c.ROWID = cmj.chat_id "
            " WHERE c.guid = ?1 AND m.is_from_me = 1), "
            "(SELECT COUNT(*) FROM message m "
            " JOIN chat_message_join cmj ON cmj.message_id = m.ROWID "
            " JOIN chat c ON c.ROWID = cmj.chat_id "
            " WHERE c.guid = ?1 AND m.cache_has_attachments = 1)";

        sqlite3_stmt *stmt;
        if (sqlite3_prepare_v2(g_msgDB, sql, -1, &stmt, NULL) != SQLITE_OK) {
            fprintf(stderr, "Query failed: %s\n", sqlite3_errmsg(g_msgDB));
            return;
        }
        sqlite3_bind_text(stmt, 1, [chatGUID UTF8String], -1, SQLITE_STATIC);

        if (sqlite3_step(stmt) == SQLITE_ROW) {
            int total = sqlite3_column_int(stmt, 0);
            int fromMe = sqlite3_column_int(stmt, 1);
            int withAttach = sqlite3_column_int(stmt, 2);

            if (jsonOutput) {
                printf("{\n");
                printf("  \"chat\": \"%s\",\n", [chatGUID UTF8String]);
                printf("  \"total\": %d,\n", total);
                printf("  \"from_me\": %d,\n", fromMe);
                printf("  \"from_them\": %d,\n", total - fromMe);
                printf("  \"with_attachments\": %d\n", withAttach);
                printf("}\n");
            } else {
                printf("Chat: %s\n", [chatGUID UTF8String]);
                printf("  Total messages:     %d\n", total);
                printf("  From me:            %d\n", fromMe);
                printf("  From them:          %d\n", total - fromMe);
                printf("  With attachments:   %d\n", withAttach);
            }
        }
        sqlite3_finalize(stmt);
    } else {
        // Global statistics
        const char *sql =
            "SELECT "
            "(SELECT COUNT(*) FROM message), "
            "(SELECT COUNT(*) FROM chat), "
            "(SELECT COUNT(*) FROM handle), "
            "(SELECT COUNT(*) FROM attachment), "
            "(SELECT COUNT(*) FROM message WHERE is_from_me = 1), "
            "(SELECT COUNT(*) FROM message WHERE is_from_me = 0), "
            "(SELECT COUNT(*) FROM chat WHERE service_name = 'iMessage'), "
            "(SELECT COUNT(*) FROM chat WHERE service_name = 'SMS')";

        sqlite3_stmt *stmt;
        if (sqlite3_prepare_v2(g_msgDB, sql, -1, &stmt, NULL) != SQLITE_OK) {
            fprintf(stderr, "Query failed: %s\n", sqlite3_errmsg(g_msgDB));
            return;
        }

        if (sqlite3_step(stmt) == SQLITE_ROW) {
            int msgs = sqlite3_column_int(stmt, 0);
            int chats = sqlite3_column_int(stmt, 1);
            int handles = sqlite3_column_int(stmt, 2);
            int attachments = sqlite3_column_int(stmt, 3);
            int fromMe = sqlite3_column_int(stmt, 4);
            int fromOthers = sqlite3_column_int(stmt, 5);
            int iMsgChats = sqlite3_column_int(stmt, 6);
            int smsChats = sqlite3_column_int(stmt, 7);

            if (jsonOutput) {
                printf("{\n");
                printf("  \"messages\": %d,\n", msgs);
                printf("  \"chats\": %d,\n", chats);
                printf("  \"handles\": %d,\n", handles);
                printf("  \"attachments\": %d,\n", attachments);
                printf("  \"sent\": %d,\n", fromMe);
                printf("  \"received\": %d,\n", fromOthers);
                printf("  \"imessage_chats\": %d,\n", iMsgChats);
                printf("  \"sms_chats\": %d\n", smsChats);
                printf("}\n");
            } else {
                printf("Messages database statistics:\n");
                printf("  Total messages:     %d\n", msgs);
                printf("  Sent:               %d\n", fromMe);
                printf("  Received:           %d\n", fromOthers);
                printf("  Conversations:      %d\n", chats);
                printf("    iMessage:         %d\n", iMsgChats);
                printf("    SMS:              %d\n", smsChats);
                printf("  Contacts:           %d\n", handles);
                printf("  Attachments:        %d\n", attachments);
            }
        }
        sqlite3_finalize(stmt);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// msg contacts — list handles/contacts
// ─────────────────────────────────────────────────────────────────────────────

void cmdMsgContacts(NSUInteger limit, BOOL jsonOutput, NSString *service) {
    if (!openMessagesDB()) return;

    NSMutableString *sql = [NSMutableString stringWithString:
        @"SELECT h.ROWID, h.id, h.service, h.country, "
        @"(SELECT COUNT(*) FROM message m WHERE m.handle_id = h.ROWID) as msg_count, "
        @"(SELECT MAX(m2.date) FROM message m2 WHERE m2.handle_id = h.ROWID) as last_date "
        @"FROM handle h "];

    if (service) {
        [sql appendFormat:@"WHERE h.service = '%@' "
         @"AND (SELECT COUNT(*) FROM message m WHERE m.handle_id = h.ROWID) > 0 ",
         service];
    } else {
        [sql appendString:@"WHERE (SELECT COUNT(*) FROM message m WHERE m.handle_id = h.ROWID) > 0 "];
    }
    [sql appendString:@"ORDER BY last_date DESC "];

    if (limit > 0) {
        [sql appendFormat:@"LIMIT %lu", (unsigned long)limit];
    } else {
        [sql appendString:@"LIMIT 100"];
    }

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(g_msgDB, [sql UTF8String], -1, &stmt, NULL) != SQLITE_OK) {
        fprintf(stderr, "Query failed: %s\n", sqlite3_errmsg(g_msgDB));
        return;
    }

    if (jsonOutput) {
        printf("[\n");
        int idx = 0;
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            if (idx > 0) printf(",\n");
            int64_t rowid = sqlite3_column_int64(stmt, 0);
            const char *addr = (const char *)sqlite3_column_text(stmt, 1);
            const char *svc = (const char *)sqlite3_column_text(stmt, 2);
            const char *country = (const char *)sqlite3_column_text(stmt, 3);
            int msgCount = sqlite3_column_int(stmt, 4);
            int64_t lastDate = sqlite3_column_int64(stmt, 5);

            NSDate *d = dateFromChatDB(lastDate);

            printf("  {\n");
            printf("    \"id\": %lld,\n", rowid);
            printf("    \"address\": \"%s\",\n", addr ?: "");
            printf("    \"service\": \"%s\",\n", svc ?: "");
            printf("    \"country\": \"%s\",\n", country ?: "");
            printf("    \"message_count\": %d,\n", msgCount);
            printf("    \"last_message_date\": \"%s\"\n",
                   d ? [isoDateString(d) UTF8String] : "");
            printf("  }");
            idx++;
        }
        printf("\n]\n");
    } else {
        printf("%-4s  %-7s  %-30s  %-6s  %s\n",
               "#", "Service", "Address", "Msgs", "Last Active");
        printf("────  ───────  ──────────────────────────────  ──────  ────────────\n");

        int idx = 0;
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const char *addr = (const char *)sqlite3_column_text(stmt, 1);
            const char *svc = (const char *)sqlite3_column_text(stmt, 2);
            int msgCount = sqlite3_column_int(stmt, 4);
            int64_t lastDate = sqlite3_column_int64(stmt, 5);

            NSDate *d = dateFromChatDB(lastDate);

            printf("%-4d  %-7s  %-30s  %-6d  %s\n",
                   idx + 1,
                   svc ?: "?",
                   addr ?: "?",
                   msgCount,
                   [formatMsgDateShort(d) UTF8String]);
            idx++;
        }
        printf("\n%d contacts shown.\n", idx);
    }

    sqlite3_finalize(stmt);
}

// ─────────────────────────────────────────────────────────────────────────────
// msg info — chat details
// ─────────────────────────────────────────────────────────────────────────────

void cmdMsgInfo(const char *chatRef, BOOL jsonOutput) {
    if (!openMessagesDB()) return;

    NSString *chatGUID = resolveChatGUID(chatRef);
    if (!chatGUID) {
        fprintf(stderr, "Chat not found: %s\n", chatRef);
        return;
    }

    // Get chat details
    const char *sql =
        "SELECT c.ROWID, c.guid, c.chat_identifier, c.display_name, "
        "c.service_name, c.style, c.is_archived, c.last_read_message_timestamp, "
        "(SELECT COUNT(*) FROM chat_message_join WHERE chat_id = c.ROWID), "
        "(SELECT MIN(m.date) FROM message m "
        " JOIN chat_message_join cmj ON cmj.message_id = m.ROWID "
        " WHERE cmj.chat_id = c.ROWID), "
        "(SELECT MAX(m.date) FROM message m "
        " JOIN chat_message_join cmj ON cmj.message_id = m.ROWID "
        " WHERE cmj.chat_id = c.ROWID), "
        "(SELECT COUNT(*) FROM message m "
        " JOIN chat_message_join cmj ON cmj.message_id = m.ROWID "
        " WHERE cmj.chat_id = c.ROWID AND m.cache_has_attachments = 1) "
        "FROM chat c WHERE c.guid = ?";

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(g_msgDB, sql, -1, &stmt, NULL) != SQLITE_OK) {
        fprintf(stderr, "Query failed: %s\n", sqlite3_errmsg(g_msgDB));
        return;
    }
    sqlite3_bind_text(stmt, 1, [chatGUID UTF8String], -1, SQLITE_STATIC);

    if (sqlite3_step(stmt) != SQLITE_ROW) {
        fprintf(stderr, "Chat not found: %s\n", chatRef);
        sqlite3_finalize(stmt);
        return;
    }

    int64_t rowid = sqlite3_column_int64(stmt, 0);
    const char *_guid = (const char *)sqlite3_column_text(stmt, 1);
    const char *_chatIdent = (const char *)sqlite3_column_text(stmt, 2);
    const char *_displayName = (const char *)sqlite3_column_text(stmt, 3);
    const char *_svc = (const char *)sqlite3_column_text(stmt, 4);
    int style = sqlite3_column_int(stmt, 5);
    int isArchived = sqlite3_column_int(stmt, 6);
    int msgCount = sqlite3_column_int(stmt, 8);
    int64_t firstDate = sqlite3_column_int64(stmt, 9);
    int64_t lastDate = sqlite3_column_int64(stmt, 10);
    int attachCount = sqlite3_column_int(stmt, 11);

    // Copy strings before finalize invalidates them
    NSString *guidStr = _guid ? [NSString stringWithUTF8String:_guid] : @"";
    NSString *chatIdentStr = _chatIdent ? [NSString stringWithUTF8String:_chatIdent] : @"";
    NSString *displayNameStr = _displayName ? [NSString stringWithUTF8String:_displayName] : @"";
    NSString *svcStr = _svc ? [NSString stringWithUTF8String:_svc] : @"";

    NSDate *first = dateFromChatDB(firstDate);
    NSDate *last = dateFromChatDB(lastDate);
    BOOL isGroup = (style == 43);

    sqlite3_finalize(stmt);

    // Get participants
    NSMutableArray *participants = [NSMutableArray array];
    sql = "SELECT h.id, h.service FROM handle h "
          "JOIN chat_handle_join chj ON chj.handle_id = h.ROWID "
          "WHERE chj.chat_id = ?";
    if (sqlite3_prepare_v2(g_msgDB, sql, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_int64(stmt, 1, rowid);
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const char *addr = (const char *)sqlite3_column_text(stmt, 0);
            const char *psvc = (const char *)sqlite3_column_text(stmt, 1);
            if (addr) {
                [participants addObject:@{
                    @"address": [NSString stringWithUTF8String:addr],
                    @"service": psvc ? [NSString stringWithUTF8String:psvc] : @""
                }];
            }
        }
        sqlite3_finalize(stmt);
    }

    NSString *name = displayNameStr.length > 0 ? displayNameStr :
                     (chatIdentStr.length > 0 ? chatIdentStr : guidStr);

    if (jsonOutput) {
        printf("{\n");
        printf("  \"guid\": \"%s\",\n", [jsonEscapeString(guidStr) UTF8String]);
        printf("  \"chat_identifier\": \"%s\",\n", [jsonEscapeString(chatIdentStr) UTF8String]);
        printf("  \"display_name\": \"%s\",\n",
               [jsonEscapeString(name) UTF8String]);
        printf("  \"service\": \"%s\",\n", [svcStr UTF8String]);
        printf("  \"is_group\": %s,\n", isGroup ? "true" : "false");
        printf("  \"is_archived\": %s,\n", isArchived ? "true" : "false");
        printf("  \"message_count\": %d,\n", msgCount);
        printf("  \"attachment_count\": %d,\n", attachCount);
        printf("  \"first_message\": \"%s\",\n",
               first ? [isoDateString(first) UTF8String] : "");
        printf("  \"last_message\": \"%s\",\n",
               last ? [isoDateString(last) UTF8String] : "");
        printf("  \"participants\": [\n");
        for (NSUInteger i = 0; i < participants.count; i++) {
            NSDictionary *p = participants[i];
            printf("    {\"address\": \"%s\", \"service\": \"%s\"}%s\n",
                   [jsonEscapeString(p[@"address"]) UTF8String],
                   [p[@"service"] UTF8String],
                   (i < participants.count - 1) ? "," : "");
        }
        printf("  ]\n");
        printf("}\n");
    } else {
        printf("Chat: %s\n", [name UTF8String]);
        printf("  GUID:              %s\n", [guidStr UTF8String]);
        printf("  Service:           %s\n", [svcStr UTF8String]);
        printf("  Type:              %s\n", isGroup ? "Group" : "Direct");
        printf("  Archived:          %s\n", isArchived ? "Yes" : "No");
        printf("  Messages:          %d\n", msgCount);
        printf("  Attachments:       %d\n", attachCount);
        printf("  First message:     %s\n",
               first ? [formatMsgDate(first) UTF8String] : "N/A");
        printf("  Last message:      %s\n",
               last ? [formatMsgDate(last) UTF8String] : "N/A");
        printf("  Participants:      %lu\n", (unsigned long)participants.count);
        for (NSDictionary *p in participants) {
            printf("    - %s (%s)\n",
                   [p[@"address"] UTF8String],
                   [p[@"service"] UTF8String]);
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// msg attachments — list attachments in a chat
// ─────────────────────────────────────────────────────────────────────────────

void cmdMsgAttachments(const char *chatRef, NSUInteger limit, BOOL jsonOutput) {
    if (!openMessagesDB()) return;

    NSString *chatGUID = resolveChatGUID(chatRef);
    if (!chatGUID) {
        fprintf(stderr, "Chat not found: %s\n", chatRef);
        return;
    }

    const char *sql =
        "SELECT a.ROWID, a.guid, a.filename, a.mime_type, a.total_bytes, "
        "a.transfer_name, a.created_date, a.is_outgoing, a.uti "
        "FROM attachment a "
        "JOIN message_attachment_join maj ON maj.attachment_id = a.ROWID "
        "JOIN message m ON m.ROWID = maj.message_id "
        "JOIN chat_message_join cmj ON cmj.message_id = m.ROWID "
        "JOIN chat c ON c.ROWID = cmj.chat_id "
        "WHERE c.guid = ? "
        "ORDER BY a.created_date DESC "
        "LIMIT ?";

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(g_msgDB, sql, -1, &stmt, NULL) != SQLITE_OK) {
        fprintf(stderr, "Query failed: %s\n", sqlite3_errmsg(g_msgDB));
        return;
    }
    sqlite3_bind_text(stmt, 1, [chatGUID UTF8String], -1, SQLITE_STATIC);
    sqlite3_bind_int(stmt, 2, limit > 0 ? (int)limit : 50);

    if (jsonOutput) {
        printf("[\n");
        int idx = 0;
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            if (idx > 0) printf(",\n");
            const char *aguid = (const char *)sqlite3_column_text(stmt, 1);
            const char *fname = (const char *)sqlite3_column_text(stmt, 2);
            const char *mime = (const char *)sqlite3_column_text(stmt, 3);
            int64_t bytes = sqlite3_column_int64(stmt, 4);
            const char *tname = (const char *)sqlite3_column_text(stmt, 5);
            int64_t created = sqlite3_column_int64(stmt, 6);
            int outgoing = sqlite3_column_int(stmt, 7);
            const char *uti = (const char *)sqlite3_column_text(stmt, 8);

            NSDate *d = dateFromChatDB(created);

            printf("  {\n");
            printf("    \"index\": %d,\n", idx + 1);
            printf("    \"guid\": \"%s\",\n", aguid ?: "");
            printf("    \"filename\": \"%s\",\n",
                   fname ? [jsonEscapeString([NSString stringWithUTF8String:fname]) UTF8String] : "");
            printf("    \"transfer_name\": \"%s\",\n", tname ?: "");
            printf("    \"mime_type\": \"%s\",\n", mime ?: "");
            printf("    \"uti\": \"%s\",\n", uti ?: "");
            printf("    \"size\": %lld,\n", bytes);
            printf("    \"is_outgoing\": %s,\n", outgoing ? "true" : "false");
            printf("    \"created\": \"%s\"\n",
                   d ? [isoDateString(d) UTF8String] : "");
            printf("  }");
            idx++;
        }
        printf("\n]\n");
    } else {
        printf("%-4s  %-30s  %-20s  %-10s  %s\n",
               "#", "Filename", "Type", "Size", "Date");
        printf("────  ──────────────────────────────  ────────────────────  ──────────  ────────────\n");

        int idx = 0;
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const char *fname = (const char *)sqlite3_column_text(stmt, 2);
            const char *mime = (const char *)sqlite3_column_text(stmt, 3);
            int64_t bytes = sqlite3_column_int64(stmt, 4);
            const char *tname = (const char *)sqlite3_column_text(stmt, 5);
            int64_t created = sqlite3_column_int64(stmt, 6);

            NSDate *d = dateFromChatDB(created);

            // Use transfer_name if filename is a full path
            NSString *displayName = nil;
            if (tname && strlen(tname) > 0) {
                displayName = [NSString stringWithUTF8String:tname];
            } else if (fname) {
                displayName = [[NSString stringWithUTF8String:fname] lastPathComponent];
            } else {
                displayName = @"(unknown)";
            }

            // Format size
            NSString *sizeStr;
            if (bytes < 1024) sizeStr = [NSString stringWithFormat:@"%lld B", bytes];
            else if (bytes < 1024*1024) sizeStr = [NSString stringWithFormat:@"%.1f KB", bytes/1024.0];
            else sizeStr = [NSString stringWithFormat:@"%.1f MB", bytes/(1024.0*1024.0)];

            printf("%-4d  %-30s  %-20s  %-10s  %s\n",
                   idx + 1,
                   [truncStr(displayName, 30) UTF8String],
                   mime ?: "?",
                   [sizeStr UTF8String],
                   [formatMsgDateShort(d) UTF8String]);
            idx++;
        }
        printf("\n%d attachments.\n", idx);
    }

    sqlite3_finalize(stmt);
}

// ─────────────────────────────────────────────────────────────────────────────
// msg send — send a text message via AppleScript
// ─────────────────────────────────────────────────────────────────────────────

int cmdMsgSend(const char *recipient, NSString *text, NSString *service) {
    if (!text || [text length] == 0) {
        fprintf(stderr, "No message text provided.\n");
        return 1;
    }

    NSString *addr = [NSString stringWithUTF8String:recipient];
    NSString *svc = service ?: @"iMessage";

    // Escape text for AppleScript
    NSString *escaped = [text stringByReplacingOccurrencesOfString:@"\\"
                                                       withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\""
                                                withString:@"\\\""];

    NSString *script = [NSString stringWithFormat:
        @"tell application \"Messages\"\n"
        @"  set targetService to 1st account whose service type = %@\n"
        @"  set targetBuddy to participant \"%@\" of targetService\n"
        @"  send \"%@\" to targetBuddy\n"
        @"end tell",
        [svc isEqualToString:@"SMS"] ? @"SMS" : @"iMessage",
        addr, escaped];

    NSString *errMsg = nil;
    runAppleScript(script, &errMsg);

    if (errMsg) {
        fprintf(stderr, "Send failed: %s\n", [errMsg UTF8String]);
        return 1;
    }

    printf("✓ Sent to %s via %s\n", recipient, [svc UTF8String]);
    return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// msg attach — send an attachment via AppleScript
// ─────────────────────────────────────────────────────────────────────────────

int cmdMsgAttach(const char *recipient, NSString *filePath, NSString *service) {
    NSString *addr = [NSString stringWithUTF8String:recipient];
    NSString *svc = service ?: @"iMessage";

    // Verify file exists
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:filePath]) {
        fprintf(stderr, "File not found: %s\n", [filePath UTF8String]);
        return 1;
    }

    // Convert to POSIX path for AppleScript
    NSString *script = [NSString stringWithFormat:
        @"tell application \"Messages\"\n"
        @"  set targetService to 1st account whose service type = %@\n"
        @"  set targetBuddy to participant \"%@\" of targetService\n"
        @"  set theFile to POSIX file \"%@\"\n"
        @"  send theFile to targetBuddy\n"
        @"end tell",
        [svc isEqualToString:@"SMS"] ? @"SMS" : @"iMessage",
        addr, filePath];

    NSString *errMsg = nil;
    runAppleScript(script, &errMsg);

    if (errMsg) {
        fprintf(stderr, "Send failed: %s\n", [errMsg UTF8String]);
        return 1;
    }

    printf("✓ Sent %s to %s via %s\n",
           [[filePath lastPathComponent] UTF8String],
           recipient, [svc UTF8String]);
    return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// msg react — send a tapback reaction
// ─────────────────────────────────────────────────────────────────────────────

int cmdMsgReact(const char *chatRef, int messageIdx, const char *reaction) {
    // Tapback via AppleScript is not directly supported.
    // This would require the Private API helper.
    // For now we can use GUI scripting as a fallback.
    fprintf(stderr, "Tapback reactions require the Private API.\n"
                    "This feature is not yet implemented via AppleScript.\n");
    return 1;
}

// ─────────────────────────────────────────────────────────────────────────────
// msg read / unread — mark chat as read or unread
// ─────────────────────────────────────────────────────────────────────────────

int cmdMsgRead(const char *chatRef) {
    fprintf(stderr, "Mark-as-read requires the Private API.\n"
                    "This feature is not yet implemented via AppleScript.\n");
    return 1;
}

int cmdMsgUnread(const char *chatRef) {
    fprintf(stderr, "Mark-as-unread requires the Private API.\n"
                    "This feature is not yet implemented via AppleScript.\n");
    return 1;
}

// ─────────────────────────────────────────────────────────────────────────────
// msg delete — delete a chat or message
// ─────────────────────────────────────────────────────────────────────────────

int cmdMsgDelete(const char *chatRef) {
    fprintf(stderr, "Deleting chats/messages requires the Private API.\n"
                    "This feature is not yet implemented.\n");
    return 1;
}

// ─────────────────────────────────────────────────────────────────────────────
// msg typing — send typing indicator
// ─────────────────────────────────────────────────────────────────────────────

int cmdMsgTyping(const char *chatRef) {
    fprintf(stderr, "Typing indicators require the Private API.\n"
                    "This feature is not yet implemented.\n");
    return 1;
}

// ─────────────────────────────────────────────────────────────────────────────
// msg edit / unsend
// ─────────────────────────────────────────────────────────────────────────────

int cmdMsgEdit(const char *msgGuid, NSString *newText) {
    fprintf(stderr, "Editing messages requires the Private API.\n"
                    "This feature is not yet implemented.\n");
    return 1;
}

int cmdMsgUnsend(const char *msgGuid) {
    fprintf(stderr, "Unsending messages requires the Private API.\n"
                    "This feature is not yet implemented.\n");
    return 1;
}

// ─────────────────────────────────────────────────────────────────────────────
// msg group — group chat operations
// ─────────────────────────────────────────────────────────────────────────────

int cmdMsgGroupNew(int addrCount, char *addresses[], NSString *message,
                   NSString *service) {
    if (addrCount < 1) {
        fprintf(stderr, "At least one address is required.\n");
        return 1;
    }

    // Build AppleScript for group chat
    NSMutableString *script = [NSMutableString stringWithString:
        @"tell application \"Messages\"\n"];
    NSString *svc = service ?: @"iMessage";
    [script appendFormat:
        @"  set targetService to 1st account whose service type = %@\n",
        [svc isEqualToString:@"SMS"] ? @"SMS" : @"iMessage"];

    // Create the chat with participants
    [script appendString:@"  set theChat to make new text chat with properties {participants:{"];
    for (int i = 0; i < addrCount; i++) {
        if (i > 0) [script appendString:@", "];
        [script appendFormat:@"participant \"%s\" of targetService",
            addresses[i]];
    }
    [script appendString:@"}}\n"];

    if (message && [message length] > 0) {
        NSString *escaped = [message stringByReplacingOccurrencesOfString:@"\\"
                                                              withString:@"\\\\"];
        escaped = [escaped stringByReplacingOccurrencesOfString:@"\""
                                                    withString:@"\\\""];
        [script appendFormat:@"  send \"%@\" to theChat\n", escaped];
    }

    [script appendString:@"end tell"];

    NSString *errMsg = nil;
    runAppleScript(script, &errMsg);

    if (errMsg) {
        fprintf(stderr, "Failed to create group: %s\n", [errMsg UTF8String]);
        return 1;
    }

    printf("✓ Group chat created with %d participants.\n", addrCount);
    return 0;
}

int cmdMsgGroupRename(const char *chatRef, NSString *newName) {
    fprintf(stderr, "Renaming groups requires the Private API.\n");
    return 1;
}

int cmdMsgGroupAdd(const char *chatRef, const char *address) {
    fprintf(stderr, "Adding participants requires the Private API.\n");
    return 1;
}

int cmdMsgGroupRemove(const char *chatRef, const char *address) {
    fprintf(stderr, "Removing participants requires the Private API.\n");
    return 1;
}

int cmdMsgGroupLeave(const char *chatRef) {
    fprintf(stderr, "Leaving groups requires the Private API.\n");
    return 1;
}

// ─────────────────────────────────────────────────────────────────────────────
// msg schedule — scheduled messages
// ─────────────────────────────────────────────────────────────────────────────

void cmdMsgScheduleList(BOOL jsonOutput) {
    if (!openMessagesDB()) return;

    const char *sql =
        "SELECT m.ROWID, m.guid, m.text, m.date, m.handle_id, "
        "h.id as handle_address, m.service "
        "FROM message m "
        "LEFT JOIN handle h ON h.ROWID = m.handle_id "
        "WHERE m.schedule_type = 2 AND m.schedule_state = 0 "
        "ORDER BY m.date ASC";

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(g_msgDB, sql, -1, &stmt, NULL) != SQLITE_OK) {
        fprintf(stderr, "Query failed: %s\n", sqlite3_errmsg(g_msgDB));
        return;
    }

    if (jsonOutput) {
        printf("[\n");
        int idx = 0;
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            if (idx > 0) printf(",\n");
            const char *guid = (const char *)sqlite3_column_text(stmt, 1);
            const char *text = (const char *)sqlite3_column_text(stmt, 2);
            int64_t date = sqlite3_column_int64(stmt, 3);
            const char *handle = (const char *)sqlite3_column_text(stmt, 5);
            const char *svc = (const char *)sqlite3_column_text(stmt, 6);

            NSDate *d = dateFromChatDB(date);

            printf("  {\n");
            printf("    \"guid\": \"%s\",\n", guid ?: "");
            printf("    \"text\": \"%s\",\n",
                   text ? [jsonEscapeString([NSString stringWithUTF8String:text]) UTF8String] : "");
            printf("    \"scheduled_for\": \"%s\",\n",
                   d ? [isoDateString(d) UTF8String] : "");
            printf("    \"recipient\": \"%s\",\n", handle ?: "");
            printf("    \"service\": \"%s\"\n", svc ?: "");
            printf("  }");
            idx++;
        }
        printf("\n]\n");
    } else {
        int idx = 0;
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const char *text = (const char *)sqlite3_column_text(stmt, 2);
            int64_t date = sqlite3_column_int64(stmt, 3);
            const char *handle = (const char *)sqlite3_column_text(stmt, 5);

            NSDate *d = dateFromChatDB(date);

            printf("%d. [%s] → %s: %s\n",
                   idx + 1,
                   d ? [formatMsgDate(d) UTF8String] : "?",
                   handle ?: "?",
                   text ?: "(no text)");
            idx++;
        }
        if (idx == 0) {
            printf("No scheduled messages.\n");
        }
    }

    sqlite3_finalize(stmt);
}

// ─────────────────────────────────────────────────────────────────────────────
// msg check — check iMessage availability for an address
// ─────────────────────────────────────────────────────────────────────────────

int cmdMsgCheck(const char *address) {
    if (!openMessagesDB()) return 1;

    // Check if address exists in handles
    const char *sql =
        "SELECT id, service FROM handle WHERE id = ? ORDER BY ROWID DESC";

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(g_msgDB, sql, -1, &stmt, NULL) != SQLITE_OK) {
        fprintf(stderr, "Query failed: %s\n", sqlite3_errmsg(g_msgDB));
        return 1;
    }
    sqlite3_bind_text(stmt, 1, address, -1, SQLITE_STATIC);

    BOOL found = NO;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        const char *svc = (const char *)sqlite3_column_text(stmt, 1);
        printf("  %s: %s ✓\n", address, svc ?: "?");
        found = YES;
    }
    sqlite3_finalize(stmt);

    if (!found) {
        printf("  %s: not found in message history\n", address);
        printf("  (Note: this only checks local history, not Apple's servers)\n");
        return 1;
    }
    return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// msg export — export a conversation
// ─────────────────────────────────────────────────────────────────────────────

int cmdMsgExport(const char *chatRef, NSString *outputPath, NSString *format) {
    if (!openMessagesDB()) return 1;

    NSString *chatGUID = resolveChatGUID(chatRef);
    if (!chatGUID) {
        fprintf(stderr, "Chat not found: %s\n", chatRef);
        return 1;
    }

    // Get all messages
    const char *sql =
        "SELECT m.ROWID, m.text, m.date, m.is_from_me, h.id as handle_address, "
        "m.cache_has_attachments "
        "FROM message m "
        "JOIN chat_message_join cmj ON cmj.message_id = m.ROWID "
        "JOIN chat c ON c.ROWID = cmj.chat_id "
        "LEFT JOIN handle h ON h.ROWID = m.handle_id "
        "WHERE c.guid = ? AND m.text IS NOT NULL "
        "ORDER BY m.date ASC";

    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(g_msgDB, sql, -1, &stmt, NULL) != SQLITE_OK) {
        fprintf(stderr, "Query failed: %s\n", sqlite3_errmsg(g_msgDB));
        return 1;
    }
    sqlite3_bind_text(stmt, 1, [chatGUID UTF8String], -1, SQLITE_STATIC);

    NSString *path = outputPath ?: [NSString stringWithFormat:@"chat-export.txt"];

    FILE *fp = fopen([path UTF8String], "w");
    if (!fp) {
        fprintf(stderr, "Cannot write to: %s\n", [path UTF8String]);
        sqlite3_finalize(stmt);
        return 1;
    }

    fprintf(fp, "Chat export: %s\n", [chatGUID UTF8String]);
    fprintf(fp, "Exported: %s\n\n",
            [formatMsgDate([NSDate date]) UTF8String]);

    int count = 0;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        int64_t rowid = sqlite3_column_int64(stmt, 0);
        const char *text = (const char *)sqlite3_column_text(stmt, 1);
        int64_t date = sqlite3_column_int64(stmt, 2);
        int isFromMe = sqlite3_column_int(stmt, 3);
        const char *handle = (const char *)sqlite3_column_text(stmt, 4);
        int hasAttach = sqlite3_column_int(stmt, 5);

        NSDate *d = dateFromChatDB(date);

        NSString *body = displayMsgText(text ? [NSString stringWithUTF8String:text] : nil,
                                        hasAttach, rowid);
        fprintf(fp, "[%s] %s: %s%s\n",
                d ? [formatMsgDate(d) UTF8String] : "",
                isFromMe ? "Me" : (handle ?: "?"),
                [body UTF8String],
                hasAttach ? " 📎" : "");
        count++;
    }

    fclose(fp);
    sqlite3_finalize(stmt);

    printf("✓ Exported %d messages to %s\n", count, [path UTF8String]);
    return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Help text
// ─────────────────────────────────────────────────────────────────────────────

void printMsgHelp(void) {
    printf(
"cider msg v" VERSION " — iMessage CLI\n"
"\n"
"SUBCOMMANDS:\n"
"  list          List conversations\n"
"  show <chat>   View messages in a conversation\n"
"  context <guid> Show messages around a specific message\n"
"  search        Search all messages\n"
"  send          Send a text message\n"
"  attach        Send a file attachment\n"
"  info <chat>   Show chat details & participants\n"
"  count         Message statistics\n"
"  contacts      List known contacts/handles\n"
"  attachments   List attachments in a chat\n"
"  export <chat> Export conversation to file\n"
"  schedule      List scheduled messages\n"
"  check <addr>  Check if address is in message history\n"
"  react         Send a tapback reaction (requires Private API)\n"
"  read          Mark chat as read (requires Private API)\n"
"  unread        Mark chat as unread (requires Private API)\n"
"  delete        Delete a chat (requires Private API)\n"
"  typing        Send typing indicator (requires Private API)\n"
"  edit          Edit a message (requires Private API)\n"
"  unsend        Unsend a message (requires Private API)\n"
"  group         Group chat operations\n"
"\n"
"CHAT REFERENCE:\n"
"  <N>           Chat index from 'cider msg list'\n"
"  +1234567890   Phone number\n"
"  user@email    Email address\n"
"  iMessage;-;.. Full chat GUID\n"
"\n"
"Run 'cider msg <subcommand> --help' for details.\n"
    );
}

void printMsgSubcommandHelp(const char *sub) {
    if (strcmp(sub, "list") == 0) {
        printf(
"cider msg list [options]\n"
"\n"
"  List conversations, most recent first.\n"
"\n"
"  --limit N      Number of conversations (default 50)\n"
"  --service S    Filter by service (iMessage, SMS)\n"
"  --json         JSON output\n"
"\n"
"  Examples:\n"
"    cider msg list\n"
"    cider msg list --limit 10\n"
"    cider msg list --service iMessage --json\n"
        );
    } else if (strcmp(sub, "show") == 0) {
        printf(
"cider msg show <chat> [options]\n"
"\n"
"  View messages in a conversation.\n"
"\n"
"  <chat>         Chat index, phone number, email, or GUID\n"
"  --limit N      Number of messages (default 50)\n"
"  --after DATE   Show messages after date\n"
"  --before DATE  Show messages before date\n"
"  --json         JSON output\n"
"\n"
"  Examples:\n"
"    cider msg show 1\n"
"    cider msg show +1234567890 --limit 100\n"
"    cider msg show 1 --after 2024-01-01 --json\n"
        );
    } else if (strcmp(sub, "context") == 0) {
        printf(
"cider msg context <message-guid> [options]\n"
"\n"
"  Show messages around a specific message in its conversation.\n"
"  Use message GUIDs from 'cider msg search --json' or 'cider msg show --json'.\n"
"\n"
"  --context N    Messages before/after (default 10)\n"
"  --before       Only show older messages (scroll up)\n"
"  --after        Only show newer messages (scroll down)\n"
"  --json         JSON output\n"
"\n"
"  Examples:\n"
"    cider msg search \"dinner\" --json       # find the GUID\n"
"    cider msg context <guid>               # 10 before + 10 after\n"
"    cider msg context <guid> --context 20  # wider window\n"
"    cider msg context <guid> --before      # scroll up\n"
"    cider msg context <guid> --after       # scroll down\n"
        );
    } else if (strcmp(sub, "search") == 0) {
        printf(
"cider msg search <query> [options]\n"
"\n"
"  Search all messages for text.\n"
"\n"
"  --limit N      Max results (default 50)\n"
"  --json         JSON output\n"
"\n"
"  Examples:\n"
"    cider msg search \"dinner tonight\"\n"
"    cider msg search \"flight\" --limit 20 --json\n"
        );
    } else if (strcmp(sub, "send") == 0) {
        printf(
"cider msg send <recipient> <message>\n"
"\n"
"  Send a text message via Messages.app.\n"
"\n"
"  <recipient>    Phone number or email\n"
"  <message>      Text to send (or pipe via stdin)\n"
"  --service S    Service (iMessage or SMS, default iMessage)\n"
"\n"
"  Examples:\n"
"    cider msg send +1234567890 \"Hey, what's up?\"\n"
"    echo \"Hello\" | cider msg send +1234567890\n"
"    cider msg send user@email.com \"Meeting at 3\" --service iMessage\n"
        );
    } else if (strcmp(sub, "info") == 0) {
        printf(
"cider msg info <chat>\n"
"\n"
"  Show detailed information about a chat.\n"
"\n"
"  --json         JSON output\n"
"\n"
"  Examples:\n"
"    cider msg info 1\n"
"    cider msg info +1234567890 --json\n"
        );
    } else if (strcmp(sub, "count") == 0) {
        printf(
"cider msg count [chat]\n"
"\n"
"  Show message statistics. Without a chat argument,\n"
"  shows global database statistics.\n"
"\n"
"  --json         JSON output\n"
"\n"
"  Examples:\n"
"    cider msg count\n"
"    cider msg count 1 --json\n"
        );
    } else if (strcmp(sub, "contacts") == 0) {
        printf(
"cider msg contacts [options]\n"
"\n"
"  List known contacts/handles from message history.\n"
"\n"
"  --limit N      Max results (default 100)\n"
"  --service S    Filter by service\n"
"  --json         JSON output\n"
        );
    } else if (strcmp(sub, "attach") == 0) {
        printf(
"cider msg attach <recipient> <file>\n"
"\n"
"  Send a file attachment via Messages.app.\n"
"\n"
"  --service S    Service (iMessage or SMS)\n"
"\n"
"  Examples:\n"
"    cider msg attach +1234567890 ~/photo.jpg\n"
        );
    } else if (strcmp(sub, "export") == 0) {
        printf(
"cider msg export <chat> [options]\n"
"\n"
"  Export a conversation to a text file.\n"
"\n"
"  -o PATH        Output file path (default: chat-export.txt)\n"
"\n"
"  Examples:\n"
"    cider msg export 1\n"
"    cider msg export +1234567890 -o convo.txt\n"
        );
    } else if (strcmp(sub, "group") == 0) {
        printf(
"cider msg group <action> [options]\n"
"\n"
"  Group chat operations.\n"
"\n"
"  new <addr1> [addr2] ...   Create a group chat\n"
"    --message TEXT           Send initial message\n"
"    --service S              Service (default iMessage)\n"
"\n"
"  rename <chat> <name>      Rename group (Private API)\n"
"  add <chat> <address>      Add participant (Private API)\n"
"  remove <chat> <address>   Remove participant (Private API)\n"
"  leave <chat>              Leave group (Private API)\n"
"\n"
"  Examples:\n"
"    cider msg group new +1234567890 +0987654321 --message \"Hey all!\"\n"
        );
    } else {
        printf("No detailed help for '%s'. Run 'cider msg --help'.\n", sub);
    }
}

/**
 * cider.h — Shared declarations for the cider CLI
 *
 * All source files (#import this header):
 *   core.m       — Framework init, Core Data, CRDT, helpers
 *   notes.m      — Notes commands
 *   reminders.m  — Reminders commands
 *   sync.m       — Bidirectional Notes <-> Markdown sync
 *   main.m       — Help text, arg parsing, main()
 */

#ifndef CIDER_H
#define CIDER_H

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <sys/stat.h>
#include <unistd.h>
#include <notify.h>

#define VERSION "4.2.0"
#define ATTACHMENT_MARKER ((unichar)0xFFFC)

// ─────────────────────────────────────────────────────────────────────────────
// Global state (defined in core.m)
// ─────────────────────────────────────────────────────────────────────────────

extern id g_ctx;
extern id g_moc;

// ─────────────────────────────────────────────────────────────────────────────
// Framework init (core.m)
// ─────────────────────────────────────────────────────────────────────────────

BOOL initNotesContext(void);

// ─────────────────────────────────────────────────────────────────────────────
// Core Data helpers (core.m)
// ─────────────────────────────────────────────────────────────────────────────

NSArray *fetchNotes(NSPredicate *predicate);
NSArray *fetchAllNotes(void);
NSArray *fetchFolders(void);
id findOrCreateFolder(NSString *title, BOOL create);
id defaultFolder(void);

// ─────────────────────────────────────────────────────────────────────────────
// Note access helpers (core.m)
// ─────────────────────────────────────────────────────────────────────────────

NSString *noteURIString(id note);
NSString *noteIdentifier(id note);
id findNoteByIdentifier(NSString *identifier);
NSInteger noteIntPK(id note);
NSString *noteTitle(id note);
NSString *folderName(id note);
id noteVisibleAttachments(id note);
NSUInteger noteAttachmentCount(id note);
NSArray *attachmentsAsArray(id attsObj);
NSArray *noteAttachmentNames(id note);

// ─────────────────────────────────────────────────────────────────────────────
// CRDT / mergeableString helpers (core.m)
// ─────────────────────────────────────────────────────────────────────────────

id noteMergeableString(id note);
NSString *noteRawText(id note);
NSString *noteTextForDisplay(id note);
NSString *rawTextToEditable(NSString *raw, NSArray *names);
NSString *editableToRawText(NSString *edited);
BOOL saveContext(void);
BOOL applyCRDTEdit(id note, NSString *oldText, NSString *newText);

// ─────────────────────────────────────────────────────────────────────────────
// Note listing helpers (core.m)
// ─────────────────────────────────────────────────────────────────────────────

NSArray *filteredNotes(NSString *filterFolder);
id noteAtIndex(NSUInteger idx, NSString *folder);

// ─────────────────────────────────────────────────────────────────────────────
// JSON / formatting / utility helpers (core.m)
// ─────────────────────────────────────────────────────────────────────────────

NSDictionary *loadCiderSettings(void);
NSString *getCiderSetting(NSString *key);
int setCiderSetting(NSString *key, NSString *value);
NSString *jsonEscapeString(NSString *s);
NSString *truncStr(NSString *s, NSUInteger maxLen);
NSString *padRight(NSString *s, NSUInteger width);
NSAppleEventDescriptor *runAppleScript(NSString *src, NSString **errMsg);
NSString *isoDateString(NSDate *date);
NSDate *parseDateString(NSString *str);

// ─────────────────────────────────────────────────────────────────────────────
// Notes commands (notes.m)
// ─────────────────────────────────────────────────────────────────────────────

NSUInteger promptNoteIndex(NSString *verb, NSString *folder);
void cmdNotesList(NSString *folder, BOOL jsonOutput,
                  NSString *afterStr, NSString *beforeStr, NSString *sortMode,
                  BOOL pinnedOnly, NSString *tagFilter);
void cmdFoldersList(BOOL jsonOutput);
int  cmdNotesView(NSUInteger idx, NSString *folder, BOOL jsonOutput);
int  cmdNotesInspect(NSUInteger idx, NSString *folder, BOOL jsonOutput);
void cmdNotesAdd(NSString *folderName);
void cmdNotesEdit(NSUInteger idx);
int  cmdNotesReplace(NSUInteger idx, NSString *findStr, NSString *replaceStr,
                     BOOL useRegex, BOOL caseInsensitive);
int  cmdNotesReplaceAll(NSString *findStr, NSString *replaceStr, NSString *folder,
                        BOOL useRegex, BOOL caseInsensitive, BOOL dryRun);
void cmdNotesDelete(NSUInteger idx);
void cmdNotesMove(NSUInteger idx, NSString *targetFolderName);
void cmdNotesSearch(NSString *query, BOOL jsonOutput, BOOL useRegex,
                    BOOL titleOnly, BOOL bodyOnly, NSString *folder,
                    NSString *afterStr, NSString *beforeStr, NSString *tagFilter);
int  cmdNotesAppend(NSUInteger idx, NSString *text, NSString *folder, BOOL noNewline);
int  cmdNotesPrepend(NSUInteger idx, NSString *text, NSString *folder, BOOL noNewline);
void cmdNotesDebug(NSUInteger idx, NSString *folder);
void cmdNotesHistory(NSUInteger idx, NSString *folder, BOOL jsonOutput, BOOL raw, BOOL blame);
int  cmdNotesGetdate(NSUInteger idx, NSString *folder, BOOL jsonOutput);
int  cmdNotesSetdate(NSUInteger idx, NSString *dateStr, NSString *folder, BOOL dryRun);
void cmdSettings(BOOL jsonOutput);
int  cmdSettingsGet(NSString *key);
int  cmdSettingsSet(NSString *key, NSString *value);
int  cmdSettingsReset(void);
int  cmdNotesPin(NSUInteger idx, NSString *folder);
int  cmdNotesUnpin(NSUInteger idx, NSString *folder);
NSArray *extractTags(NSString *text);
int  cmdNotesTag(NSUInteger idx, NSString *tag, NSString *folder);
int  cmdNotesUntag(NSUInteger idx, NSString *tag, NSString *folder);
void cmdNotesTags(BOOL withCounts, BOOL jsonOutput);
int  cmdTagsClean(void);
int  cmdFolderCreate(NSString *name, NSString *parent);
int  cmdFolderDelete(NSString *name);
int  cmdFolderRename(NSString *oldName, NSString *newName);
void cmdTemplatesList(void);
int  cmdTemplatesShow(NSString *name);
void cmdTemplatesAdd(void);
int  cmdTemplatesDelete(NSString *name);
int  cmdNotesAddFromTemplate(NSString *templateName, NSString *targetFolder);
void cmdNotesExport(NSString *exportPath);
void cmdNotesAttachments(NSUInteger idx, BOOL jsonOut);
void cmdNotesAttach(NSUInteger idx, NSString *filePath);
void cmdNotesAttachAt(NSUInteger idx, NSString *filePath, NSUInteger position);
NSArray *attachmentOrderFromCRDT(id note);
NSString *attachmentNameByID(NSArray *atts, NSString *attID);
void cmdNotesDetach(NSUInteger idx, NSUInteger attIdx);
void cmdNotesLinks(NSUInteger idx, NSString *folder, BOOL jsonOut);
void cmdNotesBacklinks(NSUInteger idx, NSString *folder, BOOL jsonOut);
void cmdNotesBacklinksAll(BOOL jsonOut);
int  cmdNotesLink(NSUInteger idx, NSString *targetTitle, NSString *folder);
void cmdNotesWatch(NSString *folder, NSTimeInterval interval, BOOL jsonOutput);
void cmdNotesChecklist(NSUInteger idx, NSString *folder, BOOL jsonOut, BOOL summary,
                       NSString *addText);
int  cmdNotesCheck(NSUInteger idx, NSUInteger itemNum, NSString *folder);
int  cmdNotesUncheck(NSUInteger idx, NSUInteger itemNum, NSString *folder);
void cmdNotesTable(NSUInteger idx, NSString *folder, NSUInteger tableIdx,
                   BOOL jsonOut, BOOL csvOut, BOOL listTables, BOOL headersOnly,
                   NSInteger rowNum);
int  cmdNotesTableAdd(NSUInteger idx, NSString *folder, NSArray *rows);
void cmdNotesShare(NSUInteger idx, NSString *folder, BOOL jsonOut);
void cmdNotesShared(BOOL jsonOut);

// ─────────────────────────────────────────────────────────────────────────────
// Reminders commands (reminders.m)
// ─────────────────────────────────────────────────────────────────────────────

BOOL initRemindersContext(void);
void cmdRemList(void);
void cmdRemAdd(NSString *title, NSString *dueDate);
void cmdRemEdit(NSUInteger idx, NSString *newTitle);
void cmdRemDelete(NSUInteger idx);
void cmdRemComplete(NSUInteger idx);

// ─────────────────────────────────────────────────────────────────────────────
// Sync commands (sync.m)
// ─────────────────────────────────────────────────────────────────────────────

int cmdSyncBackup(NSString *syncDir);
int cmdSyncRun(NSString *syncDir);
int cmdSyncWatch(NSString *syncDir, NSTimeInterval interval);
void printSyncHelp(void);
NSString *syncDefaultDir(void);

// ─────────────────────────────────────────────────────────────────────────────
// iMessage commands (imessage.m)
// ─────────────────────────────────────────────────────────────────────────────

BOOL openMessagesDB(void);
void closeMessagesDB(void);

void cmdMsgList(NSUInteger limit, BOOL jsonOutput, NSString *service);
void cmdMsgShow(const char *chatRef, NSUInteger limit, BOOL jsonOutput,
                NSString *afterStr, NSString *beforeStr, BOOL sortAsc);
void cmdMsgContext(const char *msgGuid, NSUInteger context, BOOL jsonOutput,
                   const char *direction);
void cmdMsgSearch(NSString *query, NSUInteger limit, BOOL jsonOutput,
                  BOOL sortAsc, BOOL fzfOutput);
void cmdMsgCount(const char *chatRef, BOOL jsonOutput);
void cmdMsgContacts(NSUInteger limit, BOOL jsonOutput, NSString *service);
void cmdMsgInfo(const char *chatRef, BOOL jsonOutput);
void cmdMsgAttachments(const char *chatRef, NSUInteger limit, BOOL jsonOutput);
int  cmdMsgSend(const char *recipient, NSString *text, NSString *service);
int  cmdMsgAttach(const char *recipient, NSString *filePath, NSString *service);
int  cmdMsgReact(const char *chatRef, int messageIdx, const char *reaction);
int  cmdMsgRead(const char *chatRef);
int  cmdMsgUnread(const char *chatRef);
int  cmdMsgDelete(const char *chatRef);
int  cmdMsgTyping(const char *chatRef);
int  cmdMsgEdit(const char *msgGuid, NSString *newText);
int  cmdMsgUnsend(const char *msgGuid);
int  cmdMsgGroupNew(int addrCount, char *addresses[], NSString *message,
                    NSString *service);
int  cmdMsgGroupRename(const char *chatRef, NSString *newName);
int  cmdMsgGroupAdd(const char *chatRef, const char *address);
int  cmdMsgGroupRemove(const char *chatRef, const char *address);
int  cmdMsgGroupLeave(const char *chatRef);
void cmdMsgScheduleList(BOOL jsonOutput);
int  cmdMsgCheck(const char *address);
int  cmdMsgExport(const char *chatRef, NSString *outputPath, NSString *format);
void printMsgHelp(void);
void printMsgSubcommandHelp(const char *sub);

// ─────────────────────────────────────────────────────────────────────────────
// Help text & arg parsing (main.m)
// ─────────────────────────────────────────────────────────────────────────────

void printHelp(void);
void printNotesHelp(void);
void printNotesSubcommandHelp(const char *sub);
void printRemHelp(void);
NSString *argValue(int argc, char *argv[], int startIdx,
                   const char *flag1, const char *flag2);
BOOL argHasFlag(int argc, char *argv[], int startIdx,
                const char *flag1, const char *flag2);

// ─────────────────────────────────────────────────────────────────────────────
// Passwords commands (passwords.m)
// ─────────────────────────────────────────────────────────────────────────────

void cmdPasswordsList(NSString *csvPath, BOOL jsonOutput);
void cmdPasswordsShow(NSUInteger idx, NSString *csvPath, BOOL jsonOutput);
void cmdPasswordsSearch(NSString *query, NSString *csvPath, BOOL jsonOutput);
void cmdPasswordsSync(NSString *csvPath);
void printPasswordsHelp(void);

#endif /* CIDER_H */

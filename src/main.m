/**
 * main.m — Help text, argument parsing, command registry, and dispatch
 *
 * Compile: clang -framework Foundation -framework CoreData -o cider \
 *          core.m notes.m reminders.m sync.m main.m
 */

#import "cider.h"

// ─────────────────────────────────────────────────────────────────────────────
// Help text
// ─────────────────────────────────────────────────────────────────────────────

void printHelp(void) {
    printf(
"cider v" VERSION " — Apple Notes CLI\n"
"\n"
"USAGE:\n"
"  cider notes [subcommand]    Notes operations\n"
"  cider templates [sub]       Template management\n"
"  cider settings [sub]        Cider configuration\n"
"  cider rem [subcommand]      Reminders operations\n"
"  cider msg [subcommand]      iMessage operations\n"
"  cider sync [subcommand]     Notes <-> Markdown sync\n"
"  cider passwords [sub]       Keychain passwords + Vaultwarden sync\n"
"  cider --version             Show version\n"
"\n"
"Run 'cider <command> --help' for details on any command.\n"
    );
}

void printNotesHelp(void) {
    printf(
"cider notes v" VERSION " — Apple Notes CLI\n"
"\n"
"SUBCOMMANDS:\n"
"  list          List notes (with filters, sorting, date range)\n"
"  show <N>      View note content\n"
"  inspect <N>   Full note details (metadata, tags, links, tables)\n"
"  folders       List all folders\n"
"  add           Add a new note (stdin, $EDITOR, or template)\n"
"  edit <N>      Edit note via CRDT (preserves attachments)\n"
"  delete <N>    Delete a note\n"
"  move <N>      Move note to a folder\n"
"  search        Search notes by text\n"
"  replace       Find & replace in one or all notes\n"
"  append <N>    Append text to end of note\n"
"  prepend <N>   Insert text after title\n"
"  pin <N>       Pin a note\n"
"  unpin <N>     Unpin a note\n"
"  tag <N>       Add a #tag to a note\n"
"  untag <N>     Remove a #tag from a note\n"
"  tags          List all unique tags\n"
"  share <N>     Show sharing status\n"
"  shared        List all shared notes\n"
"  table <N>     Show/add table data\n"
"  checklist <N> Show checklist items\n"
"  check <N>     Check off a checklist item\n"
"  uncheck <N>   Uncheck a checklist item\n"
"  links <N>     Show outgoing note links\n"
"  backlinks <N> Show notes linking to note N\n"
"  link <N>      Create a link to another note\n"
"  watch         Stream note change events\n"
"  history <N>   Edit timeline & blame (who wrote what, when)\n"
"  getdate <N>   Show modification/creation dates\n"
"  setdate <N>   Set modification date\n"
"  folder        Create, delete, or rename folders\n"
"  attachments   List attachments in a note\n"
"  attach <N>    Add file attachment to a note\n"
"  detach <N>    Remove an attachment\n"
"  export        Export all notes to HTML\n"
"  debug <N>     Dump CRDT attributes for a note\n"
"\n"
"Run 'cider notes <subcommand> --help' for detailed usage.\n"
    );
}

// Per-subcommand detailed help
void printNotesSubcommandHelp(const char *sub) {
    if (strcmp(sub, "list") == 0) {
        printf(
"cider notes list [options]\n"
"\n"
"  List notes with optional filtering and sorting.\n"
"\n"
"OPTIONS:\n"
"  -f, --folder <f>           Filter by folder\n"
"  --after <date>             Notes modified after date\n"
"  --before <date>            Notes modified before date\n"
"  --sort created|modified|title  Sort order (default: title)\n"
"  --pinned                   Show only pinned notes\n"
"  --tag <tag>                Filter by #tag\n"
"  --json                     JSON output\n"
"\n"
"  Date formats: 2024-01-15, 2024-01-15T10:30:00,\n"
"  today, yesterday, \"3 days ago\", \"1 week ago\"\n"
"\n"
"EXAMPLES:\n"
"  cider notes list --after today\n"
"  cider notes list --sort modified -f Work\n"
"  cider notes list --after \"1 week ago\" --json\n"
"  cider notes list --tag project-x --pinned\n"
        );
    } else if (strcmp(sub, "show") == 0) {
        printf(
"cider notes show <N> [--json] [-f <folder>]\n"
"\n"
"  View the content of note N. Also: cider notes <N>\n"
"\n"
"EXAMPLES:\n"
"  cider notes show 5\n"
"  cider notes 5\n"
"  cider notes show 5 --json\n"
        );
    } else if (strcmp(sub, "inspect") == 0) {
        printf(
"cider notes inspect <N> [--json] [-f <folder>]\n"
"\n"
"  Full note details: metadata, tags, links, tables, attachments.\n"
"\n"
"EXAMPLES:\n"
"  cider notes inspect 5\n"
"  cider notes inspect 5 --json\n"
        );
    } else if (strcmp(sub, "folders") == 0) {
        printf(
"cider notes folders [--json]\n"
"\n"
"  List all note folders.\n"
        );
    } else if (strcmp(sub, "add") == 0) {
        printf(
"cider notes add [--folder <f>] [--template <name>]\n"
"\n"
"  Add a new note. Reads from stdin (if piped) or opens $EDITOR.\n"
"  The first line becomes the title.\n"
"\n"
"OPTIONS:\n"
"  -f, --folder <f>       Target folder\n"
"  --template <name>      Pre-fill from a template\n"
"\n"
"EXAMPLES:\n"
"  cider notes add\n"
"  cider notes add -f \"Work Notes\"\n"
"  echo \"Title\\nBody\" | cider notes add\n"
"  cider notes add --template \"Meeting Notes\"\n"
        );
    } else if (strcmp(sub, "edit") == 0) {
        printf(
"cider notes edit <N>\n"
"\n"
"  Edit note N in $EDITOR using CRDT (preserves attachments).\n"
"  Attachments appear as %%%%ATTACHMENT_N_name%%%% markers.\n"
"  Edit the text freely but do NOT remove or rename markers.\n"
"  Pipe content: echo 'new body' | cider notes edit N\n"
"\n"
"EXAMPLES:\n"
"  cider notes edit 5\n"
"  echo \"new content\" | cider notes edit 5\n"
        );
    } else if (strcmp(sub, "delete") == 0) {
        printf("cider notes delete <N>\n\n  Delete note N.\n");
    } else if (strcmp(sub, "move") == 0) {
        printf(
"cider notes move <N> <folder>\n"
"\n"
"  Move note N to the specified folder.\n"
"\n"
"EXAMPLES:\n"
"  cider notes move 5 \"Work Notes\"\n"
        );
    } else if (strcmp(sub, "search") == 0) {
        printf(
"cider notes search <query> [options]\n"
"\n"
"  Search note title and body (case-insensitive).\n"
"\n"
"OPTIONS:\n"
"  --regex           Treat query as ICU regex\n"
"  --title           Search title only\n"
"  --body            Search body only\n"
"  -f, --folder <f>  Scope to folder\n"
"  --after <date>    Filter by modification date\n"
"  --before <date>   Filter by modification date\n"
"  --tag <tag>       Also filter by #tag\n"
"  --json            JSON output\n"
"\n"
"EXAMPLES:\n"
"  cider notes search \"meeting\"\n"
"  cider notes search \"TODO\" --title\n"
"  cider notes search \"\\\\d{3}-\\\\d{4}\" --regex\n"
"  cider notes search \"important\" --body -f Work\n"
        );
    } else if (strcmp(sub, "replace") == 0) {
        printf(
"cider notes replace <N> --find <s> --replace <s> [--regex] [-i]\n"
"cider notes replace --all --find <s> --replace <s> [options]\n"
"\n"
"  Find and replace text in one or all notes.\n"
"\n"
"OPTIONS:\n"
"  --all              Replace across all notes (instead of one)\n"
"  --regex            ICU regex; --replace supports $1, $2\n"
"  -i                 Case-insensitive\n"
"  -f, --folder <f>   Scope --all to a folder\n"
"  --dry-run          Preview without changing (--all mode)\n"
"\n"
"EXAMPLES:\n"
"  cider notes replace 3 --find old --replace new\n"
"  cider notes replace --all --find old --replace new --dry-run\n"
"  cider notes replace --all --find \"http://\" --replace \"https://\" -f Work\n"
        );
    } else if (strcmp(sub, "append") == 0) {
        printf(
"cider notes append <N> <text> [--no-newline] [-f <folder>]\n"
"\n"
"  Append text to the end of note N. Supports stdin piping.\n"
"\n"
"EXAMPLES:\n"
"  cider notes append 3 \"Added at the bottom\"\n"
"  echo \"piped text\" | cider notes append 3\n"
"  cider notes append 3 \"no gap\" --no-newline\n"
        );
    } else if (strcmp(sub, "prepend") == 0) {
        printf(
"cider notes prepend <N> <text> [--no-newline] [-f <folder>]\n"
"\n"
"  Insert text right after the title of note N. Supports stdin piping.\n"
"\n"
"EXAMPLES:\n"
"  cider notes prepend 3 \"Inserted after title\"\n"
"  echo \"piped text\" | cider notes prepend 3\n"
        );
    } else if (strcmp(sub, "pin") == 0 || strcmp(sub, "unpin") == 0) {
        printf(
"cider notes pin <N> [-f <folder>]\n"
"cider notes unpin <N> [-f <folder>]\n"
"\n"
"  Pin or unpin a note. Pinned notes appear at the top in Apple Notes.\n"
"\n"
"EXAMPLES:\n"
"  cider notes pin 3\n"
"  cider notes unpin 3\n"
"  cider notes list --pinned\n"
        );
    } else if (strcmp(sub, "tag") == 0 || strcmp(sub, "untag") == 0) {
        printf(
"cider notes tag <N> <tag> [-f <folder>]\n"
"cider notes untag <N> <tag> [-f <folder>]\n"
"\n"
"  Add or remove #tags. Auto-prepends # if omitted.\n"
"\n"
"EXAMPLES:\n"
"  cider notes tag 3 project-x\n"
"  cider notes untag 3 project-x\n"
        );
    } else if (strcmp(sub, "tags") == 0) {
        printf(
"cider notes tags [--count] [--json] [--clean]\n"
"\n"
"  List all unique #tags across all notes.\n"
"  --count shows how many notes use each tag.\n"
"  --clean removes orphaned tags.\n"
        );
    } else if (strcmp(sub, "share") == 0) {
        printf(
"cider notes share <N> [--json] [-f <folder>]\n"
"\n"
"  Show iCloud sharing status and participants for note N.\n"
"\n"
"EXAMPLES:\n"
"  cider notes share 5\n"
"  cider notes share 5 --json\n"
        );
    } else if (strcmp(sub, "shared") == 0) {
        printf(
"cider notes shared [--json]\n"
"\n"
"  List all shared (collaborative) notes.\n"
        );
    } else if (strcmp(sub, "table") == 0) {
        printf(
"cider notes table <N> [options]\n"
"\n"
"  Show or modify table data in note N.\n"
"\n"
"OPTIONS:\n"
"  --list              List all tables with row/col counts\n"
"  --index <i>         Select table by index (0-based)\n"
"  --json              JSON array of {header: value}\n"
"  --csv               CSV output\n"
"  --row <r>           Specific row (0-based)\n"
"  --headers           Column headers only\n"
"  --add-row \"a|b|c\"   Add row (pipe-delimited, repeatable)\n"
"\n"
"EXAMPLES:\n"
"  cider notes table 5\n"
"  cider notes table 5 --json\n"
"  cider notes table 5 --csv\n"
"  cider notes table 5 --add-row \"Name|Value\"\n"
        );
    } else if (strcmp(sub, "checklist") == 0) {
        printf(
"cider notes checklist <N> [--summary] [--json] [--add \"text\"] [-f <folder>]\n"
"\n"
"  Show checklist items with [x]/[ ] status.\n"
"\n"
"OPTIONS:\n"
"  --summary      Summary only (e.g. \"3/6 complete\")\n"
"  --json         JSON output\n"
"  --add \"text\"   Add a new checklist item\n"
"\n"
"EXAMPLES:\n"
"  cider notes checklist 5\n"
"  cider notes checklist 5 --summary\n"
"  cider notes checklist 5 --add \"Buy milk\"\n"
        );
    } else if (strcmp(sub, "check") == 0 || strcmp(sub, "uncheck") == 0) {
        printf(
"cider notes check <N> <item#> [-f <folder>]\n"
"cider notes uncheck <N> <item#> [-f <folder>]\n"
"\n"
"  Check or uncheck a checklist item by number (1-based).\n"
"\n"
"EXAMPLES:\n"
"  cider notes check 5 2\n"
"  cider notes uncheck 5 2\n"
        );
    } else if (strcmp(sub, "links") == 0) {
        printf(
"cider notes links <N> [--json] [-f <folder>]\n"
"\n"
"  Show outgoing note-to-note links in note N.\n"
"\n"
"EXAMPLES:\n"
"  cider notes links 5\n"
"  cider notes links 5 --json\n"
        );
    } else if (strcmp(sub, "backlinks") == 0) {
        printf(
"cider notes backlinks <N> [--json] [-f <folder>]\n"
"cider notes backlinks --all [--json]\n"
"\n"
"  Show notes that link to note N, or show full link graph.\n"
"\n"
"EXAMPLES:\n"
"  cider notes backlinks 5\n"
"  cider notes backlinks --all\n"
"  cider notes backlinks --all --json\n"
        );
    } else if (strcmp(sub, "link") == 0) {
        printf(
"cider notes link <N> <target title> [-f <folder>]\n"
"\n"
"  Create a link from note N to another note by title.\n"
"\n"
"EXAMPLES:\n"
"  cider notes link 5 \"Meeting Notes\"\n"
        );
    } else if (strcmp(sub, "watch") == 0) {
        printf(
"cider notes watch [--folder <f>] [--interval <s>] [--json]\n"
"\n"
"  Stream note change events (created, modified, deleted).\n"
"\n"
"OPTIONS:\n"
"  -f, --folder <f>   Watch specific folder\n"
"  --interval <s>     Poll interval in seconds (default: 2)\n"
"  --json             JSON event stream\n"
"\n"
"EXAMPLES:\n"
"  cider notes watch\n"
"  cider notes watch -f \"Work Notes\"\n"
"  cider notes watch --json --interval 10\n"
        );
    } else if (strcmp(sub, "history") == 0) {
        printf(
"cider notes history <N> [--blame] [--raw] [--json] [-f <folder>]\n"
"\n"
"  Show CRDT edit history — who edited the note and when.\n"
"  Shows person names for shared notes, device IDs otherwise.\n"
"\n"
"OPTIONS:\n"
"  --blame  Annotated view: each line shows who wrote it and when\n"
"  --raw    Per-keystroke detail (every individual edit)\n"
"  --json   JSON output with devices and sessions\n"
"\n"
"  Default groups edits into sessions (>60s gap = new session).\n"
"  --blame shows the current note text like 'git blame'.\n"
"\n"
"EXAMPLES:\n"
"  cider notes history 5\n"
"  cider notes history 5 --blame\n"
"  cider notes history 5 --raw\n"
"  cider notes history 5 --json\n"
        );
    } else if (strcmp(sub, "getdate") == 0) {
        printf(
"cider notes getdate <N> [--json] [-f <folder>]\n"
"\n"
"  Show a note's modification and creation dates.\n"
"\n"
"EXAMPLES:\n"
"  cider notes getdate 349\n"
"  cider notes getdate 349 --json\n"
        );
    } else if (strcmp(sub, "setdate") == 0) {
        printf(
"cider notes setdate <N> <date> [--dry-run] [-f <folder>]\n"
"\n"
"  Set a note's modification date.\n"
"  Date format: ISO 8601 (2024-01-15T14:30:00 or 2024-01-15)\n"
"\n"
"OPTIONS:\n"
"  --dry-run   Preview the change without writing\n"
"\n"
"EXAMPLES:\n"
"  cider notes setdate 349 2024-06-15T10:30:00\n"
"  cider notes setdate 349 2024-06-15 --dry-run\n"
        );
    } else if (strcmp(sub, "folder") == 0) {
        printf(
"cider notes folder create <name> [--parent <p>]\n"
"cider notes folder delete <name>\n"
"cider notes folder rename <old> <new>\n"
"\n"
"  Create, delete, or rename folders.\n"
"  Delete requires the folder to be empty.\n"
"\n"
"EXAMPLES:\n"
"  cider notes folder create \"Work Notes\"\n"
"  cider notes folder create \"Meetings\" --parent \"Work Notes\"\n"
"  cider notes folder delete \"Old Stuff\"\n"
"  cider notes folder rename \"Work\" \"Work Notes\"\n"
        );
    } else if (strcmp(sub, "attachments") == 0) {
        printf(
"cider notes attachments <N> [--json]\n"
"\n"
"  List attachments in note N with CRDT positions.\n"
        );
    } else if (strcmp(sub, "attach") == 0) {
        printf(
"cider notes attach <N> <file> [--at <pos>]\n"
"\n"
"  Attach a file to note N. Optionally specify position.\n"
"\n"
"EXAMPLES:\n"
"  cider notes attach 5 ~/photo.jpg\n"
"  cider notes attach 5 ~/doc.pdf --at 3\n"
        );
    } else if (strcmp(sub, "detach") == 0) {
        printf(
"cider notes detach <N> [<A>]\n"
"\n"
"  Remove attachment A (1-based index) from note N.\n"
"  Omit A to be prompted interactively.\n"
        );
    } else if (strcmp(sub, "export") == 0) {
        printf(
"cider notes export <path>\n"
"\n"
"  Export all notes to HTML files in the given directory.\n"
        );
    } else if (strcmp(sub, "debug") == 0) {
        printf(
"cider notes debug <N> [-f <folder>]\n"
"\n"
"  Dump all CRDT attributed string attributes for a note.\n"
"  Useful for understanding internal formatting.\n"
        );
    } else {
        fprintf(stderr, "No help available for '%s'. Run 'cider notes --help' for subcommand list.\n", sub);
    }
}

void printRemHelp(void) {
    printf(
"cider rem v" VERSION " — Reminders CLI\n"
"\n"
"USAGE:\n"
"  cider rem                          List all incomplete reminders\n"
"  cider rem list                     List all incomplete reminders\n"
"  cider rem add <title>              Add reminder\n"
"  cider rem add <title> <due>        Add reminder with due date\n"
"  cider rem edit <N> <new-title>     Edit reminder N\n"
"  cider rem delete <N>               Delete reminder N\n"
"  cider rem complete <N>             Complete reminder N\n"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Argument parsing helpers
// ─────────────────────────────────────────────────────────────────────────────

NSString *argValue(int argc, char *argv[], int startIdx, const char *flag1, const char *flag2) {
    for (int i = startIdx; i < argc - 1; i++) {
        if ((flag1 && strcmp(argv[i], flag1) == 0) ||
            (flag2 && strcmp(argv[i], flag2) == 0)) {
            return [NSString stringWithUTF8String:argv[i + 1]];
        }
    }
    return nil;
}

BOOL argHasFlag(int argc, char *argv[], int startIdx, const char *flag1, const char *flag2) {
    for (int i = startIdx; i < argc; i++) {
        if ((flag1 && strcmp(argv[i], flag1) == 0) ||
            (flag2 && strcmp(argv[i], flag2) == 0)) {
            return YES;
        }
    }
    return NO;
}

// ─────────────────────────────────────────────────────────────────────────────
// Command registry
// ─────────────────────────────────────────────────────────────────────────────

typedef int (*CiderHandler)(int argc, char *argv[]);

typedef struct {
    const char *parent;     // "notes", "rem", "sync", "templates", "settings"
    const char *name;       // subcommand name
    const char *alias;      // legacy alias (NULL if none)
    const char *brief;      // one-liner for help (NULL = hidden/legacy)
    const char *flags;      // space-separated flags for completions (NULL = none)
    CiderHandler handler;
} CiderCommand;

// ─────────────────────────────────────────────────────────────────────────────
// Notes handlers
// ─────────────────────────────────────────────────────────────────────────────

static int handleNotesList(int argc, char *argv[]) {
    NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
    BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
    NSString *afterStr = argValue(argc, argv, 3, "--after", NULL);
    NSString *beforeStr = argValue(argc, argv, 3, "--before", NULL);
    NSString *sortMode = argValue(argc, argv, 3, "--sort", NULL);
    BOOL pinnedOnly = argHasFlag(argc, argv, 3, "--pinned", NULL);
    NSString *tagFilter = argValue(argc, argv, 3, "--tag", NULL);
    cmdNotesList(folder, jsonOut, afterStr, beforeStr, sortMode, pinnedOnly, tagFilter);
    return 0;
}

static int handleNotesShow(int argc, char *argv[]) {
    NSUInteger idx = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    if (!idx) idx = promptNoteIndex(@"show", nil);
    if (!idx) return 1;
    BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
    return cmdNotesView(idx, nil, jsonOut);
}

static int handleNotesInspect(int argc, char *argv[]) {
    NSUInteger idx = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    NSString *fldr = argValue(argc, argv, 3, "--folder", "-f");
    if (!idx) idx = promptNoteIndex(@"inspect", fldr);
    if (!idx) return 1;
    BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
    return cmdNotesInspect(idx, fldr, jsonOut);
}

static int handleNotesFolders(int argc, char *argv[]) {
    BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
    cmdFoldersList(jsonOut);
    return 0;
}

static int handleNotesAdd(int argc, char *argv[]) {
    NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
    NSString *tmpl = argValue(argc, argv, 3, "--template", NULL);
    if (tmpl) {
        return cmdNotesAddFromTemplate(tmpl, folder);
    }
    cmdNotesAdd(folder);
    return 0;
}

static int handleNotesEdit(int argc, char *argv[]) {
    NSUInteger idx = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    if (!idx) idx = promptNoteIndex(@"edit", nil);
    if (!idx) return 1;
    cmdNotesEdit(idx);
    return 0;
}

static int handleNotesDelete(int argc, char *argv[]) {
    NSUInteger idx = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    if (!idx) idx = promptNoteIndex(@"delete", nil);
    if (!idx) return 1;
    cmdNotesDelete(idx);
    return 0;
}

static int handleNotesMove(int argc, char *argv[]) {
    NSUInteger idx = 0;
    NSString *targetFolder = nil;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    if (!idx) idx = promptNoteIndex(@"move", nil);
    if (!idx) return 1;
    targetFolder = argValue(argc, argv, 3, "--folder", "-f");
    if (!targetFolder && argc >= 5) {
        const char *arg4 = argv[4];
        if (arg4[0] != '-') {
            targetFolder = [NSString stringWithUTF8String:arg4];
        }
    }
    if (!targetFolder) {
        fprintf(stderr, "Usage: cider notes move <N> <folder>\n");
        return 1;
    }
    cmdNotesMove(idx, targetFolder);
    return 0;
}

static NSString *collectTextOrStdin(int argc, char *argv[], int startIdx) {
    // Collect non-flag arguments as text (priority over stdin)
    NSMutableArray *parts = [NSMutableArray array];
    for (int i = startIdx; i < argc; i++) {
        if (strcmp(argv[i], "--no-newline") == 0 ||
            strcmp(argv[i], "--folder") == 0 ||
            strcmp(argv[i], "-f") == 0) {
            if (strcmp(argv[i], "--folder") == 0 ||
                strcmp(argv[i], "-f") == 0) i++; // skip value
            continue;
        }
        [parts addObject:[NSString stringWithUTF8String:argv[i]]];
    }
    if (parts.count > 0) {
        return [parts componentsJoinedByString:@" "];
    }

    // Fall back to stdin if no argument text
    if (!isatty(STDIN_FILENO)) {
        NSFileHandle *fh = [NSFileHandle fileHandleWithStandardInput];
        NSData *data = [fh readDataToEndOfFile];
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if ([text hasSuffix:@"\n"]) {
            text = [text substringToIndex:[text length] - 1];
        }
        return text;
    }
    return nil;
}

static int handleNotesAppend(int argc, char *argv[]) {
    NSUInteger idx = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
    BOOL noNewline = argHasFlag(argc, argv, 3, "--no-newline", NULL);
    if (!idx) idx = promptNoteIndex(@"append to", folder);
    if (!idx) return 1;

    NSString *text = collectTextOrStdin(argc, argv, 4);
    if (!text || [text length] == 0) {
        fprintf(stderr, "Error: No text provided. Pass text as argument or pipe from stdin.\n");
        return 1;
    }
    return cmdNotesAppend(idx, text, folder, noNewline);
}

static int handleNotesPrepend(int argc, char *argv[]) {
    NSUInteger idx = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
    BOOL noNewline = argHasFlag(argc, argv, 3, "--no-newline", NULL);
    if (!idx) idx = promptNoteIndex(@"prepend to", folder);
    if (!idx) return 1;

    NSString *text = collectTextOrStdin(argc, argv, 4);
    if (!text || [text length] == 0) {
        fprintf(stderr, "Error: No text provided. Pass text as argument or pipe from stdin.\n");
        return 1;
    }
    return cmdNotesPrepend(idx, text, folder, noNewline);
}

static int handleNotesDebug(int argc, char *argv[]) {
    NSUInteger idx = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
    if (!idx) idx = promptNoteIndex(@"debug", folder);
    if (!idx) return 1;
    cmdNotesDebug(idx, folder);
    return 0;
}

static int handleNotesHistory(int argc, char *argv[]) {
    NSUInteger idx = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
    if (!idx) idx = promptNoteIndex(@"history", folder);
    if (!idx) return 1;
    BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
    BOOL rawOut = argHasFlag(argc, argv, 3, "--raw", NULL);
    BOOL blameOut = argHasFlag(argc, argv, 3, "--blame", NULL);
    cmdNotesHistory(idx, folder, jsonOut, rawOut, blameOut);
    return 0;
}

static int handleNotesGetdate(int argc, char *argv[]) {
    NSUInteger idx = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
    if (!idx) idx = promptNoteIndex(@"get date of", folder);
    if (!idx) return 1;
    BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
    return cmdNotesGetdate(idx, folder, jsonOut);
}

static int handleNotesSetdate(int argc, char *argv[]) {
    NSUInteger idx = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
    if (!idx) idx = promptNoteIndex(@"set date on", folder);
    if (!idx) return 1;
    BOOL dryRun = argHasFlag(argc, argv, 3, "--dry-run", NULL);
    NSString *dateStr = nil;
    for (int i = 4; i < argc; i++) {
        if (argv[i][0] != '-') {
            dateStr = [NSString stringWithUTF8String:argv[i]];
            break;
        }
    }
    if (!dateStr) {
        fprintf(stderr, "Usage: cider notes setdate <N> <ISO-date> [--dry-run]\n");
        return 1;
    }
    return cmdNotesSetdate(idx, dateStr, folder, dryRun);
}

static int handleNotesPin(int argc, char *argv[]) {
    NSUInteger idx = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
    if (!idx) idx = promptNoteIndex(@"pin", folder);
    if (!idx) return 1;
    return cmdNotesPin(idx, folder);
}

static int handleNotesUnpin(int argc, char *argv[]) {
    NSUInteger idx = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
    if (!idx) idx = promptNoteIndex(@"unpin", folder);
    if (!idx) return 1;
    return cmdNotesUnpin(idx, folder);
}

static int handleNotesWatch(int argc, char *argv[]) {
    NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
    BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
    NSTimeInterval interval = 2.0;
    NSString *intStr = argValue(argc, argv, 3, "--interval", NULL);
    if (intStr) interval = [intStr doubleValue];
    if (!intStr) {
        NSString *settingInterval = getCiderSetting(@"watch_interval");
        if (settingInterval) interval = [settingInterval doubleValue];
    }
    if (interval < 0.5) interval = 0.5;
    cmdNotesWatch(folder, interval, jsonOut);
    return 0; // never reached (infinite loop)
}

static int handleNotesLinks(int argc, char *argv[]) {
    NSUInteger idx = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
    BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
    if (!idx) idx = promptNoteIndex(@"show links for", folder);
    if (!idx) return 1;
    cmdNotesLinks(idx, folder, jsonOut);
    return 0;
}

static int handleNotesBacklinks(int argc, char *argv[]) {
    BOOL allLinks = argHasFlag(argc, argv, 3, "--all", NULL);
    BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
    if (allLinks) {
        cmdNotesBacklinksAll(jsonOut);
    } else {
        NSUInteger idx = 0;
        if (argc >= 4) {
            int v = atoi(argv[3]);
            if (v > 0) idx = (NSUInteger)v;
        }
        NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
        if (!idx) idx = promptNoteIndex(@"show backlinks for", folder);
        if (!idx) return 1;
        cmdNotesBacklinks(idx, folder, jsonOut);
    }
    return 0;
}

static int handleNotesLink(int argc, char *argv[]) {
    NSUInteger idx = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
    NSString *target = nil;
    if (argc >= 5) {
        NSMutableArray *parts = [NSMutableArray array];
        for (int i = 4; i < argc; i++) {
            NSString *a = [NSString stringWithUTF8String:argv[i]];
            if ([a hasPrefix:@"--"] || [a hasPrefix:@"-f"]) break;
            [parts addObject:a];
        }
        if (parts.count > 0)
            target = [parts componentsJoinedByString:@" "];
    }
    if (!idx) idx = promptNoteIndex(@"link from", folder);
    if (!idx) return 1;
    if (!target || target.length == 0) {
        fprintf(stderr, "Usage: cider notes link <N> <target note title>\n");
        return 1;
    }
    return cmdNotesLink(idx, target, folder);
}

static int handleNotesShare(int argc, char *argv[]) {
    NSUInteger idx = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
    BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
    if (!idx) idx = promptNoteIndex(@"show share status for", folder);
    if (!idx) return 1;
    cmdNotesShare(idx, folder, jsonOut);
    return 0;
}

static int handleNotesShared(int argc, char *argv[]) {
    BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
    cmdNotesShared(jsonOut);
    return 0;
}

static int handleNotesTable(int argc, char *argv[]) {
    NSUInteger idx = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
    if (!idx) idx = promptNoteIndex(@"show table for", folder);
    if (!idx) return 1;
    BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
    BOOL csvOut = argHasFlag(argc, argv, 3, "--csv", NULL);
    BOOL listTables = argHasFlag(argc, argv, 3, "--list", NULL);
    BOOL headersOnly = argHasFlag(argc, argv, 3, "--headers", NULL);
    NSUInteger tableIdx = 0;
    NSString *indexStr = argValue(argc, argv, 3, "--index", NULL);
    if (indexStr) tableIdx = (NSUInteger)[indexStr intValue];
    NSInteger rowNum = -1;
    NSString *rowStr = argValue(argc, argv, 3, "--row", NULL);
    if (rowStr) rowNum = [rowStr integerValue];

    // Collect --add-row arguments (can be repeated)
    NSMutableArray *addRows = [NSMutableArray array];
    for (int i = 3; i < argc; i++) {
        if (strcmp(argv[i], "--add-row") == 0 && i + 1 < argc) {
            [addRows addObject:[NSString stringWithUTF8String:argv[++i]]];
        }
    }
    if (addRows.count > 0) {
        return cmdNotesTableAdd(idx, folder, addRows);
    }

    cmdNotesTable(idx, folder, tableIdx, jsonOut, csvOut, listTables, headersOnly, rowNum);
    return 0;
}

static int handleNotesChecklist(int argc, char *argv[]) {
    NSUInteger idx = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
    if (!idx) idx = promptNoteIndex(@"show checklist for", folder);
    if (!idx) return 1;
    BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
    BOOL summary = argHasFlag(argc, argv, 3, "--summary", NULL);
    NSString *addText = argValue(argc, argv, 3, "--add", NULL);
    cmdNotesChecklist(idx, folder, jsonOut, summary, addText);
    return 0;
}

static int handleNotesCheck(int argc, char *argv[]) {
    NSUInteger idx = 0;
    NSUInteger itemNum = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    if (argc >= 5) {
        int v = atoi(argv[4]);
        if (v > 0) itemNum = (NSUInteger)v;
    }
    NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
    if (!idx) idx = promptNoteIndex(@"check item in", folder);
    if (!idx) return 1;
    if (!itemNum) {
        fprintf(stderr, "Usage: cider notes check <N> <item#>\n");
        return 1;
    }
    return cmdNotesCheck(idx, itemNum, folder);
}

static int handleNotesUncheck(int argc, char *argv[]) {
    NSUInteger idx = 0;
    NSUInteger itemNum = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    if (argc >= 5) {
        int v = atoi(argv[4]);
        if (v > 0) itemNum = (NSUInteger)v;
    }
    NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
    if (!idx) idx = promptNoteIndex(@"uncheck item in", folder);
    if (!idx) return 1;
    if (!itemNum) {
        fprintf(stderr, "Usage: cider notes uncheck <N> <item#>\n");
        return 1;
    }
    return cmdNotesUncheck(idx, itemNum, folder);
}

static int handleNotesFolder(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider notes folder create|delete|rename ...\n");
        return 1;
    }
    NSString *action = [NSString stringWithUTF8String:argv[3]];
    if ([action isEqualToString:@"create"]) {
        if (argc < 5) {
            fprintf(stderr, "Usage: cider notes folder create <name> [--parent <p>]\n");
            return 1;
        }
        NSString *name = [NSString stringWithUTF8String:argv[4]];
        NSString *parent = argValue(argc, argv, 5, "--parent", NULL);
        return cmdFolderCreate(name, parent);
    } else if ([action isEqualToString:@"delete"]) {
        if (argc < 5) {
            fprintf(stderr, "Usage: cider notes folder delete <name>\n");
            return 1;
        }
        NSString *name = [NSString stringWithUTF8String:argv[4]];
        return cmdFolderDelete(name);
    } else if ([action isEqualToString:@"rename"]) {
        if (argc < 6) {
            fprintf(stderr, "Usage: cider notes folder rename <old> <new>\n");
            return 1;
        }
        NSString *oldName = [NSString stringWithUTF8String:argv[4]];
        NSString *newName = [NSString stringWithUTF8String:argv[5]];
        return cmdFolderRename(oldName, newName);
    } else {
        fprintf(stderr, "Unknown folder action: %s\n", [action UTF8String]);
        return 1;
    }
}

static int handleNotesTag(int argc, char *argv[]) {
    NSUInteger idx = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
    if (!idx) idx = promptNoteIndex(@"tag", folder);
    if (!idx) return 1;
    if (argc < 5) {
        fprintf(stderr, "Usage: cider notes tag <N> <tag>\n");
        return 1;
    }
    // Find the tag argument (first non-flag arg after index)
    NSString *tag = nil;
    for (int i = 4; i < argc; i++) {
        if (strcmp(argv[i], "--folder") == 0 || strcmp(argv[i], "-f") == 0) {
            i++; continue;
        }
        tag = [NSString stringWithUTF8String:argv[i]];
        break;
    }
    if (!tag) {
        fprintf(stderr, "Usage: cider notes tag <N> <tag>\n");
        return 1;
    }
    return cmdNotesTag(idx, tag, folder);
}

static int handleNotesUntag(int argc, char *argv[]) {
    NSUInteger idx = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
    if (!idx) idx = promptNoteIndex(@"untag", folder);
    if (!idx) return 1;
    if (argc < 5) {
        fprintf(stderr, "Usage: cider notes untag <N> <tag>\n");
        return 1;
    }
    NSString *tag = nil;
    for (int i = 4; i < argc; i++) {
        if (strcmp(argv[i], "--folder") == 0 || strcmp(argv[i], "-f") == 0) {
            i++; continue;
        }
        tag = [NSString stringWithUTF8String:argv[i]];
        break;
    }
    if (!tag) {
        fprintf(stderr, "Usage: cider notes untag <N> <tag>\n");
        return 1;
    }
    return cmdNotesUntag(idx, tag, folder);
}

static int handleNotesTags(int argc, char *argv[]) {
    BOOL withCounts = argHasFlag(argc, argv, 3, "--count", NULL);
    BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
    BOOL clean = argHasFlag(argc, argv, 3, "--clean", NULL);
    if (clean) return cmdTagsClean();
    cmdNotesTags(withCounts, jsonOut);
    return 0;
}

static int handleNotesReplace(int argc, char *argv[]) {
    BOOL useRegex = argHasFlag(argc, argv, 3, "--regex", NULL);
    BOOL caseInsensitive = argHasFlag(argc, argv, 3, "-i", "--case-insensitive");
    BOOL replaceAll = argHasFlag(argc, argv, 3, "--all", NULL);
    NSString *findStr = argValue(argc, argv, 3, "--find", NULL);
    NSString *replaceStr = argValue(argc, argv, 3, "--replace", NULL);

    if (replaceAll) {
        if (!findStr || !replaceStr) {
            fprintf(stderr, "Usage: cider notes replace --all --find <text> --replace <text> [--folder <f>] [--regex] [-i] [--dry-run]\n");
            return 1;
        }
        NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
        BOOL dryRun = argHasFlag(argc, argv, 3, "--dry-run", NULL);
        return cmdNotesReplaceAll(findStr, replaceStr, folder,
                                 useRegex, caseInsensitive, dryRun);
    }

    NSUInteger idx = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    if (!idx) idx = promptNoteIndex(@"replace", nil);
    if (!idx) return 1;
    if (!findStr || !replaceStr) {
        fprintf(stderr, "Usage: cider notes replace <N> --find <text> --replace <text> [--regex] [-i]\n");
        return 1;
    }
    return cmdNotesReplace(idx, findStr, replaceStr, useRegex, caseInsensitive);
}

static int handleNotesSearch(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider notes search <query> [--regex] [--title] [--body] [-f <folder>] [--json]\n");
        return 1;
    }
    NSString *query = [NSString stringWithUTF8String:argv[3]];
    BOOL jsonOut = argHasFlag(argc, argv, 4, "--json", NULL);
    BOOL useRegex = argHasFlag(argc, argv, 4, "--regex", NULL);
    BOOL titleOnly = argHasFlag(argc, argv, 4, "--title", NULL);
    BOOL bodyOnly = argHasFlag(argc, argv, 4, "--body", NULL);
    NSString *folder = argValue(argc, argv, 4, "--folder", "-f");
    NSString *afterStr = argValue(argc, argv, 4, "--after", NULL);
    NSString *beforeStr = argValue(argc, argv, 4, "--before", NULL);
    NSString *tagFilter = argValue(argc, argv, 4, "--tag", NULL);
    if (titleOnly && bodyOnly) {
        fprintf(stderr, "Error: --title and --body are mutually exclusive\n");
        return 1;
    }
    cmdNotesSearch(query, jsonOut, useRegex, titleOnly, bodyOnly, folder, afterStr, beforeStr, tagFilter);
    return 0;
}

static int handleNotesExport(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider notes export <path>\n");
        return 1;
    }
    NSString *path = [NSString stringWithUTF8String:argv[3]];
    cmdNotesExport(path);
    return 0;
}

static int handleNotesAttachments(int argc, char *argv[]) {
    NSUInteger idx = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    if (!idx) idx = promptNoteIndex(@"list attachments for", nil);
    if (!idx) return 1;
    BOOL json = NO;
    for (int ai = 4; ai < argc; ai++) {
        if (strcmp(argv[ai], "--json") == 0) { json = YES; break; }
    }
    cmdNotesAttachments(idx, json);
    return 0;
}

static int handleNotesDetach(int argc, char *argv[]) {
    NSUInteger idx = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    if (!idx) idx = promptNoteIndex(@"detach from", nil);
    if (!idx) return 1;

    NSUInteger attIdx = 0;
    if (argc >= 5) {
        attIdx = (NSUInteger)(atoi(argv[4]) - 1);
    } else {
        id note = noteAtIndex(idx, nil);
        if (note) {
            NSArray *orderedIDs = attachmentOrderFromCRDT(note);
            NSArray *atts = attachmentsAsArray(noteVisibleAttachments(note));
            NSUInteger inlineCount = orderedIDs ? orderedIDs.count : 0;
            if (inlineCount == 0) {
                fprintf(stderr, "Note %lu has no inline attachments.\n", (unsigned long)idx);
                return 1;
            }
            printf("Attachments in note %lu:\n", (unsigned long)idx);
            for (NSUInteger i = 0; i < inlineCount; i++) {
                id val = orderedIDs[i];
                NSString *aName = (val != [NSNull null])
                    ? attachmentNameByID(atts, val) : @"attachment";
                printf("  %lu. %s\n", (unsigned long)(i + 1), [aName UTF8String]);
            }
            if (inlineCount == 1) {
                attIdx = 0;
                printf("Removing the only attachment.\n");
            } else {
                printf("Remove which attachment? [1-%lu]: ", (unsigned long)inlineCount);
                fflush(stdout);
                char buf[32];
                if (fgets(buf, sizeof(buf), stdin)) {
                    int v = atoi(buf);
                    if (v < 1 || (NSUInteger)v > inlineCount) {
                        fprintf(stderr, "Invalid selection.\n");
                        return 1;
                    }
                    attIdx = (NSUInteger)(v - 1);
                }
            }
        }
    }
    cmdNotesDetach(idx, attIdx);
    return 0;
}

static int handleNotesAttach(int argc, char *argv[]) {
    NSUInteger idx = 0;
    if (argc >= 4) {
        int v = atoi(argv[3]);
        if (v > 0) idx = (NSUInteger)v;
    }
    if (!idx) idx = promptNoteIndex(@"attach", nil);
    if (!idx) return 1;
    if (argc < 5) {
        fprintf(stderr, "Usage: cider notes attach <N> <file>\n");
        return 1;
    }
    NSString *filePath = [NSString stringWithUTF8String:argv[4]];

    NSInteger atPos = -1;
    for (int ai = 5; ai < argc - 1; ai++) {
        if (strcmp(argv[ai], "--at") == 0) {
            atPos = (NSInteger)atoi(argv[ai + 1]);
            break;
        }
    }
    if (atPos >= 0) {
        cmdNotesAttachAt(idx, filePath, (NSUInteger)atPos);
    } else {
        cmdNotesAttach(idx, filePath);
    }
    return 0;
}

// ── Legacy notes aliases ────────────────────────────────────────────────────

static int handleNotesLegacyFl(int argc, char *argv[]) {
    (void)argc; (void)argv;
    cmdFoldersList(NO);
    return 0;
}

static int handleNotesLegacyF(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider notes -f <folder>\n");
        return 1;
    }
    NSString *folder = [NSString stringWithUTF8String:argv[3]];
    cmdNotesList(folder, NO, nil, nil, nil, NO, nil);
    return 0;
}

static int handleNotesLegacyV(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider notes -v <N>\n");
        return 1;
    }
    NSUInteger idx = (NSUInteger)atoi(argv[3]);
    cmdNotesView(idx, nil, NO);
    return 0;
}

static int handleNotesLegacyA(int argc, char *argv[]) {
    NSString *folder = nil;
    for (int i = 3; i < argc - 1; i++) {
        if (strcmp(argv[i], "-f") == 0) {
            folder = [NSString stringWithUTF8String:argv[i + 1]];
        }
    }
    cmdNotesAdd(folder);
    return 0;
}

static int handleNotesLegacyE(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider notes -e <N>\n");
        return 1;
    }
    NSUInteger idx = (NSUInteger)atoi(argv[3]);
    cmdNotesEdit(idx);
    return 0;
}

static int handleNotesLegacyD(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider notes -d <N>\n");
        return 1;
    }
    NSUInteger idx = (NSUInteger)atoi(argv[3]);
    cmdNotesDelete(idx);
    return 0;
}

static int handleNotesLegacyM(int argc, char *argv[]) {
    if (argc < 6 || strcmp(argv[4], "-f") != 0) {
        fprintf(stderr, "Usage: cider notes -m <N> -f <folder>\n");
        return 1;
    }
    NSUInteger idx = (NSUInteger)atoi(argv[3]);
    NSString *folder = [NSString stringWithUTF8String:argv[5]];
    cmdNotesMove(idx, folder);
    return 0;
}

static int handleNotesLegacyS(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider notes -s <query>\n");
        return 1;
    }
    NSString *query = [NSString stringWithUTF8String:argv[3]];
    cmdNotesSearch(query, NO, NO, NO, NO, nil, nil, nil, nil);
    return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Templates handlers
// ─────────────────────────────────────────────────────────────────────────────

static int handleTemplatesList(int argc, char *argv[]) {
    (void)argc; (void)argv;
    cmdTemplatesList();
    return 0;
}

static int handleTemplatesShow(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider templates show <name>\n");
        return 1;
    }
    NSString *name = [NSString stringWithUTF8String:argv[3]];
    return cmdTemplatesShow(name);
}

static int handleTemplatesAdd(int argc, char *argv[]) {
    (void)argc; (void)argv;
    cmdTemplatesAdd();
    return 0;
}

static int handleTemplatesDelete(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider templates delete <name>\n");
        return 1;
    }
    NSString *name = [NSString stringWithUTF8String:argv[3]];
    return cmdTemplatesDelete(name);
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings handlers
// ─────────────────────────────────────────────────────────────────────────────

static int handleSettingsGet(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider settings get <key>\n");
        return 1;
    }
    NSString *key = [NSString stringWithUTF8String:argv[3]];
    return cmdSettingsGet(key);
}

static int handleSettingsSet(int argc, char *argv[]) {
    if (argc < 5) {
        fprintf(stderr, "Usage: cider settings set <key> <value>\n");
        return 1;
    }
    NSString *key = [NSString stringWithUTF8String:argv[3]];
    // Join remaining args as value (allows spaces without quoting)
    NSMutableArray *valParts = [NSMutableArray array];
    for (int i = 4; i < argc; i++) {
        [valParts addObject:[NSString stringWithUTF8String:argv[i]]];
    }
    NSString *value = [valParts componentsJoinedByString:@" "];
    return cmdSettingsSet(key, value);
}

static int handleSettingsReset(int argc, char *argv[]) {
    (void)argc; (void)argv;
    return cmdSettingsReset();
}

// ─────────────────────────────────────────────────────────────────────────────
// Sync handlers
// ─────────────────────────────────────────────────────────────────────────────

static int handleSyncBackup(int argc, char *argv[]) {
    NSString *syncDir = argValue(argc, argv, 3, "--dir", "-d") ?: syncDefaultDir();
    if (!initNotesContext()) return 1;
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:syncDir withIntermediateDirectories:YES attributes:nil error:nil];
    return cmdSyncBackup(syncDir);
}

static int handleSyncRun(int argc, char *argv[]) {
    NSString *syncDir = argValue(argc, argv, 3, "--dir", "-d") ?: syncDefaultDir();
    if (!initNotesContext()) return 1;
    return cmdSyncRun(syncDir);
}

static int handleSyncWatch(int argc, char *argv[]) {
    NSString *syncDir = argValue(argc, argv, 3, "--dir", "-d") ?: syncDefaultDir();
    if (!initNotesContext()) return 1;
    NSTimeInterval interval = 2.0;
    NSString *intStr = argValue(argc, argv, 3, "--interval", "-i");
    if (intStr) interval = [intStr doubleValue];
    if (interval < 0.5) interval = 0.5;
    return cmdSyncWatch(syncDir, interval);
}

// ─────────────────────────────────────────────────────────────────────────────
// Reminders handlers
// ─────────────────────────────────────────────────────────────────────────────

static int handleRemList(int argc, char *argv[]) {
    (void)argc; (void)argv;
    cmdRemList();
    return 0;
}

static int handleRemAdd(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider rem add <title> [due-date]\n");
        return 1;
    }
    NSString *title = [NSString stringWithUTF8String:argv[3]];
    NSString *due = (argc >= 5) ? [NSString stringWithUTF8String:argv[4]] : nil;
    cmdRemAdd(title, due);
    return 0;
}

static int handleRemEdit(int argc, char *argv[]) {
    if (argc < 5) {
        fprintf(stderr, "Usage: cider rem edit <N> <new-title>\n");
        return 1;
    }
    NSUInteger idx = (NSUInteger)atoi(argv[3]);
    NSString *title = [NSString stringWithUTF8String:argv[4]];
    cmdRemEdit(idx, title);
    return 0;
}

static int handleRemDelete(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider rem delete <N>\n");
        return 1;
    }
    NSUInteger idx = (NSUInteger)atoi(argv[3]);
    cmdRemDelete(idx);
    return 0;
}

static int handleRemComplete(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider rem complete <N>\n");
        return 1;
    }
    NSUInteger idx = (NSUInteger)atoi(argv[3]);
    cmdRemComplete(idx);
    return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// msg handlers
// ─────────────────────────────────────────────────────────────────────────────

static NSString *collectTextOrStdinMsg(int argc, char *argv[], int startIdx) {
    if (startIdx < argc) {
        NSMutableArray *parts = [NSMutableArray array];
        for (int i = startIdx; i < argc; i++) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg hasPrefix:@"--"]) break;
            [parts addObject:arg];
        }
        if (parts.count > 0)
            return [parts componentsJoinedByString:@" "];
    }
    // Try stdin
    if (!isatty(STDIN_FILENO)) {
        NSFileHandle *fh = [NSFileHandle fileHandleWithStandardInput];
        NSData *data = [fh readDataToEndOfFile];
        if (data.length > 0) {
            NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            // Trim trailing newline
            if ([s hasSuffix:@"\n"])
                s = [s substringToIndex:s.length - 1];
            return s;
        }
    }
    return nil;
}

static int handleMsgList(int argc, char *argv[]) {
    NSString *limitStr = argValue(argc, argv, 3, "--limit", "-n");
    NSUInteger limit = limitStr ? (NSUInteger)[limitStr intValue] : 0;
    BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
    NSString *service = argValue(argc, argv, 3, "--service", NULL);
    cmdMsgList(limit, jsonOut, service);
    return 0;
}

static int handleMsgContext(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider msg context <message-guid> [options]\n"
                        "  --context N    Messages before/after (default 10)\n"
                        "  --before       Only older messages\n"
                        "  --after        Only newer messages\n"
                        "  --json         JSON output\n");
        return 1;
    }
    NSString *ctxStr = argValue(argc, argv, 4, "--context", "-c");
    NSUInteger ctx = ctxStr ? (NSUInteger)[ctxStr intValue] : 10;
    BOOL jsonOut = argHasFlag(argc, argv, 4, "--json", NULL);
    const char *dir = NULL;
    if (argHasFlag(argc, argv, 4, "--before", NULL)) dir = "before";
    else if (argHasFlag(argc, argv, 4, "--after", NULL)) dir = "after";
    cmdMsgContext(argv[3], ctx, jsonOut, dir);
    return 0;
}

static int handleMsgShow(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider msg show <chat> [options]\n");
        return 1;
    }
    NSString *limitStr = argValue(argc, argv, 4, "--limit", "-n");
    NSUInteger limit = limitStr ? (NSUInteger)[limitStr intValue] : 0;
    BOOL jsonOut = argHasFlag(argc, argv, 4, "--json", NULL);
    NSString *afterStr = argValue(argc, argv, 4, "--after", NULL);
    NSString *beforeStr = argValue(argc, argv, 4, "--before", NULL);
    NSString *sortStr = argValue(argc, argv, 4, "--sort", NULL);
    BOOL sortAsc = sortStr && strcasecmp([sortStr UTF8String], "asc") == 0;
    cmdMsgShow(argv[3], limit, jsonOut, afterStr, beforeStr, sortAsc);
    return 0;
}

static int handleMsgSearch(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider msg search <query> [options]\n");
        return 1;
    }
    NSString *query = [NSString stringWithUTF8String:argv[3]];
    NSString *limitStr = argValue(argc, argv, 4, "--limit", "-n");
    NSUInteger limit = limitStr ? (NSUInteger)[limitStr intValue] : 0;
    BOOL jsonOut = argHasFlag(argc, argv, 4, "--json", NULL);
    BOOL fzfOut = argHasFlag(argc, argv, 4, "--fzf", NULL);
    NSString *sortStr = argValue(argc, argv, 4, "--sort", NULL);
    BOOL sortAsc = sortStr && strcasecmp([sortStr UTF8String], "asc") == 0;

    if (fzfOut) {
        // Pipe search results through fzf, then show context in less

        // Build a pipe: search --fzf | fzf | cut -f1
        // We write search results to a temp file, then exec fzf on it
        NSString *tmpFile = [NSTemporaryDirectory()
            stringByAppendingPathComponent:@"cider-msg-search.tsv"];
        FILE *saved = freopen([tmpFile UTF8String], "w", stdout);
        if (!saved) {
            fprintf(stderr, "Cannot create temp file\n");
            return 1;
        }
        cmdMsgSearch(query, limit, NO, sortAsc, YES);
        fflush(stdout);
        freopen("/dev/tty", "w", stdout);

        // Check if there were any results
        NSDictionary *attrs = [[NSFileManager defaultManager]
            attributesOfItemAtPath:tmpFile error:nil];
        if (!attrs || [attrs fileSize] == 0) {
            printf("No messages found matching \"%s\"\n",
                   [query UTF8String]);
            return 1;
        }

        // Run fzf
        NSString *fzfCmd = [NSString stringWithFormat:
            @"cat '%@' | fzf --delimiter='\\t' --with-nth=2.. "
            @"--preview-window=hidden --no-multi "
            @"--header='Select a message to view in context'",
            tmpFile];
        FILE *fzf = popen([fzfCmd UTF8String], "r");
        if (!fzf) {
            fprintf(stderr, "Cannot run fzf. Is it installed?\n");
            return 1;
        }
        char buf[4096];
        NSMutableString *selection = [NSMutableString string];
        while (fgets(buf, sizeof(buf), fzf)) {
            [selection appendString:[NSString stringWithUTF8String:buf]];
        }
        int fzfExit = pclose(fzf);
        [[NSFileManager defaultManager] removeItemAtPath:tmpFile error:nil];

        if (fzfExit != 0 || selection.length == 0) {
            return 0; // User cancelled fzf
        }

        // Extract GUID (first tab-delimited field)
        NSString *guid = [[selection componentsSeparatedByString:@"\t"]
            firstObject];
        guid = [guid stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (guid.length > 0) {
            // Dump a large context window to a temp file, then open in less
            // jumping to the target message (marked with >>>)
            NSString *ctxFile = [NSTemporaryDirectory()
                stringByAppendingPathComponent:@"cider-msg-context.txt"];
            FILE *cf = freopen([ctxFile UTF8String], "w", stdout);
            if (!cf) {
                freopen("/dev/tty", "w", stdout);
                fprintf(stderr, "Cannot create temp file\n");
                return 1;
            }
            // Use a large context window so there's plenty to scroll
            cmdMsgContext([guid UTF8String], 500, NO, NULL);
            fflush(stdout);
            freopen("/dev/tty", "w", stdout);

            // Open in less, jumping to the >>> marker
            NSString *lessCmd = [NSString stringWithFormat:
                @"less -R '+/^>>>' '%@'", ctxFile];
            int rc = system([lessCmd UTF8String]);
            [[NSFileManager defaultManager] removeItemAtPath:ctxFile error:nil];
            return rc == 0 ? 0 : 1;
        }
        return 0;
    }

    cmdMsgSearch(query, limit, jsonOut, sortAsc, NO);
    return 0;
}

static int handleMsgCount(int argc, char *argv[]) {
    BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
    const char *chatRef = NULL;
    if (argc >= 4 && argv[3][0] != '-') chatRef = argv[3];
    cmdMsgCount(chatRef, jsonOut);
    return 0;
}

static int handleMsgContacts(int argc, char *argv[]) {
    NSString *limitStr = argValue(argc, argv, 3, "--limit", "-n");
    NSUInteger limit = limitStr ? (NSUInteger)[limitStr intValue] : 0;
    BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
    NSString *service = argValue(argc, argv, 3, "--service", NULL);
    cmdMsgContacts(limit, jsonOut, service);
    return 0;
}

static int handleMsgInfo(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider msg info <chat>\n");
        return 1;
    }
    BOOL jsonOut = argHasFlag(argc, argv, 4, "--json", NULL);
    cmdMsgInfo(argv[3], jsonOut);
    return 0;
}

static int handleMsgAttachments(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider msg attachments <chat>\n");
        return 1;
    }
    NSString *limitStr = argValue(argc, argv, 4, "--limit", "-n");
    NSUInteger limit = limitStr ? (NSUInteger)[limitStr intValue] : 0;
    BOOL jsonOut = argHasFlag(argc, argv, 4, "--json", NULL);
    cmdMsgAttachments(argv[3], limit, jsonOut);
    return 0;
}

static int handleMsgSend(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider msg send <recipient> <message>\n");
        return 1;
    }
    NSString *service = argValue(argc, argv, 4, "--service", NULL);
    NSString *text = collectTextOrStdinMsg(argc, argv, 4);
    if (!text) {
        fprintf(stderr, "No message provided. Provide text or pipe via stdin.\n");
        return 1;
    }
    return cmdMsgSend(argv[3], text, service);
}

static int handleMsgAttachFile(int argc, char *argv[]) {
    if (argc < 5) {
        fprintf(stderr, "Usage: cider msg attach <recipient> <file>\n");
        return 1;
    }
    NSString *service = argValue(argc, argv, 5, "--service", NULL);
    NSString *filePath = [NSString stringWithUTF8String:argv[4]];
    // Expand ~ in path
    filePath = [filePath stringByExpandingTildeInPath];
    return cmdMsgAttach(argv[3], filePath, service);
}

static int handleMsgReact(int argc, char *argv[]) {
    if (argc < 5) {
        fprintf(stderr, "Usage: cider msg react <chat> <msg-index> <reaction>\n"
                        "  Reactions: love, like, dislike, laugh, emphasize, question\n");
        return 1;
    }
    return cmdMsgReact(argv[3], atoi(argv[4]),
                       argc >= 6 ? argv[5] : NULL);
}

static int handleMsgRead(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider msg read <chat>\n");
        return 1;
    }
    return cmdMsgRead(argv[3]);
}

static int handleMsgUnread(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider msg unread <chat>\n");
        return 1;
    }
    return cmdMsgUnread(argv[3]);
}

static int handleMsgDelete(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider msg delete <chat>\n");
        return 1;
    }
    return cmdMsgDelete(argv[3]);
}

static int handleMsgTyping(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider msg typing <chat>\n");
        return 1;
    }
    return cmdMsgTyping(argv[3]);
}

static int handleMsgEdit(int argc, char *argv[]) {
    if (argc < 5) {
        fprintf(stderr, "Usage: cider msg edit <message-guid> <new-text>\n");
        return 1;
    }
    NSString *text = collectTextOrStdinMsg(argc, argv, 4);
    return cmdMsgEdit(argv[3], text);
}

static int handleMsgUnsend(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider msg unsend <message-guid>\n");
        return 1;
    }
    return cmdMsgUnsend(argv[3]);
}

static int handleMsgGroup(int argc, char *argv[]) {
    if (argc < 4) {
        printMsgSubcommandHelp("group");
        return 1;
    }
    const char *action = argv[3];
    if (strcmp(action, "new") == 0) {
        if (argc < 5) {
            fprintf(stderr, "Usage: cider msg group new <addr1> [addr2] ...\n");
            return 1;
        }
        NSString *message = argValue(argc, argv, 4, "--message", "-m");
        NSString *service = argValue(argc, argv, 4, "--service", NULL);
        // Collect addresses (non-flag args after "new")
        int addrStart = 4;
        int addrCount = 0;
        char *addrs[64];
        for (int i = addrStart; i < argc && addrCount < 64; i++) {
            if (argv[i][0] == '-') {
                // Skip flag and its value
                if (strcmp(argv[i], "--message") == 0 || strcmp(argv[i], "-m") == 0 ||
                    strcmp(argv[i], "--service") == 0) {
                    i++; // skip value
                }
                continue;
            }
            addrs[addrCount++] = argv[i];
        }
        return cmdMsgGroupNew(addrCount, addrs, message, service);
    } else if (strcmp(action, "rename") == 0) {
        if (argc < 6) {
            fprintf(stderr, "Usage: cider msg group rename <chat> <name>\n");
            return 1;
        }
        return cmdMsgGroupRename(argv[4],
            [NSString stringWithUTF8String:argv[5]]);
    } else if (strcmp(action, "add") == 0) {
        if (argc < 6) {
            fprintf(stderr, "Usage: cider msg group add <chat> <address>\n");
            return 1;
        }
        return cmdMsgGroupAdd(argv[4], argv[5]);
    } else if (strcmp(action, "remove") == 0) {
        if (argc < 6) {
            fprintf(stderr, "Usage: cider msg group remove <chat> <address>\n");
            return 1;
        }
        return cmdMsgGroupRemove(argv[4], argv[5]);
    } else if (strcmp(action, "leave") == 0) {
        if (argc < 5) {
            fprintf(stderr, "Usage: cider msg group leave <chat>\n");
            return 1;
        }
        return cmdMsgGroupLeave(argv[4]);
    } else {
        fprintf(stderr, "Unknown group action: %s\n", action);
        printMsgSubcommandHelp("group");
        return 1;
    }
}

static int handleMsgSchedule(int argc, char *argv[]) {
    BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
    cmdMsgScheduleList(jsonOut);
    return 0;
}

static int handleMsgCheck(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider msg check <address>\n");
        return 1;
    }
    return cmdMsgCheck(argv[3]);
}

static int handleMsgExport(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: cider msg export <chat> [-o path]\n");
        return 1;
    }
    NSString *output = argValue(argc, argv, 4, "-o", "--output");
    return cmdMsgExport(argv[3], output, nil);
}

// ─────────────────────────────────────────────────────────────────────────────
// Command table
// ─────────────────────────────────────────────────────────────────────────────

static const CiderCommand g_commands[] = {
    // ── notes ────────────────────────────────────────────────────────────────
    {"notes", "list",        NULL,       "List notes",
     "--folder -f --json --after --before --sort --pinned --tag", handleNotesList},
    {"notes", "show",        NULL,       "View note content",
     "--json", handleNotesShow},
    {"notes", "inspect",     NULL,       "Full note details",
     "--folder -f --json", handleNotesInspect},
    {"notes", "folders",     NULL,       "List all folders",
     "--json", handleNotesFolders},
    {"notes", "add",         NULL,       "Add a new note",
     "--folder -f --template", handleNotesAdd},
    {"notes", "edit",        NULL,       "Edit note via CRDT",
     NULL, handleNotesEdit},
    {"notes", "delete",      NULL,       "Delete a note",
     NULL, handleNotesDelete},
    {"notes", "move",        NULL,       "Move note to a folder",
     "--folder -f", handleNotesMove},
    {"notes", "append",      NULL,       "Append text to note",
     "--folder -f --no-newline", handleNotesAppend},
    {"notes", "prepend",     NULL,       "Insert text after title",
     "--folder -f --no-newline", handleNotesPrepend},
    {"notes", "debug",       NULL,       "Dump CRDT attributes",
     "--folder -f", handleNotesDebug},
    {"notes", "history",     NULL,       "Edit timeline & blame",
     "--folder -f --json --raw --blame", handleNotesHistory},
    {"notes", "getdate",     NULL,       "Show dates",
     "--folder -f --json", handleNotesGetdate},
    {"notes", "setdate",     NULL,       "Set modification date",
     "--folder -f --dry-run", handleNotesSetdate},
    {"notes", "pin",         NULL,       "Pin a note",
     "--folder -f", handleNotesPin},
    {"notes", "unpin",       NULL,       "Unpin a note",
     "--folder -f", handleNotesUnpin},
    {"notes", "watch",       NULL,       "Stream change events",
     "--folder -f --json --interval", handleNotesWatch},
    {"notes", "links",       NULL,       "Show outgoing links",
     "--folder -f --json", handleNotesLinks},
    {"notes", "backlinks",   NULL,       "Show incoming links",
     "--folder -f --json --all", handleNotesBacklinks},
    {"notes", "link",        NULL,       "Create a link to another note",
     "--folder -f", handleNotesLink},
    {"notes", "share",       NULL,       "Show sharing status",
     "--folder -f --json", handleNotesShare},
    {"notes", "shared",      NULL,       "List shared notes",
     "--json", handleNotesShared},
    {"notes", "table",       NULL,       "Show/add table data",
     "--folder -f --json --csv --list --index --row --headers --add-row", handleNotesTable},
    {"notes", "checklist",   NULL,       "Show checklist items",
     "--folder -f --json --summary --add", handleNotesChecklist},
    {"notes", "check",       NULL,       "Check off a checklist item",
     "--folder -f", handleNotesCheck},
    {"notes", "uncheck",     NULL,       "Uncheck a checklist item",
     "--folder -f", handleNotesUncheck},
    {"notes", "folder",      NULL,       "Create, delete, rename folders",
     NULL, handleNotesFolder},
    {"notes", "tag",         NULL,       "Add a #tag",
     "--folder -f", handleNotesTag},
    {"notes", "untag",       NULL,       "Remove a #tag",
     "--folder -f", handleNotesUntag},
    {"notes", "tags",        NULL,       "List all unique tags",
     "--count --json --clean", handleNotesTags},
    {"notes", "replace",     NULL,       "Find & replace",
     "--find --replace --regex -i --all --folder -f --dry-run", handleNotesReplace},
    {"notes", "search",      NULL,       "Search notes",
     "--regex --title --body --folder -f --after --before --tag --json", handleNotesSearch},
    {"notes", "export",      NULL,       "Export all notes to HTML",
     NULL, handleNotesExport},
    {"notes", "attachments", NULL,       "List attachments",
     "--json", handleNotesAttachments},
    {"notes", "detach",      NULL,       "Remove an attachment",
     NULL, handleNotesDetach},
    {"notes", "attach",      NULL,       "Add file attachment",
     "--at", handleNotesAttach},

    // ── Legacy notes aliases (hidden from help/completions) ──────────────────
    {"notes", "-fl",         NULL,       NULL, NULL, handleNotesLegacyFl},
    {"notes", "-f",          NULL,       NULL, NULL, handleNotesLegacyF},
    {"notes", "-v",          NULL,       NULL, NULL, handleNotesLegacyV},
    {"notes", "-a",          NULL,       NULL, NULL, handleNotesLegacyA},
    {"notes", "-e",          NULL,       NULL, NULL, handleNotesLegacyE},
    {"notes", "-d",          NULL,       NULL, NULL, handleNotesLegacyD},
    {"notes", "-m",          NULL,       NULL, NULL, handleNotesLegacyM},
    {"notes", "-s",          NULL,       NULL, NULL, handleNotesLegacyS},
    {"notes", "--export",    NULL,       NULL, NULL, handleNotesExport},
    {"notes", "--attach",    NULL,       NULL, NULL, handleNotesAttach},

    // ── templates ────────────────────────────────────────────────────────────
    {"templates", "list",    NULL,       "List templates",
     NULL, handleTemplatesList},
    {"templates", "show",    NULL,       "Show template content",
     NULL, handleTemplatesShow},
    {"templates", "add",     NULL,       "Add a new template",
     NULL, handleTemplatesAdd},
    {"templates", "delete",  NULL,       "Delete a template",
     NULL, handleTemplatesDelete},

    // ── settings ─────────────────────────────────────────────────────────────
    {"settings", "get",      NULL,       "Get a setting value",
     NULL, handleSettingsGet},
    {"settings", "set",      NULL,       "Set a setting",
     NULL, handleSettingsSet},
    {"settings", "reset",    NULL,       "Reset all settings",
     NULL, handleSettingsReset},

    // ── sync ─────────────────────────────────────────────────────────────────
    {"sync", "backup",       NULL,       "Backup Notes.sqlite",
     "--dir -d", handleSyncBackup},
    {"sync", "run",          NULL,       "One-time sync cycle",
     "--dir -d", handleSyncRun},
    {"sync", "watch",        NULL,       "Continuous sync",
     "--dir -d --interval -i", handleSyncWatch},

    // ── rem ──────────────────────────────────────────────────────────────────
    {"rem", "list",          NULL,       "List reminders",
     NULL, handleRemList},
    {"rem", "add",           NULL,       "Add reminder",
     NULL, handleRemAdd},
    {"rem", "edit",          NULL,       "Edit reminder",
     NULL, handleRemEdit},
    {"rem", "delete",        NULL,       "Delete reminder",
     NULL, handleRemDelete},
    {"rem", "complete",      NULL,       "Complete reminder",
     NULL, handleRemComplete},

    // ── Legacy rem aliases (hidden) ──────────────────────────────────────────
    {"rem", "-a",            NULL,       NULL, NULL, handleRemAdd},
    {"rem", "-e",            NULL,       NULL, NULL, handleRemEdit},
    {"rem", "-d",            NULL,       NULL, NULL, handleRemDelete},
    {"rem", "-c",            NULL,       NULL, NULL, handleRemComplete},

    // ── msg (iMessage) ───────────────────────────────────────────────────────
    {"msg", "list",          NULL,       "List conversations",
     "--limit -n --service --json", handleMsgList},
    {"msg", "show",          NULL,       "View messages in a chat",
     "--limit -n --after --before --sort --json", handleMsgShow},
    {"msg", "context",       NULL,       "Show messages around a specific message",
     "--context -c --before --after --json", handleMsgContext},
    {"msg", "search",        NULL,       "Search all messages",
     "--limit -n --sort --fzf --json", handleMsgSearch},
    {"msg", "send",          NULL,       "Send a text message",
     "--service", handleMsgSend},
    {"msg", "attach",        NULL,       "Send a file attachment",
     "--service", handleMsgAttachFile},
    {"msg", "info",          NULL,       "Chat details & participants",
     "--json", handleMsgInfo},
    {"msg", "count",         NULL,       "Message statistics",
     "--json", handleMsgCount},
    {"msg", "contacts",      NULL,       "List contacts/handles",
     "--limit -n --service --json", handleMsgContacts},
    {"msg", "attachments",   NULL,       "List attachments in a chat",
     "--limit -n --json", handleMsgAttachments},
    {"msg", "export",        NULL,       "Export conversation to file",
     "-o --output", handleMsgExport},
    {"msg", "schedule",      NULL,       "List scheduled messages",
     "--json", handleMsgSchedule},
    {"msg", "check",         NULL,       "Check address in history",
     NULL, handleMsgCheck},
    {"msg", "react",         NULL,       "Send tapback (Private API)",
     NULL, handleMsgReact},
    {"msg", "read",          NULL,       "Mark chat as read (Private API)",
     NULL, handleMsgRead},
    {"msg", "unread",        NULL,       "Mark chat unread (Private API)",
     NULL, handleMsgUnread},
    {"msg", "delete",        NULL,       "Delete a chat (Private API)",
     NULL, handleMsgDelete},
    {"msg", "typing",        NULL,       "Typing indicator (Private API)",
     NULL, handleMsgTyping},
    {"msg", "edit",          NULL,       "Edit a message (Private API)",
     NULL, handleMsgEdit},
    {"msg", "unsend",        NULL,       "Unsend a message (Private API)",
     NULL, handleMsgUnsend},
    {"msg", "group",         NULL,       "Group chat operations",
     NULL, handleMsgGroup},
};

static const size_t g_numCommands = sizeof(g_commands) / sizeof(g_commands[0]);

// ─────────────────────────────────────────────────────────────────────────────
// Registry lookup
// ─────────────────────────────────────────────────────────────────────────────

static const CiderCommand *findCommand(const char *parent, const char *sub) {
    for (size_t i = 0; i < g_numCommands; i++) {
        if (strcmp(g_commands[i].parent, parent) != 0) continue;
        if (strcmp(g_commands[i].name, sub) == 0) return &g_commands[i];
        if (g_commands[i].alias && strcmp(g_commands[i].alias, sub) == 0)
            return &g_commands[i];
    }
    return NULL;
}

// ─────────────────────────────────────────────────────────────────────────────
// Shell completions
// ─────────────────────────────────────────────────────────────────────────────

static void printCompletionsZsh(void) {
    printf("#compdef cider\n\n");
    printf("_cider() {\n");
    printf("  local -a top_commands\n");
    printf("  top_commands=(\n");
    printf("    'notes:Apple Notes operations'\n");
    printf("    'templates:Template management'\n");
    printf("    'settings:Cider configuration'\n");
    printf("    'rem:Reminders operations'\n");
    printf("    'sync:Notes <-> Markdown sync'\n");
    printf("    'msg:iMessage operations'\n");
    printf("  )\n\n");
    printf("  if (( CURRENT == 2 )); then\n");
    printf("    _describe 'command' top_commands\n");
    printf("    return\n");
    printf("  fi\n\n");

    // Generate per-parent subcommand completions
    const char *parents[] = {"notes", "templates", "settings", "sync", "rem", "msg"};
    for (int p = 0; p < 6; p++) {
        printf("  if [[ $words[2] == '%s' ]]; then\n", parents[p]);
        printf("    if (( CURRENT == 3 )); then\n");
        printf("      local -a subcmds\n");
        printf("      subcmds=(\n");
        for (size_t i = 0; i < g_numCommands; i++) {
            if (strcmp(g_commands[i].parent, parents[p]) != 0) continue;
            if (!g_commands[i].brief) continue; // skip hidden
            printf("        '%s:%s'\n", g_commands[i].name, g_commands[i].brief);
        }
        printf("      )\n");
        printf("      _describe 'subcommand' subcmds\n");
        printf("      return\n");
        printf("    fi\n");

        // Per-subcommand flag completions
        printf("    case $words[3] in\n");
        for (size_t i = 0; i < g_numCommands; i++) {
            if (strcmp(g_commands[i].parent, parents[p]) != 0) continue;
            if (!g_commands[i].brief || !g_commands[i].flags) continue;
            printf("      %s)\n", g_commands[i].name);
            printf("        _arguments");
            // Parse space-separated flags
            char flagsBuf[512];
            strncpy(flagsBuf, g_commands[i].flags, sizeof(flagsBuf) - 1);
            flagsBuf[sizeof(flagsBuf) - 1] = '\0';
            char *tok = strtok(flagsBuf, " ");
            while (tok) {
                printf(" '%s'", tok);
                tok = strtok(NULL, " ");
            }
            printf("\n");
            printf("        ;;\n");
        }
        printf("    esac\n");
        printf("  fi\n\n");
    }

    printf("}\n\n");
    printf("_cider\n");
}

static void printCompletionsBash(void) {
    printf("_cider() {\n");
    printf("  local cur prev words cword\n");
    printf("  _init_completion || return\n\n");
    printf("  if [[ $cword -eq 1 ]]; then\n");
    printf("    COMPREPLY=($(compgen -W 'notes templates settings rem sync msg --version --help' -- \"$cur\"))\n");
    printf("    return\n");
    printf("  fi\n\n");

    const char *parents[] = {"notes", "templates", "settings", "sync", "rem", "msg"};
    for (int p = 0; p < 6; p++) {
        printf("  if [[ ${words[1]} == '%s' ]]; then\n", parents[p]);
        printf("    if [[ $cword -eq 2 ]]; then\n");
        printf("      local subcmds='");
        int first = 1;
        for (size_t i = 0; i < g_numCommands; i++) {
            if (strcmp(g_commands[i].parent, parents[p]) != 0) continue;
            if (!g_commands[i].brief) continue;
            if (!first) printf(" ");
            printf("%s", g_commands[i].name);
            first = 0;
        }
        printf("'\n");
        printf("      COMPREPLY=($(compgen -W \"$subcmds\" -- \"$cur\"))\n");
        printf("      return\n");
        printf("    fi\n");

        printf("    case ${words[2]} in\n");
        for (size_t i = 0; i < g_numCommands; i++) {
            if (strcmp(g_commands[i].parent, parents[p]) != 0) continue;
            if (!g_commands[i].brief || !g_commands[i].flags) continue;
            printf("      %s) COMPREPLY=($(compgen -W '%s' -- \"$cur\")) ;;\n",
                   g_commands[i].name, g_commands[i].flags);
        }
        printf("    esac\n");
        printf("  fi\n\n");
    }

    printf("}\n\ncomplete -F _cider cider\n");
}

static void printCompletionsList(void) {
    const char *lastParent = "";
    for (size_t i = 0; i < g_numCommands; i++) {
        if (!g_commands[i].brief) continue;
        if (strcmp(g_commands[i].parent, lastParent) != 0) {
            printf("\n%s:\n", g_commands[i].parent);
            lastParent = g_commands[i].parent;
        }
        printf("  %-14s %s", g_commands[i].name, g_commands[i].brief);
        if (g_commands[i].flags) {
            printf("  [%s]", g_commands[i].flags);
        }
        printf("\n");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// main
// ─────────────────────────────────────────────────────────────────────────────

int main(int argc, char *argv[]) {
    @autoreleasepool {

        if (argc < 2) {
            printHelp();
            return 0;
        }

        NSString *cmd = [NSString stringWithUTF8String:argv[1]];

        // ── top-level flags ──────────────────────────────────────────────────
        if ([cmd isEqualToString:@"--version"] ||
            [cmd isEqualToString:@"-V"]) {
            printf("cider v" VERSION "\n");
            return 0;
        }
        if ([cmd isEqualToString:@"--help"] ||
            [cmd isEqualToString:@"-h"]) {
            printHelp();
            return 0;
        }
        if ([cmd isEqualToString:@"--completions"]) {
            if (argc < 3) {
                fprintf(stderr, "Usage: cider --completions zsh|bash|list\n");
                return 1;
            }
            if (strcmp(argv[2], "zsh") == 0)       printCompletionsZsh();
            else if (strcmp(argv[2], "bash") == 0)  printCompletionsBash();
            else if (strcmp(argv[2], "list") == 0)  printCompletionsList();
            else {
                fprintf(stderr, "Unknown format: %s (use zsh, bash, or list)\n", argv[2]);
                return 1;
            }
            return 0;
        }

        // ── notes ────────────────────────────────────────────────────────────
        if ([cmd isEqualToString:@"notes"]) {
            if (argc >= 3 && (strcmp(argv[2], "--help") == 0 ||
                               strcmp(argv[2], "-h") == 0)) {
                printNotesHelp();
                return 0;
            }

            if (!initNotesContext()) return 1;

            if (argc == 2) {
                cmdNotesList(nil, NO, nil, nil, nil, NO, nil);
                return 0;
            }

            NSString *sub = [NSString stringWithUTF8String:argv[2]];

            // Per-subcommand help
            if (argc >= 4 && (strcmp(argv[3], "--help") == 0 ||
                               strcmp(argv[3], "-h") == 0)) {
                printNotesSubcommandHelp([sub UTF8String]);
                return 0;
            }

            // Bare number → show
            if ([sub intValue] > 0 && [sub isEqualToString:
                [NSString stringWithFormat:@"%d", [sub intValue]]]) {
                NSUInteger idx = (NSUInteger)[sub intValue];
                BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
                return cmdNotesView(idx, nil, jsonOut);
            }

            const CiderCommand *entry = findCommand("notes", [sub UTF8String]);
            if (!entry) {
                fprintf(stderr, "Unknown notes subcommand: %s\n", argv[2]);
                printNotesHelp();
                return 1;
            }
            return entry->handler(argc, argv);
        }

        // ── templates ────────────────────────────────────────────────────────
        if ([cmd isEqualToString:@"templates"]) {
            if (!initNotesContext()) return 1;

            if (argc == 2) {
                cmdTemplatesList();
                return 0;
            }

            const CiderCommand *entry = findCommand("templates", argv[2]);
            if (!entry) {
                fprintf(stderr, "Unknown templates subcommand: %s\n", argv[2]);
                return 1;
            }
            return entry->handler(argc, argv);
        }

        // ── settings ─────────────────────────────────────────────────────────
        if ([cmd isEqualToString:@"settings"]) {
            if (!initNotesContext()) return 1;

            if (argc == 2) {
                cmdSettings(NO);
                return 0;
            }

            // Handle bare "cider settings --json"
            if (strcmp(argv[2], "--json") == 0) {
                cmdSettings(YES);
                return 0;
            }

            const CiderCommand *entry = findCommand("settings", argv[2]);
            if (!entry) {
                fprintf(stderr, "Unknown settings subcommand: %s\n", argv[2]);
                return 1;
            }
            return entry->handler(argc, argv);
        }

        // ── sync ─────────────────────────────────────────────────────────────
        if ([cmd isEqualToString:@"sync"]) {
            if (argc >= 3 && (strcmp(argv[2], "--help") == 0 ||
                               strcmp(argv[2], "-h") == 0)) {
                printSyncHelp();
                return 0;
            }

            if (argc == 2) {
                printSyncHelp();
                return 0;
            }

            const CiderCommand *entry = findCommand("sync", argv[2]);
            if (!entry) {
                fprintf(stderr, "Unknown sync subcommand: %s\n", argv[2]);
                printSyncHelp();
                return 1;
            }
            return entry->handler(argc, argv);
        }

        // ── msg (iMessage) ───────────────────────────────────────────────────
        if ([cmd isEqualToString:@"msg"]) {
            if (argc >= 3 && (strcmp(argv[2], "--help") == 0 ||
                               strcmp(argv[2], "-h") == 0)) {
                printMsgHelp();
                return 0;
            }

            if (argc == 2) {
                cmdMsgList(0, NO, nil);
                return 0;
            }

            NSString *sub = [NSString stringWithUTF8String:argv[2]];

            // Per-subcommand help
            if (argc >= 4 && (strcmp(argv[3], "--help") == 0 ||
                               strcmp(argv[3], "-h") == 0)) {
                printMsgSubcommandHelp([sub UTF8String]);
                return 0;
            }

            // Bare number → show chat
            if ([sub intValue] > 0 && [sub isEqualToString:
                [NSString stringWithFormat:@"%d", [sub intValue]]]) {
                cmdMsgShow([sub UTF8String], 0, NO, nil, nil, NO);
                return 0;
            }

            const CiderCommand *entry = findCommand("msg", [sub UTF8String]);
            if (!entry) {
                fprintf(stderr, "Unknown msg subcommand: %s\n", argv[2]);
                printMsgHelp();
                return 1;
            }
            return entry->handler(argc, argv);
        }

        // ── rem ──────────────────────────────────────────────────────────────
        if ([cmd isEqualToString:@"rem"]) {
            if (argc >= 3 && (strcmp(argv[2], "--help") == 0 ||
                               strcmp(argv[2], "-h") == 0)) {
                printRemHelp();
                return 0;
            }

            if (argc == 2) {
                cmdRemList();
                return 0;
            }

            const CiderCommand *entry = findCommand("rem", argv[2]);
            if (!entry) {
                fprintf(stderr, "Unknown rem subcommand: %s\n", argv[2]);
                printRemHelp();
                return 1;
            }
            return entry->handler(argc, argv);
        }

        if ([cmd isEqualToString:@"passwords"] || [cmd isEqualToString:@"pw"]) {
            if (argc >= 3 && (strcmp(argv[2], "--help") == 0 ||
                               strcmp(argv[2], "-h") == 0)) {
                printPasswordsHelp();
                return 0;
            }

            BOOL jsonOut = argHasFlag(argc, argv, 2, "--json", NULL);

            if (argc == 2 || strcmp(argv[2], "list") == 0) {
                // optional: cider passwords list [file.csv]
                NSString *csvArg = nil;
                int startIdx = strcmp(argv[2], "list") == 0 ? 3 : 2;
                for (int i = startIdx; i < argc; i++) {
                    if (argv[i][0] != '-') { csvArg = @(argv[i]); break; }
                }
                cmdPasswordsList(csvArg, jsonOut);
                return 0;
            }

            if (strcmp(argv[2], "show") == 0) {
                if (argc < 4) { fprintf(stderr, "Usage: cider passwords show <N> [file.csv]\n"); return 1; }
                NSUInteger idx = (NSUInteger)atol(argv[3]);
                NSString *csvArg = nil;
                for (int i = 4; i < argc; i++) {
                    if (argv[i][0] != '-') { csvArg = @(argv[i]); break; }
                }
                cmdPasswordsShow(idx, csvArg, jsonOut);
                return 0;
            }

            if (strcmp(argv[2], "search") == 0) {
                if (argc < 4) { fprintf(stderr, "Usage: cider passwords search <query> [file.csv]\n"); return 1; }
                NSString *csvArg = nil;
                for (int i = 4; i < argc; i++) {
                    if (argv[i][0] != '-') { csvArg = @(argv[i]); break; }
                }
                cmdPasswordsSearch(@(argv[3]), csvArg, jsonOut);
                return 0;
            }

            if (strcmp(argv[2], "sync") == 0) {
                NSString *csvArg = nil;
                for (int i = 3; i < argc; i++) {
                    if (argv[i][0] != '-') { csvArg = @(argv[i]); break; }
                }
                cmdPasswordsSync(csvArg);
                return 0;
            }

            fprintf(stderr, "Unknown passwords subcommand: %s\n", argv[2]);
            printPasswordsHelp();
            return 1;
        }

        fprintf(stderr, "Unknown command: %s\n"
                "Run 'cider --help' for usage.\n", [cmd UTF8String]);
        return 1;
    }
}

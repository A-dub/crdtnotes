/**
 * passwords.m — Passwords commands (CSV import + Vaultwarden sync)
 *
 * iCloud Keychain requires a signed binary with keychain-access-groups entitlements —
 * unsigned CLIs get errSecItemNotFound. Instead, this module works with the CSV export
 * from Passwords.app (File → Export Passwords…).
 *
 * Commands:
 *   cider passwords list [file.csv]       List all entries
 *   cider passwords show <N> [file.csv]   Show entry #N including password
 *   cider passwords search <q> [file.csv] Search by title/username/URL
 *   cider passwords sync [file.csv]       Push entries to Vaultwarden (adds new only)
 *
 * Config (via cider settings):
 *   passwords.vaultwarden_url    e.g. https://vw.6047.in
 *   passwords.vaultwarden_token  Vaultwarden personal API key
 *   passwords.default_csv        Default CSV path (optional, avoids repeating path)
 *
 * Export from Passwords.app:
 *   Passwords.app → File → Export Passwords… → save as ~/passwords.csv
 *   (or any path — pass it as the last argument, or set passwords.default_csv)
 */

#import "cider.h"

// ─────────────────────────────────────────────────────────────────────────────
// CSV parser (handles quoted fields and embedded commas/newlines)
// ─────────────────────────────────────────────────────────────────────────────

static NSArray *parseCSVLine(NSString *line) {
    NSMutableArray *fields = [NSMutableArray array];
    NSUInteger i = 0, len = line.length;
    while (i <= len) {
        NSMutableString *field = [NSMutableString string];
        if (i < len && [line characterAtIndex:i] == '"') {
            i++;
            while (i < len) {
                unichar c = [line characterAtIndex:i];
                if (c == '"') {
                    i++;
                    if (i < len && [line characterAtIndex:i] == '"') {
                        [field appendString:@"\""];
                        i++;
                    } else break;
                } else {
                    [field appendFormat:@"%C", c];
                    i++;
                }
            }
        } else {
            while (i < len && [line characterAtIndex:i] != ',') {
                [field appendFormat:@"%C", [line characterAtIndex:i]];
                i++;
            }
        }
        [fields addObject:field];
        if (i < len && [line characterAtIndex:i] == ',') i++;
        else break;
    }
    return fields;
}

// ─────────────────────────────────────────────────────────────────────────────
// Core: load CSV into array of dicts
// Passwords.app CSV format: Title,URL,Username,Password,Notes,OTPAuth
// ─────────────────────────────────────────────────────────────────────────────

static NSString *defaultCSVPath(void) {
    NSString *setting = getCiderSetting(@"passwords.default_csv");
    if (setting && setting.length > 0) return [setting stringByExpandingTildeInPath];
    return nil;
}

static NSArray *loadCSV(NSString *path) {
    NSError *err = nil;
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err];
    if (err) {
        fprintf(stderr, "Error reading %s: %s\n", [path UTF8String], [[err localizedDescription] UTF8String]);
        return nil;
    }

    NSArray *lines = [content componentsSeparatedByCharactersInSet:
                      [NSCharacterSet characterSetWithCharactersInString:@"\n\r"]];

    NSMutableArray *result = [NSMutableArray array];
    NSArray *headers = nil;

    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) continue;

        NSArray *fields = parseCSVLine(trimmed);

        if (!headers) {
            // Normalize header names: lowercase
            headers = [fields valueForKey:@"lowercaseString"];
            continue;
        }

        NSMutableDictionary *row = [NSMutableDictionary dictionary];
        for (NSUInteger i = 0; i < headers.count && i < fields.count; i++) {
            row[headers[i]] = fields[i];
        }

        // Normalize common column name variations
        NSString *title    = row[@"title"] ?: row[@"name"] ?: @"";
        NSString *url      = row[@"url"] ?: row[@"website"] ?: @"";
        NSString *username = row[@"username"] ?: row[@"account"] ?: row[@"email"] ?: @"";
        NSString *password = row[@"password"] ?: @"";
        NSString *notes    = row[@"notes"] ?: row[@"note"] ?: @"";
        NSString *otp      = row[@"otpauth"] ?: row[@"totp"] ?: @"";

        [result addObject:@{
            @"title":    title,
            @"url":      url,
            @"username": username,
            @"password": password,
            @"notes":    notes,
            @"otp":      otp,
        }];
    }
    return result;
}

static NSString *resolveCSVPath(NSString *argPath) {
    if (argPath && argPath.length > 0) return [argPath stringByExpandingTildeInPath];
    NSString *def = defaultCSVPath();
    if (def) return def;
    fprintf(stderr,
        "Error: No CSV file specified.\n"
        "\n"
        "Export from Passwords.app:\n"
        "  Passwords.app → File → Export Passwords… → save as ~/passwords.csv\n"
        "\n"
        "Then run: cider passwords list ~/passwords.csv\n"
        "Or set a default: cider settings set passwords.default_csv ~/passwords.csv\n");
    return nil;
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMAND: passwords list [file.csv]
// ─────────────────────────────────────────────────────────────────────────────

void cmdPasswordsList(NSString *csvPath, BOOL jsonOutput) {
    NSString *path = resolveCSVPath(csvPath);
    if (!path) return;

    NSArray *items = loadCSV(path);
    if (!items) return;
    if (items.count == 0) { printf("(no entries in CSV)\n"); return; }

    if (jsonOutput) {
        printf("[\n");
        for (NSUInteger i = 0; i < items.count; i++) {
            NSDictionary *it = items[i];
            printf("  {\"index\":%lu,\"title\":\"%s\",\"username\":\"%s\",\"url\":\"%s\"}%s\n",
                (unsigned long)(i + 1),
                [jsonEscapeString(it[@"title"]) UTF8String],
                [jsonEscapeString(it[@"username"]) UTF8String],
                [jsonEscapeString(it[@"url"]) UTF8String],
                i < items.count - 1 ? "," : "");
        }
        printf("]\n");
        return;
    }

    printf("%-4s  %-30s  %-25s  %s\n", "#", "Title", "Username", "URL");
    printf("%-4s  %-30s  %-25s  %s\n", "─", "──────────────────────────────", "─────────────────────────", "───────────────────────────────");
    for (NSUInteger i = 0; i < items.count; i++) {
        NSDictionary *it = items[i];
        printf("%-4lu  %-30s  %-25s  %s\n",
            (unsigned long)(i + 1),
            [truncStr(it[@"title"],    30) UTF8String],
            [truncStr(it[@"username"], 25) UTF8String],
            [truncStr(it[@"url"],      40) UTF8String]);
    }
    printf("\n%lu entries. Use 'cider passwords show <N>' to reveal password.\n",
           (unsigned long)items.count);
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMAND: passwords show <N> [file.csv]
// ─────────────────────────────────────────────────────────────────────────────

void cmdPasswordsShow(NSUInteger idx, NSString *csvPath, BOOL jsonOutput) {
    NSString *path = resolveCSVPath(csvPath);
    if (!path) return;

    NSArray *items = loadCSV(path);
    if (!items) return;

    if (idx < 1 || idx > items.count) {
        fprintf(stderr, "Entry %lu not found (have %lu)\n",
                (unsigned long)idx, (unsigned long)items.count);
        return;
    }

    NSDictionary *it = items[idx - 1];

    if (jsonOutput) {
        printf("{\"index\":%lu,\"title\":\"%s\",\"username\":\"%s\",\"url\":\"%s\","
               "\"password\":\"%s\",\"notes\":\"%s\"}\n",
            (unsigned long)idx,
            [jsonEscapeString(it[@"title"]) UTF8String],
            [jsonEscapeString(it[@"username"]) UTF8String],
            [jsonEscapeString(it[@"url"]) UTF8String],
            [jsonEscapeString(it[@"password"]) UTF8String],
            [jsonEscapeString(it[@"notes"]) UTF8String]);
        return;
    }

    printf("Title:    %s\n", [it[@"title"] UTF8String]);
    printf("Username: %s\n", [it[@"username"] UTF8String]);
    printf("URL:      %s\n", [it[@"url"] UTF8String]);
    printf("Password: %s\n", [it[@"password"] UTF8String]);
    if ([it[@"notes"] length] > 0) printf("Notes:    %s\n", [it[@"notes"] UTF8String]);
    if ([it[@"otp"] length] > 0)   printf("OTP:      %s\n", [it[@"otp"] UTF8String]);
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMAND: passwords search <query> [file.csv]
// ─────────────────────────────────────────────────────────────────────────────

void cmdPasswordsSearch(NSString *query, NSString *csvPath, BOOL jsonOutput) {
    NSString *path = resolveCSVPath(csvPath);
    if (!path) return;

    NSArray *items = loadCSV(path);
    if (!items) return;

    NSString *lq = [query lowercaseString];
    NSMutableArray *matches = [NSMutableArray array];
    for (NSUInteger i = 0; i < items.count; i++) {
        NSDictionary *it = items[i];
        BOOL hit = [[it[@"title"] lowercaseString] containsString:lq]
                || [[it[@"username"] lowercaseString] containsString:lq]
                || [[it[@"url"] lowercaseString] containsString:lq]
                || [[it[@"notes"] lowercaseString] containsString:lq];
        if (hit) {
            NSMutableDictionary *m = [it mutableCopy];
            m[@"_idx"] = @(i + 1);
            [matches addObject:m];
        }
    }

    if (matches.count == 0) { printf("(no matches for \"%s\")\n", [query UTF8String]); return; }

    if (jsonOutput) {
        printf("[\n");
        for (NSUInteger i = 0; i < matches.count; i++) {
            NSDictionary *it = matches[i];
            printf("  {\"index\":%lu,\"title\":\"%s\",\"username\":\"%s\",\"url\":\"%s\"}%s\n",
                (unsigned long)[it[@"_idx"] unsignedIntegerValue],
                [jsonEscapeString(it[@"title"]) UTF8String],
                [jsonEscapeString(it[@"username"]) UTF8String],
                [jsonEscapeString(it[@"url"]) UTF8String],
                i < matches.count - 1 ? "," : "");
        }
        printf("]\n");
        return;
    }

    for (NSDictionary *it in matches) {
        printf("%lu. %s  (%s)\n",
            (unsigned long)[it[@"_idx"] unsignedIntegerValue],
            [it[@"title"] UTF8String],
            [it[@"username"] UTF8String]);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vaultwarden HTTP helper
// ─────────────────────────────────────────────────────────────────────────────

static NSString *vaultwardenRequest(NSString *urlStr, NSString *method,
                                     NSDictionary *body, NSString *token,
                                     int *outStatus) {
    NSURL *url = [NSURL URLWithString:urlStr];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = method;
    [req setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    if (body) {
        NSError *err = nil;
        req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:&err];
        if (err) { fprintf(stderr, "JSON error: %s\n", [[err localizedDescription] UTF8String]); return nil; }
    }

    __block NSString *responseStr = nil;
    __block int statusCode = 0;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *taskErr) {
            if (taskErr) { fprintf(stderr, "Network error: %s\n", [[taskErr localizedDescription] UTF8String]); }
            else {
                statusCode = (int)[(NSHTTPURLResponse *)resp statusCode];
                if (data) responseStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            }
            dispatch_semaphore_signal(sem);
        }];
    [task resume];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

    if (outStatus) *outStatus = statusCode;
    return responseStr;
}

static NSSet *fetchExistingVaultwardenTitles(NSString *baseURL, NSString *token) {
    int status = 0;
    NSString *resp = vaultwardenRequest([baseURL stringByAppendingString:@"/api/ciphers"],
                                         @"GET", nil, token, &status);
    if (status != 200 || !resp) return [NSSet set];

    NSData *d = [resp dataUsingEncoding:NSUTF8StringEncoding];
    id json = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    NSArray *ciphers = [json isKindOfClass:[NSDictionary class]] ? json[@"data"] : json;
    if (![ciphers isKindOfClass:[NSArray class]]) return [NSSet set];

    NSMutableSet *titles = [NSMutableSet set];
    for (NSDictionary *c in ciphers) {
        NSString *name = c[@"name"] ?: @"";
        if (name.length > 0) [titles addObject:name];
        NSArray *uris = c[@"login"][@"uris"];
        for (NSDictionary *u in uris) {
            NSString *uri = u[@"uri"] ?: @"";
            if (uri.length > 0) [titles addObject:uri];
        }
    }
    return titles;
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMAND: passwords sync [file.csv]
// ─────────────────────────────────────────────────────────────────────────────

void cmdPasswordsSync(NSString *csvPath) {
    NSString *baseURL = getCiderSetting(@"passwords.vaultwarden_url");
    NSString *token   = getCiderSetting(@"passwords.vaultwarden_token");

    if (!baseURL || baseURL.length == 0) {
        fprintf(stderr,
            "Error: Vaultwarden URL not set.\n"
            "Run: cider settings set passwords.vaultwarden_url https://vw.6047.in\n");
        return;
    }
    if (!token || token.length == 0) {
        fprintf(stderr,
            "Error: Vaultwarden token not set.\n"
            "Run: cider settings set passwords.vaultwarden_token <your-api-key>\n"
            "Find it: Vaultwarden web UI → Account Settings → API Key\n");
        return;
    }
    if ([baseURL hasSuffix:@"/"]) baseURL = [baseURL substringToIndex:baseURL.length - 1];

    NSString *path = resolveCSVPath(csvPath);
    if (!path) return;

    printf("Loading passwords from %s...\n", [path UTF8String]);
    NSArray *items = loadCSV(path);
    if (!items) return;
    printf("Found %lu entries in CSV.\n", (unsigned long)items.count);

    printf("Fetching existing entries from Vaultwarden...\n");
    NSSet *existing = fetchExistingVaultwardenTitles(baseURL, token);
    printf("Vaultwarden has %lu existing entries.\n", (unsigned long)existing.count);

    NSString *ciphersURL = [baseURL stringByAppendingString:@"/api/ciphers"];
    NSUInteger added = 0, skipped = 0, failed = 0;

    for (NSDictionary *it in items) {
        NSString *title    = it[@"title"] ?: @"";
        NSString *url      = it[@"url"] ?: @"";
        NSString *username = it[@"username"] ?: @"";
        NSString *password = it[@"password"] ?: @"";
        NSString *notes    = it[@"notes"] ?: @"";

        // Skip if title or URL already in Vaultwarden
        if ([existing containsObject:title] || (url.length > 0 && [existing containsObject:url])) {
            skipped++;
            continue;
        }

        NSMutableArray *uris = [NSMutableArray array];
        if (url.length > 0) [uris addObject:@{@"match": [NSNull null], @"uri": url}];

        NSDictionary *cipher = @{
            @"type":  @1,
            @"name":  title.length > 0 ? title : (url.length > 0 ? url : @"(untitled)"),
            @"notes": notes,
            @"login": @{
                @"username": username,
                @"password": password,
                @"uris":     uris,
            },
        };

        int status = 0;
        NSString *resp = vaultwardenRequest(ciphersURL, @"POST", cipher, token, &status);
        if (status == 200 || status == 201) {
            printf("  + %s (%s)\n", [title UTF8String], [username UTF8String]);
            added++;
        } else {
            fprintf(stderr, "  ! Failed %s: HTTP %d %s\n",
                    [title UTF8String], status, [resp UTF8String]);
            failed++;
        }
    }

    printf("\nSync complete: %lu added, %lu skipped (already exist), %lu failed.\n",
           (unsigned long)added, (unsigned long)skipped, (unsigned long)failed);
}

// ─────────────────────────────────────────────────────────────────────────────
// Help
// ─────────────────────────────────────────────────────────────────────────────

void printPasswordsHelp(void) {
    printf(
"cider passwords — Apple Passwords export → Vaultwarden sync\n"
"\n"
"SUBCOMMANDS:\n"
"  list [file.csv]              List all entries\n"
"  show <N> [file.csv]          Show entry #N including password\n"
"  search <query> [file.csv]    Search by title, username, or URL\n"
"  sync [file.csv]              Push entries to Vaultwarden (adds new, skips existing)\n"
"\n"
"OPTIONS:\n"
"  --json    JSON output (list, show, search)\n"
"\n"
"EXPORT FROM PASSWORDS.APP:\n"
"  Passwords.app → File → Export Passwords… → save as ~/passwords.csv\n"
"\n"
"SETUP FOR SYNC:\n"
"  cider settings set passwords.vaultwarden_url https://vw.6047.in\n"
"  cider settings set passwords.vaultwarden_token <api-key>\n"
"\n"
"  Find your API key: Vaultwarden web UI → Account Settings → API Key\n"
"\n"
"  Optionally set a default CSV path (avoids repeating the path every time):\n"
"  cider settings set passwords.default_csv ~/passwords.csv\n"
    );
}

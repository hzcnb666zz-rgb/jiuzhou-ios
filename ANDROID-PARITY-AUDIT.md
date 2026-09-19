# Android / iOS parity audit

## Iteration status (supersedes the historical findings below)

Reference project: `../MudZJutf8-src/MudZJutf8/app/src/main`. Runtime reference:
`../MudZJutf8-src/MudZJutf8/app/build/outputs/apk/debug/app-debug.apk`.
The existing APK has now been run on Android 11 x86_64, with a loopback-only
deterministic socket fixture (`scripts/parity-fixture-server.ps1`). No production
accounts are used. Source and actual runtime are both required: XML defaults
alone have repeatedly been misleading.

Android phone capture: 1179x2556, density 480, content width 393dp.
Android tablet capture: 1600x2270, density 320, content width 800dp.
The emulator-only NAT rule redirects the APK's old 172.20.10.5:6666 endpoint to
the fixture at host loopback:16666; production app source was not modified.
Local evidence is in `build/android-*.png` and `build/android-*-ui.xml`.
iOS captures are in `build/review-<Actions run ID>/`.

| Area | Implemented correction | Evidence / scope |
|---|---|---|
| L01-L04 | Stats above bottom bar; runtime center/side/weighted bottom dimensions restored | Phone Android bounds: center 294px wide, bottom shortcut 159px wide. Tablet: center 400px, shortcut 222px. Matches width/4 and weighted calculation after pixel rounding. |
| L05-L09 | Width divisors applied to text, actions, stats; description wraps to content; action subtitles hidden | `init_main_face`, `takeobacts`, `longitem.xml`; Android runtime confirms subtitle view remains GONE even after settext2. CoreText line breaking and text padding still need exact comparison. |
| L11-L12 | Centered menu, original buttonx images, Android mode mapping, initial chat height /5 and multiline /3 | Phone runtime menu plus source. Forum/recharge are GONE in XML; their absence is not a defect. |
| L13 | Stretched login background, width/11 fields, width/10 command buttons, unbordered login tab, tap-to-edit credentials | Android login runtime and logind.java. A click test caught the blank part of credential fields not responding; contentShape fixed it. |
| L15 | Two full-width history tabs and right-aligned 150dp close button with original bt1 image | Android history runtime; tab height width/10. |
| R01-R02 | 31 image resources byte-identical; CJK reference font bundled with OFL license; Debug asserts font registration and displayed image loading | SHA-256 checked locally; iPhone/iPad screenshots show actual assets. Center normal background is exitbt.xml (transparent, #6FDCEDC8 1dp stroke, 5dp radius), not a missing PNG; pressed background is exitbt2.png. This does not establish complete resource coverage. |
| L10 | Separate map and paged-text surfaces; pages retain state on n/b and close with q | Android tablet runtime confirms map centered in right panel, pages full-width, text block horizontally centered at top. Build 8 incorrectly aligned page text left; corrected for build 9. |
| P01 | Ordinary input substitutes $txt# or appends space and value | Model test checks emitted command and dialog updates while typing. |
| P02 | cmds, pops, http/https links implemented | Popup parser uses Android's $z2# and pipe delimiters, not ordinary action delimiters. Voice playback remains unported. |
| P03 | 045 embedded web panel, 900 redirect, 997/998 newline semantics | Model tests and source. Live redirected-server and web-service sessions still pending. |
| P04 | ANSI palette, background, bold, fullwidth, day colors, sizing and main-buffer clear implemented | Source comparison; color/font screenshot smoke checks are not complete ANSI conformance tests. |
| P05 | Nested popup command protected from framing; $sock# split confined to confirmation | Core and model regression tests. |
| P06-P09 | Server shortcut persistence, local reload, center edit, buffers, saved description preference, auto stat columns | Source and model tests. |
| P10 | Reward parsing, fallback artwork, quantity field, cancel and inspect behavior | Runtime revealed quantity is ALWAYS visible in this source, even without numb.; confirmation is a centered wrap-content panel on gray, not a full-screen brown fill. Corrected after run e31c569. |
| P11 | Input focus and keyboard, stable dialog identity through action updates | UI test types and submits; model test checks same dialog identity. |
| P12-P13 | TCP keepalive, port persistence, retry after rejected login; ignore obsolete connection frames after redirect | Source and model coverage; no claim of a fresh phone-to-production-server login. |

### Validation runs

- `35447509179` / e73ac06: first iPhone and iPad login/world runtime captures.
- `35448035497` / 31a586e: 12 logic tests pass; login/world/menu/dialog/input captures.
- `35449091283` / 8025c32: matching font and revised rendering compile and launch.
- `35449541522` / d4fe664: UI run FAILED. Input passed; credential hit area and custom-button query failed. Not an accepted delivery.
- `35449882533` / e31c569: 17 logic tests and 3 UI tests pass; 14 phone/tablet captures. Subsequent Android reward runtime found further differences, so this is not a parity sign-off.
- `35450612913` / 2604ea8: build success; confirmation phone capture inspected against Android runtime. Native input padding and system keyboard still differ.
- `35451093032` / e3e5836: 19 logic tests and 5 interaction tests pass; 20 phone/tablet captures. Map/pages source and tablet runtime checked. Missing center default background and page text alignment found afterward; not a parity sign-off.
- Build 9: restores XML center background, exact hes/map-close colors and centered page text. Verification result pending.

### Still open; do not claim exact parity

- Voice record/playback, membership/registration/server-list completeness, and original remote service behavior.
- Map/paged-text long-content scrolling and exact font metrics; floating combat text animation.
- Full ANSI transition coverage, three-component health bars, overlapping or repeated object/action identities.
- Exact line-breaking, font padding, background bounds relative to safe areas, pressed states, long text and rotation, on phone and tablet.
- Actual installed device login and longer gameplay with current production server data.

The aim remains Android parity, not redesign. Passing tests or producing an IPA
does not close these entries. The original audit below is historical evidence;
its statements about absent runtime testing and the earlier menu/subtitle
interpretations are superseded by the evidence above.

Date: 2026-09-19. Audited iOS commit: fbf19ee1997d24d450fdadb3b94447585feb4a72.

This is a source audit, not a claim of runtime or pixel equivalence. No app code was changed during this audit. Android source: ../MudZJutf8-src/MudZJutf8/app/src/main. iOS source: Jiuzhou. Android XML defaults must be combined with Java runtime overrides; dp, physical pixels, iOS points, text metrics and safe areas are distinct.

## Confirmed regressions in the previous calibration

| ID | Android evidence | Current iOS | Effect / required correction |
|---|---|---|---|
| L01 | res/layout/mainx.xml:29 intop/build is above line1; line1 is above menuinss; fcline is above intop | AndroidWorldView.swift:73 puts stats above title | Stats belong immediately above bottom menu, not above title. Restore bottom divider too. |
| L02 | mudmaind.java:1462 setwh(senname,4,15), definition at 2491 | AndroidWorldView.swift:221 uses 92 x 35 | XML initial size is overridden by screenWidth/4 x screenWidth/15. |
| L03 | mudmaind.java:1286 and 1300 set side buttons to screenWidth/7; ce_m11 height set at 1481 | AndroidWorldView.swift:242 fixes side width at 40 | Restore runtime width plus actual XML margins. |
| L04 | res/layout/menuins.xml:31 etc. width 40 plus weight 1; menu icon width 20 plus weight 1 | AndroidWorldView.swift:280 fixes six buttons to 40, icon to 30 | Bottom row no longer distributes available width; on wide devices it leaves unused space. Reproduce weighted sizing. |

## Layout, rendering and resources

| ID | Evidence | Difference / impact |
|---|---|---|
| L05 | Android title font (scrw-14dp)/18; description and hide button (scrw-14dp)/25, mudmaind.java init_main_face | iOS omits 14dp subtraction. Title container is fixed at 40 while hide button is width/13; at 768pt width that button is about 59pt high. Overlap risk on tablets. |
| L06 | Android mainx.xml story_text wrap_content; minimainview fills remaining area | iOS description uses ScrollView capped at 26% of screen height. Changes text placement, scrolling and message area. |
| L07 | Android setwh for direction buttons uses width/5 x width/12 | iOS caps direction width to one third of compass width. Font fixed 12 rather than Android width/33. |
| L08 | Android message font width/28, shortcut width/31, stat font supplied by protocol, top action width/30 | iOS many fixed 11/12/13/14pt sizes; server fontDivisor parsed but not applied to stats/actions. |
| L09 | Android takeobacts uses four layout parameters and label separator pipe for subtitle | iOS actionGrid ignores widthDivisor/fontDivisor, uses hardcoded 390 for height, leaves subtitle text unsplit. |
| L10 | Android oblay.xml text/actions measured within interaction panel; map and more-text use separate overlays | iOS uses one full right-panel interaction view, two-axis text scroller and shared layout for map/pages/dialog. Wrapping, panel bounds and close/paging behavior need separate calibration. |
| L11 | Android mengbans.xml centered multirow menu with drawable buttonx and separators | iOS top-aligned 180pt vertical bordered menu; adds settings/close and omits forum/recharge. No purchases should be performed while validating. |
| L12 | Android XML labels: mud_bt=night, help_bt=normal; handlers map mud_bt to mode mud/huashan and help_bt to mode night/bk2 | iOS labels map night to bk2 and normal to huashan. Visible labels trigger different themes. |
| L13 | Android loginx.xml bitmap background stretched into bounds; logind.java:438 onward runtime input heights width/11 | iOS SplashBackground scaledToFill crops aspect ratios; fields fixed height 40. Both top tabs are bordered, unlike Android's unbordered login tab. |
| L14 | Android loginx.xml registration includes phone/email fields and server-list controls; Java local bypass handles server selection | iOS registration/server-list/user-center are reduced versions; iOS credential validation and character-length constraints require server-contract review. Server selection exists on Android, contrary to earlier claim it was an iOS-only addition. |
| L15 | Android chat.xml TabHost, dimensions adjusted in updateTab | iOS segmented picker and generic close button differ in dimensions, appearance and interaction. |
| R01 | SHA256 comparison of every file in Jiuzhou/AndroidArt against drawable-hdpi-v4 | 24 imported files, zero hash mismatches. Confirms copied bytes, not completeness or runtime display. Other Android resources such as item artwork, menu/overlay drawables and embedded web/media assets are not fully ported. |
| R02 | BundleImage returns clear on load failure; SplashBackground falls back to white | Resource failure can remain invisible. Need runtime assertions/screenshots, not just archive-entry checks. PNG optimization during Xcode packaging means packaged PNG byte hashes need not equal source hashes. |

## Interaction and protocol behavior

| ID | Android evidence | Current iOS / impact |
|---|---|---|
| P01 | mudmaind.java:2040 input_ok substitutes $txt#, otherwise appends space + input | GameModel.swift submitInput only substitutes $txt#/$N. Plain command templates lose entered text. Separate normal-input formatting from numeric confirmation formatting. |
| P02 | myUSpan.java:20 supports cmds:, pops:, voice:, otherwise URLSpan opens URL | MudRichText supports cmds: only; popup links, voice and ordinary web links do not work equivalently. |
| P03 | mudmaind.java:837 handles 045 web; 846 handles 900 server switch; 854/856 handle 997/998 newline mode | GameModel has no cases for these; falls back to printing content. mudsocketd.mudout replaces newlines with semicolons when mode disabled; iOS Transport rejects all embedded newlines. |
| P04 | takespan at mudmaind.java:942 supports background colors, bold, bright palette, fullwidth mode, day palette remapping and clear-screen | MudRichText omits these behaviors; basic ANSI colors use different RGB values. Size code hardcodes 390 and clamps 11...24. |
| P05 | Android parse flow distinguishes escaped popup commands and separate confirmation $sock# splitting | MudDecoder scans every ESC+3digits as a new frame, including potential nested ESC020 in an action; GameModel globally splits $sock#. Need captured nested-command fixtures before changing framing. |
| P06 | Android mainx.xml + takebutton preserve bottom b12...b17 edits from server; cmds_exit reloads local b1...b11 | iOS server buttons are not persisted, toggle only flips visibility, server assignments can mask local custom commands. |
| P07 | Android herename click only acts on configured tag, long press edits senbt | iOS missing center long press, substitutes look when no command. Changes default behavior. |
| P08 | Android main/system/chat/fight buffers use separate limits; main 50, history 500, fight 50; 015 adds to system history | iOS main retains 300; 015 also inserts into main; 024 float animation becomes a notice. 023 server show command overrides local hide preference. |
| P09 | Android 012 accepts layout columns 0 as automatic count/2 | MudLayout clamps 0 to 1, resulting in wrong stat row count for such frames. |
| P10 | Android 010 uses separate duihua screen and item image tokens | iOS generic right interaction loses item artwork/reward layout and full-screen confirmation behavior. |
| P11 | Android 001 focuses input and opens keyboard; 007/008/009 update interaction contents | iOS no input focus management; dialog ID changes can reset text during updates. Verify asynchronous updates during typing. |
| P12 | Android Socket UTF-8 readLine/println with setKeepAlive(true) | iOS UTF-8 line framing aligns in principle but keepalive is not configured. Extra Telnet decline handling is an iOS implementation choice, not an Android equivalence test. |
| P13 | Android local server selection defaults to 172.20.10.5; current iOS default 10.220.35.229, host persisted | Endpoints differ; iOS port edits not persisted. Connection reachability from PC does not prove reachability/authentication from phone. Wrong-password path leaves connected true and server button disabled until return/disconnect. |

## Validation coverage and remaining uncertainty

- build-unsigned.sh runs swift test, then builds Simulator and device Release; it does not boot Simulator or launch the app.
- Package.swift test target contains only Jiuzhou/Core. Six existing tests cover decoding, byte fragmentation, Telnet negotiation, simple actions and an old captured session. They do not exercise GameModel, SwiftUI, login UI, commands sent by controls or visual parity.
- ADB device list was empty during this audit; no connected Android reference device or Android emulator executable was found at work/android-sdk/emulator/emulator.exe. iOS Simulator runtime validation was not performed in this audit.
- Source comparison cannot settle font rasterization, keyboard/safe-area effects, actual hit regions, long text clipping, rotation, or app behavior under delayed/reordered network input.
- Earlier reports overstated completion and misread XML defaults. Current fbf19ee IPA is not parity-verified and contains the four confirmed layout regressions listed first.

## Required acceptance sequence

1. Correct confirmed regressions using final Android runtime values, not XML alone; define density/point conversion and intended portrait/landscape reference bounds explicitly.
2. Add protocol behavior fixtures for normal input, numeric confirmation, layouts with automatic columns, nested popup commands, server buttons and newline mode. Exercise GameModel with an injectable transport.
3. Validate image loading and launch login/world/dialog/chat/menu on iPhone and iPad Simulators; compare computed bounds and screenshots to Android running the same deterministic replay. User screenshots are bug evidence, not the design authority.
4. Exercise keyboard entry, successful and rejected login, creation, movement, NPC actions, customization, reconnect and server switching. Keep the repository private and check free quota before any build.
5. Deliver a new unsigned IPA only with a clear record of which comparisons passed and which remain unverified; user will sign it.

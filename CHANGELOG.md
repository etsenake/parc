# Changelog

## 2.9.0 (2026-11-17)

### New

- **command-bar:** Type a few words from any page's title and the bar sniffs it out of your open tabs, your archive or last month's browsing, and archived tabs hop straight back in when you pick them

### Fixed

- **library:** Let the Library's menu items glide out one after another instead of sprinting past you
- **command-bar:** Let "github" plus Space be a plain old search instead of teleporting you into GitHub's own search box, while Tab still takes you there
- **search:** Show the twenty websites cosplaying as search engines out of the search engine menu, and let Tab search LinkedIn and Wikipedia right from their own pages
- **extensions:** Let extension popups wait until they're drawn, then glide in softly and drift off when closed, instead of blinking in half-ready and vanishing
- **command-bar:** Fill in just the website when you type part of its address, instead of the clingy sign-in page it forwards you to every day
- **extensions:** Hang extension popups just below the button you clicked, whether it's in the sidebar, a toolbar or either half of a stacked split, instead of parking them on top of it or over the other pane
- **command-bar:** Let the bar remember what you actually pick, so typing "okta" stops playing dumb and leads with the page you always choose
- **command-bar:** Trim long result links down to the site and path, light up the bits you typed, and fold repeat sign-in pages into one row instead of a wall of login parameters
- **command-bar:** Keep what you're typing in view while a long completion trails off softly to the right, with the page's title tagging along in grey
- **extensions:** Let extension popups stretch and tuck in smoothly when their contents grow or shrink, instead of hiccuping to the new size in one go
- **library:** Let the Library's side tiles take a breath when you click them, with icons that hop at an easy amble, highlights that glide in and out, and pages that fade in instead of slamming the door
- **extensions:** Light up the extension button you clicked and give its icon a little Dock-style hop until the popup shows up, so slow popups stop pretending they didn't hear you
- **search:** Let Tab borrow a site's own search right on pages like GitLab, march site-search defaults back to Google, and teach Parc to remember the site searches you binned while quietly restocking the ones it fumbled
- **library:** Keep the Media grid in two tidy columns however you reopen the Library, and stop thumbnails from ghosting into blank tiles when you hop between Library pages and back
- **extensions:** Teach pinned extension buttons in page toolbars to glow exactly as bright as the Site Control Center button beside them, so dark mode stops playing favourites
- **media:** Let videos and calls stay put when you click into the app sharing your split screen, so picture in picture only pops out once Parc is mostly out of sight instead of the moment it blinks

## 2.8.0 (2026-11-16)

### New

- **extensions:** Warn on every page when an extension starts debugging the browser, in a Parc strip with Cancel and close that stop it, instead of letting it debug silently

### Fixed

- **devtools:** Bring back the right-click menu in docked Developer Tools, so Edit attribute, Copy, Store as global variable and the rest show up instead of a click that does nothing
- **devtools:** Open View certificate from the Security and Network panels for every origin, and in undocked Developer Tools, instead of doing nothing unless it was the page's own certificate
- **extensions:** Right-click now works in extension pop-ups, extension side panels, embedded extension options and the undocked device toolbar, with Inspect, Copy and Paste, instead of doing nothing
- **automation:** Let Puppeteer, Playwright and ChromeDriver drive their own isolated Parc profile from --user-data-dir, find DevToolsActivePort where they expect it and skip onboarding with --no-first-run, instead of silently using your real profile
- **extensions:** Open file choosers from extension pop-ups and side panels instead of silently cancelling them, and keep the pop-up open while you pick
- **devtools:** Open DevTools on DevTools with Command-Option-I in an undocked tools window, title each tools window after its page, and enable Full Screen and Close Window there
- **devtools:** Show the download arrival in the inspected page's window for screenshots, traces and other files saved from Developer Tools, instead of no sign anything happened
- **printing:** Let Save as PDF work when an embedded page such as extension options prints, instead of the save panel doing nothing
- **install:** Open the downloaded disk image as Parc's install window for real this time, now that Finder can read the map, with each park sign planted on its own little grassy knoll instead of in the sea
- **devtools:** Make View's Zoom In, Zoom Out and Actual Size zoom an undocked Developer Tools window instead of being greyed out
- **extensions:** Confirm folder uploads from extension pop-ups and side panels on their own window instead of refusing them or floating a loose dialog
- **devtools:** Open links, Learn more and Open in new tab from service worker, shared worker, extension and Node Developer Tools in a front tab instead of doing nothing
- **extensions:** Put the debugging warning's buttons in the Tab order as soon as it appears, let pane focus reach it and announce it once when a background tab with one is shown
- **devtools:** Attach Chromium's prompts, such as DevTools' Allow edit files for Workspaces and Local Overrides and the file pickers' folder warnings, to their page or window instead of floating loose mid-screen
- **permissions:** Ask macOS for location access when a site you allow starts using it, so pages like store locators get your position, and show Off in macOS with a Settings button when macOS blocks it
- **permissions:** Show Off in macOS with a Settings button for camera, microphone, notifications and clipboard when macOS blocks them, ask macOS before an allowed site's first notification, and flag macOS blocks on Settings' site pages
- **permissions:** Show a site's first notification once macOS allows Parc to notify, instead of macOS silently dropping it while it asks
- **permissions:** Update Settings' site pages live when macOS turns camera, microphone or notifications off or on, instead of only after a reload
- **devices:** Show Parc's own device picker for Web Bluetooth, WebUSB, WebHID and Web Serial instead of crashing the browser when a site or extension asks for a device

## 2.7.0 (2026-11-16)

### New

- **install:** Open the downloaded disk image as Parc's own install window, with a squiggly arrow, a paper boat and one little drag to Applications
- **pages:** Give every page that can't load Parc's own drawings and words, from nosediving paper planes to a plug toy for offline waits, and dress security warnings in Parc's look without loosening a single safety bolt
- **pages:** Turn parc://chrome-urls into Parc's own directory of internal pages, with every address finally spelled parc://
- **dialogs:** Tell you a page is stuck in plain words instead of Chromium's "Page Unresponsive" robot-speak
- **pages:** Put a little nosedived paper plane on the "This page couldn't open" view so it stops looking like a blank apology
- **pages:** Give every remaining security warning Parc's own words, from wrong clocks to café Wi-Fi sign-ins, and keep the details button saying Details no matter how often you open it
- **pages:** Dress the rare web app offline and organization proxy pages in Parc's look too, so no Chromium error page is left in its work clothes

### Fixed

- **peek:** Make a closed Peek wait its turn on the main thread when it reopens after its page hops windows, by contract now instead of by good manners
- **sidebar:** Let the Pinned header stand up straight at full row height, so its highlight lines up with New Tab instead of crouching beside it
- **spaces:** Keep the window in its Space when you close that Space's last tab, so the start page glows in through your own colors instead of the browser wandering off to another Space
- **updates:** Make See What's New actually open after an update and spotlight the versions you skipped, instead of greeting you with "This site can't be reached"
- **updates:** Retire the Update Complete card's Share Parc row, which was mostly sharing a shrug
- **updates:** Give See What's New a pointing hand and a hover glow on the Update Complete card, so it finally looks as clickable as it is
- Make every SwiftUI button and clickable toast actually show the pointing hand on recent macOS, instead of letting it sneak back to an arrow
- **install:** Hang the install window's icon names on little wooden park signs instead of a clay strip above the sea, so they stay readable in dark mode too
- **peek:** Wake up the greyed-out Split button on a tab you opened in Peek, so one click tucks its page back into its tab and sets it beside yours, just like the preview card's Split View
- **peek:** Let a dimmed Peek Split button perk right back up the moment the Library closes, full screen ends, a tab lands from another window, the split changes or you stay after all, instead of sulking until the page does something
- **pages:** Only offer Go back on an error page when there's actually a page behind it, and fall back to Try again otherwise
- **licences:** Credit Cormorant Garamond for the error page headings it now sets, not just What's New
- **pages:** Hide the monitored-connection warning's Back to safety button, which never did anything, so Details is its one honest control instead of a dead end

## 2.6.0 (2026-11-16)

### New

- **onboarding:** Ask for your favorite sites right after you pick a browser to import, so you're choosing them while your stuff moves in instead of watching it load
- **sidebar:** Teach Command-Z to un-copy, so a Duplicate or Pin to folder copy you regret vanishes and Redo puts it right back where it was
- **import:** Keep your Chrome bookmarks moving in even after Chrome locks them in a safe, and pack the bookmarks and passwords saved to your Google Account too
- **import:** Offer Firefox switchers the same drop-your-passwords step Safari gets, complete with a map to Firefox’s own export button
- **import:** Welcome Zen to the browser lineup and stop Firefox’s hidden account entry from making a clean password import look half-done
- **shortcuts:** Let your number keypad keep its own shortcuts, so Control–keypad 1 stops impersonating Control-1 and Clear quits cosplaying as Escape
- **splits:** Let VoiceOver nudge split dividers and give keyboards Widen, Narrow and Make All Split Panes Equal, so Expand is no longer a one-way trip
- **import:** Take Safari’s own Export Browsing Data zip, so every Safari Profile’s history, your bookmarks and your passwords move in without Full Disk Access or a password scavenger hunt
- **splits:** Trade the split menu's shrugging Share for Copy Links, which scoops up every page in the split as titled links, and let Command-C copy a lone sidebar row too
- **format:** Give Notes and Easels a real Edit › Format menu, so Command-B, I and U finally bold, slant and underline, headings, lists, indents and links come along for the ride, and the checkmarks know exactly what your text is wearing
- **popups:** Show a quiet sign when a site's pop-up gets blocked, with Open, Open All and Always Allow in the site controls card, so sign-ins and course tools stop dead-ending
- **import:** Let password files with thousands of logins move in whole, fed to the importer a bite at a time instead of being turned away at the door
- **task-manager:** Open Task Manager from any window, even a Note, an Easel or an empty Space, and find it in the Window menu too, so a memory-hogging tab has nowhere left to hide
- **sidebar:** Fold Pinned away under a tidy header that shows a little stack of its icons, or just a count while you share your screen, with Collapse Pinned in the View menu and command bar and a roomy Pinned drop spot on empty Library cards
- **import:** Pack the payment cards from Safari's export file too, shredding Parc's copy the moment they're read and leaving out any card you already have
- **import:** Open the door to Chrome Beta, Dev and Canary, Opera GX, Dia, Comet, Helium and ChatGPT Atlas, each found by its real folder and Keychain name
- **peek:** Let two fingers fling a Peek away: the card follows along, taps at the point of no return, springs back if you chicken out, and every close now fades instead of blinking out
- **sidebar:** Let tab, folder and work-site preview cards stretch out to a roomier 288 points, with a bigger still-crisp tab picture and longer lists, while squeezing politely into narrow windows
- **import:** Stop leaving Opera and Opera GX side profiles behind, so each one comes along as its own profile under the name you gave it, minus the throwaway ones Opera wipes on quit
- **peek:** Right-click a tab in a folder's preview card and Open in Peek to see its very own live page float over where you are, scroll, typing and video intact, then close it to tuck it back into its tab or click the tab to bring it home without a single reload
- **peek:** Let Peek float above the whole window, reaching closer to its edges, while the page behind takes a polite step back instead of just sitting there dimmed
- **sidebar:** Quietly keep a week of sidebar backups and offer the newest good one when your saved sidebar won’t open, instead of slamming the door with “Parc couldn’t start”
- **sidebar:** Hold Option while dragging to drop a copy of any tab, folder, Favorite or mixed bunch anywhere in the sidebar, green plus and all, with Command-Z standing by if the twin was a mistake
- **media:** Show the Mini Player's Cast button in speaker-only homes on sites like YouTube, so beaming a tab's sound to your Nest or Google Home takes one click instead of a scavenger hunt through the menus
- **previews:** Give a tab's hover picture its own Open in Peek button right beside Split View, so one hover and one click float that page over yours without a single reload

### Fixed

- **routing:** Save Air Traffic Control routes the moment you change them, so a link clicked with the panel still open already goes to the Space you picked
- **updates:** Give What's New its own parc://whats-new address, so the app's install path stops photobombing your History, copied links and address bar
- **command-bar:** Stop New Parc Note from answering to the old borrowed name it was supposed to have dropped
- **setup:** Skip the iCloud Passwords extension on macOS 15.5 and later, where Apple won't let it talk to Parc, send Safari passwords to import instead, and fess up when it couldn't be added
- **setup:** Name the imported ad blocker that refused to leave with a Couldn’t remove notice, even when it was still downloading after ten minutes, instead of letting it lurk
- **extensions:** Let an extension's right-click menu open and close its side panel instead of greying the option out with an excuse that expired the day the panel moved in
- **extensions:** Only show the Extensions button in private pop-ups when an extension is actually allowed in private windows, instead of opening a party with no guests
- **import:** Ask macOS for a browser's Keychain key just once per import instead of stacking a prompt for every profile, and unlock the rare saved items Chromium sealed with its spare key
- **extensions:** Show the Extensions button only when there's an extension tile behind it, so buttonless background extensions stop ringing the doorbell and running off
- **links:** Teach Option-click to open links in Split View beside your page instead of sneakily downloading them, and let the link preview say Split View only when a split is really coming
- **links:** Let the link preview pill change colours with your Space while it's showing, instead of clinging to last season's theme until you hover again
- **setup:** Check Safari's password helper's own guest list before offering iCloud Passwords, and give setup's Couldn’t add/remove notice a Retry button, Profile names and a seat right after the import notice
- **extensions:** Make an extension's side panel menu say Close Side Panel while the panel is still loading, instead of promising to open the very thing the click shuts
- **links:** Paste renamed tabs under the names you gave them, so copied titled links stop blurting out the page's own title
- **import:** Call Zen by its own name when its profile turns out to be damaged, instead of blaming Firefox for a mess it never made
- **command-bar:** Make clicking a page toolbar's address open the full command bar right where Command-L would, aimed at the pane you clicked, instead of a cramped dropdown that forgot half its tricks
- **extensions:** Let an extension call off its side panel while it's still loading instead of having it barge in anyway, and keep the panel's Open or Close menu item honest when its corner gets tucked away
- **sidebar:** Keep the extension and site buttons beside the sidebar's address in place while their popup or Site Settings panel is open, and always out for VoiceOver, so your password manager's button stops ghosting you mid-login
- **links:** Copy pinned tabs under the title their sidebar row actually shows, not whatever the page has started calling itself since you pinned it
- **command-bar:** Let the sidebar's address editor stretch out to 450 points with its address row lined up over the results, while pop-ups keep theirs tucked neatly inside even the skinniest sign-in window
- **onboarding:** Give every import page after Favorites its own number in the setup counter, so bookmarks and passwords stop squatting on Favorites' step and the total stops fibbing about what's left
- **splits:** Let VoiceOver hear a split divider's new spot after drags, double-clicks, Expand, window resizes and panes coming or going, once it settles, instead of hoarding the news until you bump into it again
- **links:** Let the link preview promise Split View and Peek from whichever pane you're hovering, change its story when the window does while you hold the key, and stop making promises on behalf of ads
- **spaces:** Let Manage Spaces resize itself when a Space is deleted, folded into a folder, undone or redone, or changed from another window, instead of leaving a card-sized hole or shoving the comeback card off the edge
- **tooltips:** Repaint a tooltip that is already showing when its window changes theme, so a keyboard Space switch or theme nudge stops leaving yesterday's colors hanging around
- **library:** Let Media spot iCloud borrowing or returning a photo right away, wait for slow copies to land before redrawing, ditch stale grid math mid-sum and follow a new screenshot folder the moment you pick it
- **import:** Tell you which Profile an imported extension missed and hand you a Retry, and when an administrator, another app or a parent is the real holdout, say so instead of dangling a Retry that can't win
- **developer-mode:** Put the blocked pop-up sign on the Developer Mode toolbar too, so a swallowed sign-in window can't hide behind the stripes
- **windows:** Let the shortcuts panel grey out Copy when the page truly can't be copied, and stop Command-T in a sign-in popup from yanking a busy main window forward for nothing, so a fresh window catches the tab instead
- **links:** Copy titles like Vec<T>, snake_case.py and **launch** as Markdown that pastes exactly as written, instead of letting renderers swallow the angle brackets or turn your asterisks into a bold surprise
- **onboarding:** Count the new browser's pages on Favorites even while your last import is still packing up, so switching browsers mid-import stops sneaking an extra step into the total later
- **shortcuts:** Let French, Belgian, Czech and Lithuanian number rows fire digit shortcuts like Command-Shift-2, and call the keypad's decimal key Keypad , wherever it types a comma instead of insisting it's a dot
- **command-bar:** Keep your Control-Space search text planted right where you started typing, and keep both bars' address rows lined up with their results even when scroll bars refuse to hide
- **toasts:** Let keyboards reach a notice's Share and Retry with Command-Option-Shift-A or Control-F6, hop between them with Tab and send it packing with Escape, all without the notice ever snatching focus from what you're typing
- **windows:** When closing a tab another window is holding can't go through, say why and send it home instead of leaving it squatting, selected, in the window you were tidying
- **sidebar:** Keep the floating sidebar's frosted glass on your Space's own light or dark side, so forced-dark text stops squinting at a pale blur, and let the glass melt from one Space into the next as you swipe
- **peek:** Let a Shift-click inside a Peek open the link right there in the same Peek, Back and swipe included, instead of launching a surprise window, and let links in a page's embedded frames Shift-peek too
- **sidebar:** With Reduce Motion on, tab, folder and work-site preview cards now just fade in and out where they stand instead of zooming out of the sidebar at you
- **tooltips:** Let shortcut keycaps press for Shift-plus-number and symbol shortcuts like Command-Shift-2, so Capture's tooltip finally nods along when you nail it
- **command-bar:** Stop buttons hiding under the command bar from lighting up as your pointer drifts across it, so the bar feels solid instead of haunted
- **library:** Let the Library snap straight to its new width when Reduce Motion is on, instead of swooping across the window each time you visit Spaces or a Space comes or goes, and freeze any swoop mid-air the moment you flip the switch
- **sidebar:** Let VoiceOver call out every Control-Space hop through the sidebar, naming each tab, folder and split, piping up at either end of the list, and keeping its voice down while tabs load in the background
- **private:** Stop private windows from tripping over each other when they open and close at the same moment, so slamming the last one shut and diving straight into a fresh one just works, nothing private lingers afterwards, and Open Link in Incognito Window opens a private window even when none is open
- **windows:** Bring a window Parc reopens on its own back where you left it, with its own size, spot and sidebar, instead of parking it wherever a long-closed window used to sit
- **peek:** Let Undo bring back a closed Peek even after its page wandered off to another window, fetching the page home first just like Reopen does
- **windows:** Give the frozen picture a moved tab leaves behind a real snapshot even when the window holding the page is sitting in the back, instead of a dim blank panel
- **themes:** Let the color knob under your drag puff up like the open hand promises, and keep the Noise label on the dial's middle button so it stops photobombing your spins
- **import:** Keep Parc steady when it's paired with an older engine that only names the extensions it couldn't add, showing the plain Couldn't add notice instead of tripping over the missing Profile and Retry
- **peek:** Once you expand a Peek into a tab, its right-click menu stops treating it like a guest and offers Open Link in Split View like every other tab
- **peek:** Keep the link preview honest over sandboxed frames inside a Peek, saying a new window when that's where your Shift-click really goes instead of fibbing about this Peek
- **themes:** Let colored Automatic Spaces read the room and pick light or dark text from what's actually behind the sidebar, so pale-on-pale stops whispering, and give dark-mode Macs the same dark glass docked as floating
- **sidebar:** Let VoiceOver pick sidebar tabs with VO-Return and gather a bunch with VO-Command-Return for the selected-items menu without ever whisking you off to another tab, and stop background tabs coming and going from wiping a selection you built
- **command-bar:** Let the address editor's icon and text glide out of the sidebar pill and land right on its line, and save a seat for always-on scroll bars so results stop shuffling sideways when the list grows
- **import:** Give every extension that missed its import its own notice and Retry, even when the rest of your data stumbled too, lined up politely behind the Only some of your data imported notice
- **sidebar:** Let New Tab shake off a cancelled press, springing back when you drag away and squishing again when you come back
- **downloads:** Give Reduce Motion fans a calm download hello, with the icon and tray fading in right where they rest instead of doing aerial acrobatics across the window
- **sidebar:** Let Command-S dock the floating sidebar while Spaces are still sliding without a hiccup, so the glass hands off to the window mid-swipe instead of jumping at the finish
- **sidebar:** Let Delete sweep away a bunch of selected empty folders after one quick are-you-sure, with Undo, instead of playing dead, and beep when it truly can't help
- **onboarding:** Make Retry honor the ad blocker you picked in setup, so a blocker you kept out never sneaks back in and a retry that works still leaves just the one you chose
- **splits:** Stop split dividers and the page's edge grip from flashing their resize arrows through the command bar, so the pointer over the bar stays the bar's own
- **peek:** Let your typing follow you to the page underneath the moment a Peek starts fading, and let a Peek whose tab you close mid-fade just leave with it instead of popping back to wave goodbye
- **toasts:** Let Command-Option-Shift-A and Control-F6 stay yours when they belong to a Parc command, and have VoiceOver name the notice, Share or Retry each time keyboard focus hops between them
- **peek:** Let the page behind a tab's own Peek ease back into place as the card fades, instead of snapping forward the moment you put it back
- **spaces:** Trade the mystery beep for a straight answer when a Note or Easel can't move to a Space with its own data, naming the folder, split or Archive entry still holding on to it before you're ever asked to confirm
- **sidebar:** Give long Space swipes a rubber band, so the sidebar stretches gently at the next Space or the first one instead of wandering off into empty nothing while the color daydreams about Spaces further along
- **archive:** Let an archived page's preview pop up over a Note, an Easel or an empty start page too, instead of giving your click the silent treatment
- **themes:** Let the intensity thumb and noise marker puff up a gentle 5% with a deeper shadow when you hover or grab them, fill the dial's dots smoothly as you turn, and keep color knobs honest when they slide under a pointer that never moved
- **start-page:** Let the last tab in a Space bow out gracefully, fading away while the start page glows in through your Space's own colors instead of blinking out
- **archive:** Put Back now rebuilds a deleted folder around its tabs, nested folders, name, icon and spot included, so siblings move back in together instead of drifting loose across Pinned
- **onboarding:** Keep each setup's ad-blocker choice its own, so a download from an earlier setup that fails after you start Replay can't sneak a declined blocker back with a Retry
- **spaces:** Give Share data with and Keep separate the same straight answer moves got, naming the Favorite, Archive entry or other Space still clinging to a Note or Easel instead of refusing in total silence
- **sidebar:** Offer your backups when the saved sidebar has vanished, not just when it's mangled, and stop copies saved while your Mac's clock was time-traveling from cutting the line as the newest
- **themes:** Let the noise dial's marker cast its whole shadow even parked at the bottom, instead of having it sliced off at the dial's edge
- **archive:** Let an archived page's preview open over a tab whose page hasn't loaded yet too, then quietly move in with that page the moment it turns up
- **archive:** Let an archived tab that's open in a preview or halfway out the Archive door still learn its folder's way home when that folder is deleted, so Put Back rebuilds the folders around it too
- **media:** Let protected streams listen when a page switches pitch correction off, so speeding up with a pitch-bending extension finally gives you the chipmunks you asked for instead of a polite shrug
- **sidebar:** Make clearing history over a time range also sweep out sidebar backups saved while your Mac's clock was fibbing, instead of letting a wrong timestamp sneak one past the broom
- **sidebar:** Stop swipes onto the last Space from tapping the trackpad like they meant to make a new one, and let a swipe that catches a long click's slide keep the page and color already on screen instead of swapping in a surprise neighbor
- **peek:** Let a fading Peek bow out with its whole window instead of popping back for an encore, hand your typing to the page underneath every single time, let Stay settle a Peek even mid tab-close, and keep the page behind centred and the fading card in step while the sidebar slides or the window resizes
- **peek:** Let the page behind a Peek that opens mid-slide keep its poise, staying dead centre while the sidebar or Library glides past instead of drifting a couple of points off until the dance ends
- **scripting:** Let scripts grab a tab by its id inside a Space straight away, instead of making Parc call the whole Space's roll first
- **sidebar:** Keep an extension's button beside the sidebar's address standing by from the moment you click it, so it stops ducking out while its popup is still getting dressed
- **peek:** Keep the page behind a Peek dead centre even when a sidebar or Library slide gets interrupted and restarts toward the same spot, instead of trusting the first slide's starting line
- **extensions:** Keep an extension's Open or Close Side Panel item honest even while its menu is open, so a panel that starts or quits mid-menu flips the label before your click instead of after it
- **themes:** Let the sidebar's glass deepen its shade just enough behind mid-tone Spaces on a dark Mac, so tab names stop squinting at you over a bright page while your Space keeps its colors

### Faster

- **tabs:** Let Parc skip the archive when it only cares about open tabs, and stop launch from copying every tab and history visit one at a time
- **easels:** Let web pages inside an Easel nap after four hours out of sight, like regular tabs, instead of hogging memory forever
- **library:** Let the Media page check your photo folders quietly and only redraw when something actually changed, instead of re-sorting the whole pile twice every five seconds to learn nothing moved
- **library:** Let the Media page hear photos land, change or wander off instead of re-checking every file every five seconds, and slip each one into the grid without reshuffling the whole pile
- **scripting:** Let scripts and launchers list all your tabs in one quick sweep instead of making Parc rummage through every tab, archive and all, for each title and URL
- **library:** Keep one lookout per iCloud folder instead of a guard on every photo, so a Desktop full of screenshots stays light while Media is open and Remove Download stops insisting they're in use

## 2.5.1 (2026-11-15)

### Fixed

- **themes:** Redraw the grain, sand, denim and tweed textures and their picker swatches so they read as fine grain, gravel, woven threads and fibre
- **onboarding:** Give the welcome screen soft colour film grain instead of harsh grey static
- **library:** Spring the rail icons when a page is picked and give Easels & Notes the paintbrush from its cards
- **splits:** Snap the split menu icons to the pixel grid so they render crisp on retina
- **sidebar:** Centre the New Split menu icon's plus inside its right pane instead of crowding the edge
- **library:** Make the Library button's hover glow rise from the box instead of fading toward it
- **settings:** Give the membership card a fine date-ticket hatch and vivid fallback gradients
- **themes:** Match the theme editor's dot grid weight and give the sun icon short rays close to its disc
- **onboarding:** Fill the welcome orb's mask to its canvas so the opening orb appears at full size
- **shortcuts:** Give the shortcuts keycap face livelier head moves, snappier blinks and a bigger wink
- **window-frame:** Render the crank at twice your screen's sharpness so its curves and shadow stop looking like they were cut out with safety scissors

## 2.5.0 (2026-11-15)

### New

- **onboarding:** Give the welcome headline, setup titles and Easel Hip text new open-licensed typefaces
- **onboarding:** Welcome new users with Parc's own intro music
- **library:** Give Notes cards Parc's own P and Easel cards a paintbrush
- **about:** Show Parc's licence, warranty notice, licences page and source link, list every bundled font, icon set and library on the licences page, and finish scrubbing reverse-engineering notes
- **sidebar:** Draw the New Space, New Tab and New Split menu icons in Parc's own hand
- **site-controls:** Draw the Control Center, Copy Link and full-page capture icons in Parc's own hand
- **sidebar:** Give the New Split icon two equal halves and a plus sized to them
- **navigation:** Draw the hard-refresh icon in Parc's own hand
- **splits:** Draw the split-view menu icons in Parc's own hand
- **pages:** Show a wilting flower when a page crashes
- **library:** Draw the Library button's box of things, its hover glow and the download placeholder in Parc's own hand
- **capture:** Draw the screenshot cursor in Parc's own hand
- **sidebar:** Draw the floating sidebar's shadow in Parc's own hand
- **themes:** Draw the theme editor's texture knobs and dot grid in Parc's own hand
- **themes:** Animate the sun, moon and automatic appearance icons in Parc's own hand
- **library:** Animate the Library rail's Media, Downloads, Easels, Spaces and Archive icons in Parc's own hand
- **settings:** Draw the membership card's masks, blob, stripes and fallback gradients in Parc's own hand
- **onboarding:** Give the welcome orb, background, grain and favorites Parc's own videos and the services' official logos
- **switcher:** Draw the recent switcher's Note, Easel and private-page fallbacks in Parc's own hand
- **capture:** Play Parc's own shutter sound when a capture completes
- **themes:** Fill the theme editor's preset pages with Parc's own palette
- **shortcuts:** Animate Parc's own winking face on the shortcuts keycap
- **settings:** Give the alternate app icons their own names and carry saved choices over

## 2.4.0 (2026-11-14)

### New

- **spaces:** Swap Set Profile for Share data with, warn only when it costs something, and give Settings a Spaces pane

### Fixed

- **private:** Show the Incognito pill in every private window instead of only when you have a second profile
- **settings:** Give search engine, suggestions and download folder back to each Space, since they travel with its data
- **spaces:** Only delete a Space's data under the warning you actually saw, and let Settings' Delete Space and New Space always follow through

## 2.3.0 (2026-11-14)

### New

- **settings:** Pick your search engine and download folder once in General and every Space follows along
- **spaces:** Give every Profile its own Space, let Spaces share data or keep separate, and let each Space pick its own Auto-Archive timer
- **profiles:** Let the Default Profile retire like any other, handing the crown to a Profile that still has a Space
- **spaces:** Make New Space ask who to share data with, work from any window and keep Profiles out of sight
- **start-page:** Lay the start page on solid paper tinted from your Space, with each theme colour glowing from its corner, the multi-colour logo, and light or dark that follows View → Appearance
- **window-frame:** Hand every window a little crank so you can wind the frame from a hairline to a gallery, with clicks that climb as it opens

### Fixed

- **sidebar:** Give the Done button room for its whole name and let a double-click on the Space name start renaming
- **settings:** Let a search engine picked inside a Space become everyone's pick, and stop stale or failed writes from sneaking past it
- **spaces:** Retire the little profile badge from Space headers and the profile pill from Space dock tooltips
- **command-bar:** Say Space Preferences, drop New Profile, and tell same-named Spaces apart by position
- **menus:** Drop New Profile and Change Profile from the app menus
- **links:** List Spaces by name when picking where a link opens
- **tabs:** Warn that a Space uses different data instead of a different profile
- **downloads:** Stop naming profiles on download rows and loading messages
- **spaces:** Say Space instead of profile in capture, notes, easel, import and scripting text
- **downloads:** Retire the profile filter since profiles are going invisible
- **links:** Tell same-named Spaces apart in the link destination list
- **spaces:** Keep leftover link rules converting until they land on a Space and hand the Default crown only to data that still has a Space
- **spaces:** Keep same-named Spaces apart in the share picker, give it room to breathe, and send New Space to the form you already have open instead of a minimized window
- **spaces:** Make New Space ask your Peek to hang up first when the camera or mic is live, then carry on into the new Space form
- **spaces:** Keep a second New Space press from hanging up your Peek call, and run just one wait at a time
- **spaces:** Show each Space's icon in the New Space sharing picker on macOS 27
- **command-bar:** Give Adjust Window Frame its window icon in the command bar

## 2.2.0 (2026-11-14)

### New

- **swipe:** Lay out the welcome mat for the new Back and Forward swipe indicator
- **swipe:** Tune swipe-and-hold to a snappier 0.3 s, give the indicator some stretch, and keep scrolling long histories while your fingers rest at the trackpad's edge
- **swipe:** Swipe Back or Forward and a frosted circle slides in with the chevron, then hold to morph it into a scrolling list of where you've been
- **swipe:** Hand Back and Forward swipes to Parc's own recognizer, so the frosted circle and hold-for-history list show up on every page, split pane and Peek, even in windows you aren't looking at
- **swipe:** Rest your fingers to open the history list on the page you're on, slide back to fold it into the circle, and keep edge scrolling from twitching on its own
- **start-page:** Give empty Spaces a page of their own, with a command bar on Note paper and a Parc logo that does three different tricks

### Fixed

- **swipe:** Let Back and Forward swipes land on the page under your fingers, even in a window or split pane that isn't paying attention
- **swipe:** Let a resting hand wait for the history list without trembling it shut, and say plainly that AppKit decides a Magic Mouse commit
- **peek:** Peek ditches its title bar, moves to round theme-colored buttons on the right and lets your Space's colors wash over the page behind it
- **library:** Wait for a hover on the Library button before asking for your Desktop and Documents, instead of ambushing you right after onboarding
- **engine:** Open again on Chromium 157 with its earlier-sandboxed helpers, and keep translation, auto sign-in and new-extension pinning as before
- **swipe:** Keep the swipe circle's shadow from fading on a theme flip and drop the row lean when the list folds away
- **swipe:** Keep a picked history row when the fingers drift a hair sideways, and fold the list away without cancelling the swipe
- **engine:** Point the engine framework's Aperitif link at the library beside it instead of Chrome's install path

## 2.1.2 (2026-11-13)

### Fixed

- **passwords:** Keep passkey sheets, card-name fixes, extension panels and held tabs behaving on the new Chromium
- **engine:** Bring Chromium 157's security fixes to Parc

## 2.1.1 (2026-11-12)

### Fixed

- **engine:** Pull in Chromium's latest security fixes so sneaky videos, PDFs and extensions have fewer holes to climb through

## 2.1.0 (2026-11-12)

### New

- **settings:** Give Settings a glow-up with a sidebar, glass back and forward buttons and a proper Edit Profile page

### Fixed

- **profiles:** Ask for a new profile's name right where you are, and give renaming the proper Parc dialog

## 2.0.0 (2026-11-11)

### Heads up

- **engine:** Plug Parc's engine into Chromium's own hooks so new Chromium versions land fast

### Fixed

- **media:** Stop a closing protected video from walking off with another video's speaker icon

## 1.13.0 (2026-11-11)

### New

- **engine:** Give Parc a brand-new Chromium engine, freshly patched against the web's latest troublemakers
- **extensions:** Give the Remove extension dialog Parc's good looks and a red button that means business
- **dialogs:** Dress up page alerts, confirms and prompts in Parc's own sheet so sneaky timed Return presses can't click OK for you
- **dialogs:** Give name prompts a cozy rounded field and swap the stock checkbox for the onboarding circle
- **dialogs:** Match engine dialog fields and checkboxes to the app's cozy card and onboarding circle, and wrap crowded buttons
- **passwords:** Give password, address and card save prompts Parc's own sheet, with Never on this site politely off to the side
- **sign-in:** Restyle website sign-in with roomy labelled fields that glow blue instead of wearing a focus ring
- **apps:** Show open-in-app requests in Parc's dialog with the app's own icon front and center
- **pages:** Ask about frozen pages in Parc's dialog, where Escape now just means keep waiting
- **notifications:** Dress the notification permission nudge in Parc's dialog so Never Mind answers Escape
- **windows:** Put download, caret browsing and private window decisions in Parc's dialog
- **devtools:** Give DevTools-window alerts and prompts Parc's dialog, round checkbox and all
- **extensions:** Bring enterprise, parent-approval and repair install requests into Parc's dialog, cozy password card included

### Fixed

- **spaces:** Let your only Space swipe invite a friend
- **profiles:** Let Delete Profile ask nicely in one plain dialog instead of making you type its name
- **files:** Keep Image Files from vanishing in upload dialogs
- **dialogs:** Evict the last macOS pop-ups so every alert, rename and error talks like Parc
- **windows:** Give every window and every split pane the same frozen picture of a moved tab instead of leaving some staring at white
- **windows:** Let every pane of a moved split keep its frozen picture without borrowing focus from your keyboard

## 1.12.3 (2026-11-11)

### Fixed

- **dialogs:** Bring a page's silenced alerts back when Chromium resets the page
- **pip:** Give picture-in-picture captions the screen details they were squinting without

## 1.12.2 (2026-11-10)

### Fixed

- **pages:** Stop new tabs from needing a nudge to appear

## 1.12.1 (2026-11-10)

### Fixed

- **pages:** Size new tabs before showing their content

## 1.12.0 (2026-11-10)

### New

- **sidebar:** Show a tab's picture, title and site when you hover over it, with a button to open it in Split View
- **settings:** Turn off the tab picture preview in Previews Settings

### Fixed

- **updates:** Keep download progress and byte counts steady
- **site-controls:** Show the Site Control Center's section headings in plain black or white so they're readable in any theme
- **updates:** Keep See What's New readable when you hover over the Update Complete banner
- **site-controls:** Turn Developer Mode on from the Site Control Center, and keep its capture and Clear Cache controls available while it's open
- **toasts:** Keep toast icons and secondary text readable in light and dark mode
- Show the pointing hand over every button and clickable control
- **pages:** Show a tab opened by the click that brings Parc to the front instead of leaving it black until you switch apps

## 1.11.0 (2026-11-10)

### New

- **extensions:** Show a pinned extension's menu in your Space's colours beside its button, without closing the Site Control Center
- **developer-mode:** Turn Developer Mode and the developer tools on and off together, from the Site Control Center or any developer shortcut

### Fixed

- **extensions:** Show why an extension menu item is unavailable when you rest the pointer on it

## 1.10.0 (2026-11-10)

### New

- **updates:** Check for updates every four hours
- **updates:** Restart to install a downloaded update while your Mac is locked or asleep
- **whats-new:** Set the What's New page's headings in a calligraphic italic serif over a grainier header
- **updates:** Install a downloaded update after half an hour without keyboard or mouse use
- **extensions:** Show an extension's Site Control Center menu in your Space's colours, beside its tile
- **whats-new:** Show every Parc release on a timeline under the current one
- **whats-new:** Mark the releases you skipped when you open What's New after an update

### Fixed

- **sidebar:** Keep rows lighting up on hover beside the sidebar's resize edge
- **whats-new:** Stop stretching the Parc logo on the What's New tab
- **extensions:** Keep the Site Control Center open while an extension's menu shows
- **menus:** Open What's New, History and Extensions in a new tab right away and show them loading
- **extensions:** Open Manage Extensions, Add Extension and site settings in a new tab right away
- **engine:** Say Parc instead of Chromium in menus, dialogs, settings and notifications
- **extensions:** Keep the Site Control Center and extension menus inside the window from every toolbar and split pane
- **engine:** Say Parc instead of Chrome where a menu, dialog or setting means this browser

### Faster

- **whats-new:** Load the What's New page faster with a right-sized logo

## 1.9.0 (2026-11-09)

### New

- **menus:** Open the bundled What’s New page from Help ▸ Release Notes
- **updates:** Check for updates from the Parc menu
- **sidebar:** Show Update Complete with See What’s New after Parc updates
- **sidebar:** Add a hover gradient and sparkles to Update Complete
- **sidebar:** Show Restart and Update when a Parc update is ready
- **sidebar:** Open the update-ready banner from its title

### Fixed

- Correct browser chrome, onboarding replay, and About panel
- **command-bar:** Make Edit Theme… and other window commands work from the command bar
- **command-bar:** Center and restyle search scopes in the command bar
- **command-bar:** Stop row labels, keycaps and the privacy banner clipping their text
- **updates:** Resize the window that says Parc is up to date
- **whats-new:** Reopen saved What's New tabs at this version's page and leave its file address out of link copies
- **whats-new:** Show the page's title instead of its file address in the toolbar, Copy URL, Share and address edit
- **whats-new:** Show the page's title in the sidebar address and keep its file address out of the command bar and Archive
- **command-bar:** Open the command bar inside the browser window
- **command-bar:** Show hover text only on the unavailable Check for Updates… row
- **sidebar:** Reach every update banner control from the keyboard
- **whats-new:** Hide only Parc's own What's New address and leave other apps' pages where they are
- **command-bar:** Keep window commands and their shortcuts working while the command bar is open
- **capture:** Leave the What's New page's file address out of its captures and their shares
- **whats-new:** Offer no shared quote on the What's New page, whose link would be its file address
- **sidebar:** Keep rows and buttons under the command bar from lighting up on hover

## 1.8.2 (2026-11-09)

Small fixes and improvements.

## 1.8.1 (2026-11-09)

Small fixes and improvements.

## 1.8.0 (2026-11-09)

Small fixes and improvements.

## 1.7.0 (2026-11-08)

Small fixes and improvements.

## 1.6.0 (2026-11-08)

Small fixes and improvements.

## 1.5.0 (2026-11-08)

Small fixes and improvements.

## 1.4.1 (2026-11-08)

Small fixes and improvements.

## 1.4.0 (2026-11-07)

Small fixes and improvements.

## 1.3.8 (2026-11-07)

Small fixes and improvements.

## 1.3.7 (2026-11-07)

Small fixes and improvements.

## 1.3.6 (2026-11-07)

Small fixes and improvements.

## 1.3.5 (2026-11-07)

Small fixes and improvements.

## 1.3.4 (2026-11-07)

Small fixes and improvements.

## 1.3.3 (2026-11-07)

Small fixes and improvements.

## 1.3.2 (2026-11-07)

Small fixes and improvements.

## 1.3.1 (2026-11-07)

Small fixes and improvements.

## 1.3.0 (2026-11-06)

Small fixes and improvements.

## 1.2.0 (2026-11-06)

Small fixes and improvements.

## 1.1.1 (2026-11-06)

Small fixes and improvements.

## 1.1.0 (2026-11-05)

Small fixes and improvements.

## 1.0.0 (2026-11-05)

Small fixes and improvements.

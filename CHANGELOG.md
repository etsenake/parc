# Changelog

## 2.16.0 (2026-11-22)

### New

- **notes:** New notes start with a random gallery cover already in place
- **easels:** The tool bar floats at the bottom now, rises in with a sliding pill, and tools hop, tilt and wiggle awake when you pick them
- **easels:** Swatches, shapes, templates, the timer and the page list get lift, squish, rolling digits and a sliding page marker
- **easels:** Code Copy morphs into a check, the crop zoom knob grows under your finger and the web link box shakes at a bad address
- **easels:** Stamps slam down with an ink splash, stickies drop like paper and deleted objects puff away
- **easels:** Jumping to a find result gives the object a little pop and glow so your eyes land on it
- **easels:** Held stamps hover and breathe, pop through each size with a tick, and the stamp wheel fans out and flies your pick to the pointer
- **easels:** Guides fade in with a little pop and snapping to guides, 15° turns or a matching size clicks under your fingertip
- **easels:** Connectors made for you draw themselves, arrowheads pop and shapes glow as an end clicks onto them
- **easels:** Sections light up like a tray while you carry things over and flash when you drop them in
- **easels:** Mind-map branches fold away, unfold outward and new topics grow out of their parent
- **easels:** Flipping pages slides the board with a soft cross-fade
- **easels:** Stickies ease to their new height as you type
- **easels:** Table rows and columns slide open and close up
- **easels:** Erased strokes poof away
- **easels:** Mermaid imports cascade in, restyles cross-fade cleanly and the motion guide covers the whole desk
- **easels:** New connectors just draw themselves on, and expanding a mind-map branch unfolds its topics level by level
- **peek:** Notes and Easels float up in a Peek from their hover card, still fully editable, and the card's buttons wear Parc's own tooltips
- **easels:** Easels learn audio, files, PDFs and block equations, and new media objects can start empty like a note's block
- **easels:** Links and text sizes in Easels use the Notes link box and size menu, links to notes open the note, and hovering a link shows its open, copy, edit and remove card
- **easels:** Adding a web image to an Easel picks the Easel from a Notes-style card instead of a pop-up window
- **easels:** Audio, files, PDFs, linked videos and Unsplash credits now show up in your exported Easels instead of vanishing
- **easels:** Drop a stack of PDFs, songs and files on an Easel and they line up neatly in one row
- **easels:** Media, Web and Code buttons put empty images, videos, audio, files, PDFs, embeds, bookmarks and equations on the board, with every one in the ⌘/ menu
- **easels:** Highlight words in Notion's nine colours and mark them as code from the text toolbar, with ⇧⌘H to repeat the last colour and Turn Into wearing the Notes rows
- **easels:** Type / in Easel text to open the Notes block menu, turn the line into a heading, list or quote, or add a sticky, shape, image or table beside it
- **easels:** Custom emoji from your Notes library work as stamps, saved by name and drawn from the library
- **easels:** Block equations typeset with the Notes math renderer, edit in the Notes equation editor and export as vectors
- **easels:** Notes and Easels link to each other both ways, and an Easel can be locked, take a default font and count its words
- **easels:** Copy an Easel as Markdown or export it as a Markdown file, headings, lists, tables and code all in reading order
- **easels:** Send objects to another Easel, drop a note or Easel from the sidebar onto the canvas, paste and copy HTML and Markdown, and print an Easel
- **easels:** Give an Easel a page icon from its title row, with the same picker notes use, and see it everywhere the Easel shows
- **easels:** Duplicating an Easel keeps its icon, and open Easel tabs show it in the command bar
- **easels:** Type @ or [[ in Easel text to mention a note or a date, set reminders that ring like a note's, and use your custom emoji
- **easels:** Links on an Easel become proper bookmark cards with the page's title, blurb and site, saved for offline and exports
- **easels:** Mentioning a note in an Easel counts in its backlinks, and the mention follows the note when it's renamed or moved
- **easels:** Dropping a note from the sidebar onto an Easel makes a note mention, and hovering a mention offers Open like a note link
- **easels:** Notes typing shortcuts work in Easel text: ==highlight==, ~strike~, **bold**, $math$, arrows like -> and =>, and $$ for a block equation
- **easels:** Videos, audio, files and PDFs on an Easel wear the Notes players and cards, and empty media fill straight from Upload, a link or a drop
- **easels:** The slash menu's Mention, Date and Inline equation rows work in Easel text
- **easels:** Mention and equation buttons join the text toolbar, with ⇧⌘E for an inline equation
- **easels:** Empty Embed and Bookmark objects take a link like a note's block, Embed searches DuckDuckGo too, and a pasted link offers Paste as
- **easels:** Add to-do lists and dividers to Easel text, with Notes-style boxes you can tick, fading ticked items and a pop
- **easels:** Typing --- on its own line in Easel text draws a divider, like in a note
- **easels:** Click a date or inline equation in a selected Easel object to change it right on the canvas

### Fixed

- **easels:** Sticky notes show their text again as soon as you click away instead of staying blank until something else redraws them
- **easels:** Hidden section counts update as objects move in, connector labels stay readable after switching light or dark, and group outlines and badges no longer linger half drawn
- **easels:** Code blocks and web captures show their buttons when you hover them, just like in Notes
- **easels:** Tables show their add and move controls as soon as you hover them, no click first
- **easels:** Pinching an Easel below 100% no longer crashes Parc, and a ⌘-scroll zoom stops when your fingers lift instead of gliding on or taking over a scroll's glide
- **easels:** Stickies, shapes and mind-map nodes show their + dots the moment you hover them, and clicking a mind map's + or a collapsed branch finally does something
- **easels:** Mind-map and quick-create + dots no longer leave stray pieces behind when you zoom out and start typing, select something else or click away
- **easels:** Dragging the fill opacity slider updates shapes as you drag instead of only when you let go
- **easels:** Copying and pasting text in a scaled-up sticky keeps its size instead of shrinking or ballooning when it lands
- **easels:** Escape out of a sticky or text box leaves it selected, like tables and code blocks, so a second Escape deselects
- **easels:** Drag a sticky's or shape's + dot onto another object to join them with a connector, no tool switching and no surprise copy
- **easels:** Table cells keep their text when you Tab or click to another cell instead of going blank
- **easels:** Tab and Shift-Tab while typing in a mind-map node keep your caret instead of selecting the text so the next key replaces it
- **easels:** Headings, lists and markdown shortcuts in a resized sticky come out at the sticky's size instead of tiny or huge
- **easels:** Shapes and text boxes you draw with the tools pick up the colour, fill and lines you last gave one instead of the old grey look
- **easels:** The right-click Shape menu stays available when a selection mixes locked and unlocked shapes, like the toolbar's shape picker
- **easels:** Undoing or deleting table columns under a resting pointer, pasting Easel text with a broken size, and saving a version of an Easel with a damaged date no longer crash Parc
- **easels:** Undo goes straight to your previous change after you undo all your typing, instead of needing an extra press that does nothing
- **easels:** A section title you're renaming is kept when you switch page, export, restore a version or close the Easel instead of snapping back
- **easels:** Typing a new Easel title undoes in one step instead of one letter at a time
- **easels:** Leaving an Easel inside a note finishes the edit and clears its selection, and its errors and Copied Image toast show like in the full editor
- **easels:** A page name you're typing in the page list is kept when the list closes instead of going back to the old name
- **easels:** Paste in an object's right-click menu lands where you clicked, like Paste Here on empty canvas
- **easels:** Duplicate in the selection toolbar's More menu works on locked objects, matching ⌘D and the right-click menu
- **easels:** Undo and Redo select what they bring back or change, holding an arrow key undoes as one step, and Delete is greyed out for locked objects
- **easels:** A crop you're adjusting is kept when you switch page or close the Easel instead of being thrown away
- **easels:** Command-click adds an object to the selection instead of replacing it
- **easels:** Export Selection works in an Easel inside a note instead of always being greyed out
- **notes:** Uploading an image for a note's icon or cover works instead of the picker closing and dropping the file you chose
- **notes:** The typing cursor no longer takes over buttons, checkboxes and menus in a note, so they show the pointing hand or arrow without flickering as you move
- **notes:** The note's ••• menu button at the top right sits on a solid plate with a bolder icon and stays visible instead of hiding until you hover
- **notes:** Note pickers close when you click a toast or another Parc panel, and a covered text field never shows the typing cursor
- **notes:** Menus, pickers and popovers in a note hold their cursor, with the hand on rows and buttons and the typing cursor only in their text fields, instead of flickering with whatever sits underneath
- **notes:** Image, video, link, embed and capture blocks show the pointing hand on their buttons and covered blocks no longer change the cursor under a menu
- **notes:** Views underneath a note menu can never claim the cursor, even the page itself
- **notes:** Add icon opens the icon picker under the new icon, and choosing an emoji, Random, an image or a cover keeps the picker open until you click away
- **notes:** The note icon, cover, emoji picker and emoji suggestions show the pointing hand on what you can click and the typing cursor in their search box, and no longer change the cursor or light up under a menu
- **notes:** Checkboxes, toggles, handles and table grips show the pointing hand, and block hover chrome and cursors no longer react through an open menu
- **notes:** Cursors settle correctly when a note menu opens, closes or scrolls under a still pointer, and covered calendar days and embed resize handles drop their hover
- **notes:** Table column edges show the resize cursor again instead of the typing cursor, and block handles come back on their own when a menu closes
- **easels:** Dragging a tool over the floating bar hides its ghost and drops nothing, and the current-tool pill never stalls mid-slide
- **easels:** The selection toolbar stays clear of the floating tool bar near the bottom of the board
- **easels:** An empty Easel only shows the template rows that fit above the floating tool bar, so no card ever hides half-tucked beneath it
- **easels:** Live page cards only cast a shadow when they land, and slamming stamps never leave a smudge at their edges
- **easels:** Rolling timer digits no longer hop on fast changes, the 00:00 glow stops when you reset and template cards drop back when the pointer leaves
- **easels:** Tables closing up and stickies shrinking as you type never get cut off at the bottom on boards with live pages
- **easels:** Typing near the bottom keeps your caret above the floating bar, and the bar stops staying faded after you switch away mid-drag
- **easels:** Drawing a connector ticks once when its end lands instead of every frame, and grabbing an attached end stays quiet
- **easels:** Table slides settle the moment you undo, redo or edit again, and section glows never clip on live-page boards
- **easels:** New lines in a growing sticky stay tucked inside the paper while it eases taller
- **easels:** Collapsing or expanding two mind-map branches at once folds every topic into its own branch
- **easels:** Clicking through colours quickly blends smoothly from what's on screen instead of popping
- **easels:** Held stamps land at the size you let go, the stamp wheel steps aside the moment you pick, and find pulses wait for a pop to finish
- **easels:** The opacity slider stays crisp while you drag it instead of cross-fading on every nudge
- **easels:** Closing find in an Easel no longer hands the keyboard back to a control that's hidden or tucked away
- **easels:** Arrow-key nudges made after a pause undo on their own instead of merging with ones from minutes earlier
- **easels:** Markdown copies and exports include audio, files, PDFs, block equations and bookmark titles
- **easels:** Restoring an older version of an Easel brings back the icon it had then too
- **easels:** Escape in the equation editor puts back the TeX you started with, and a blank equation is always removed when editing ends
- **easels:** Failed picture or PDF downloads say so plainly, and the search list closes when its empty Embed goes away
- **easels:** A file named .zip or .txt that happens to start like an MP3 stays a file, and only files with no known extension are sniffed
- **easels:** The Web button always adds something, the Code menu hides what isn't offered, and the toolbar and ⌘/ agree on what's available
- **easels:** A locked Easel only undoes or redoes its lock, still follows renamed notes, and Send to Easel and History restore no longer leave stray pictures or fail on a missing icon
- **easels:** An open Easel's icon edits reach the sidebar and command bar, and image icons drop back to the Easel mark when their picture goes missing
- **easels:** Highlighting inline code keeps it code, and highlighted words keep their light-theme colour in HTML and SVG exports
- **easels:** Picking a slash block is one Undo, /equation lands beside the text, and the menu's words match Notes
- **easels:** Custom emoji stamps draw from your profile's Notes folder instead of whichever folder has emoji first
- **easels:** The mention and equation buttons and the DuckDuckGo search rows use the words Notes uses
- **easels:** Markdown copies of Easel text keep to-dos, dividers and note mentions
- **easels:** Copies, CSV and find never show stray object characters, equations that can't typeset still export as TeX, and inline payloads have a size cap
- **easels:** Reminders in an Easel move with it to another Profile and come back when a deleted Easel is restored
- **easels:** Undo names for mentions, dates, reminders, equations and emoji read in sentence case, and Turn Into says To-do List
- **easels:** Dropping, undoing or locking while a picture or video loads no longer shows a bogus error, and link and download messages read plainly
- **easels:** Undo names for icons, dates, equations, sending and default text read in sentence case
- **easels:** Pictures and Easels that are too big now say so plainly, with the size that fits
- **easels:** Exported equations write tidy scale numbers, and the equation checks finally get a seat in the Easel test run
- **accessibility:** Label a button's own copy of its artwork so buttons sharing an image or AppKit's placeholder keep their own names
- **engine:** Keep the picture-in-picture slider building

## 2.15.0 (2026-11-21)

### New

- **easels:** Swap the cramped text rail for a floating toolbar that hovers over whatever you select, keeps its size at any zoom and ducks out of the way while you drag
- **easels:** ⌘F finds and replaces across a whole Easel, lighting up every match on the canvas and gliding to each one
- **easels:** Duplicate with ⌘D or an Option-drag, group with ⌘G, lock with ⇧⌘L and shuffle layers with ⌘] and ⌘[, while locked things let your clicks slip right through
- **easels:** Sticky notes land as soft paper squares with a little lift, go wide, widen with a side drag and scale text and all with a corner
- **easels:** Pictures on an Easel crop in place with a zoom slider and turns, wear the Notes masks, carry alt text, swap without moving and play GIFs when you pick one
- **easels:** Paste cells from Numbers, Excel or Sheets onto an Easel and get a real table to type in, Tab through, resize, merge, colour and export as CSV
- **easels:** Table cells answer to Option keys for adding, moving and resizing rows and columns, and VoiceOver can hop straight into editing them
- **easels:** Paste Mermaid flowcharts and ER diagrams onto an Easel and get real shapes, arrows and sections to keep editing
- **easels:** Sections get a title tab you can click, drag and rename, a marquee that works inside them, hidden contents and a VoiceOver landmark
- **easels:** Text you click to place widens as you type, text you drag wraps at your width, and whole objects align left, centre or right
- **easels:** Drag a text corner to scale the words with a size badge riding along, and pick any size from 8 to 400 with Custom
- **easels:** ⌥⌘L, ⌥⌘T and ⌥⌘R line selected or edited text up left, centre or right
- **easels:** Right-click a table cell and the menu works on that cell, the way spreadsheets do
- **easels:** Doodles glide out smooth with no lag, Shift lays them dead straight, a tap leaves a dot and fresh ink no longer hides under a selection outline
- **easels:** Give a text, shape or sticky its own link with ⌘K, then open it from the little link badge that rides its corner
- **easels:** Type a colon and a couple of letters in Easel text to pick an emoji from the same list Notes uses, or finish the :shortcode: and it swaps itself in
- **easels:** Typed markdown in Easel text grows #### headings, > quotes that keep going on Return, and `inline code`
- **easels:** ⇧⌘/ hops into the selection toolbar from the canvas or mid-sentence, just like it does in Notes
- **easels:** The selection toolbar learns to align, distribute, tidy, group, section, lock and unlock, plus wide stickies and a section's rename, lock and hide options
- **easels:** Pictures get Crop, Mask, Replace and Alt text right on the selection toolbar, which bows out while you crop
- **easels:** The selection toolbar lines text up, picks washi patterns, and gives tables their own typeface, size, colours and Merge cells
- **easels:** Bold, italic, underline, strikethrough and text size work on selected table cells, or the whole table, without opening a cell
- **easels:** Colour the words in a shape or sticky without touching its outline or paper, in one Undo step
- **easels:** Right-click text, a shape or a sticky for Text Color and pick from the palette
- **easels:** The selection toolbar's Link button gives a text, shape or sticky its own link when you're not typing
- **easels:** Right-click anything on an Easel to paint it in Notes' nine colours, fill it, or make its lines thin, thick, dashed or dotted
- **easels:** Arrows grow up into connectors that snap to any object, route straight, elbow or curved, wear a dozen heads and a label, and stickies and shapes sprout plus dots for the next step
- **easels:** Easels answer to tool keys like V, S, R, O, T, L and X, pan with H or a held Space, and zoom with ⌘+, ⌘−, ⇧1, ⇧2 or ⌘-scroll
- **easels:** The Easel toolbar grows up into grouped tools with shape, connector and draw pickers, drag-to-place buttons, a zoom menu that takes a typed percentage, and a Recenter chip
- **easels:** Press ⌘/ in an Easel to find any tool, shape, insert or zoom by name, and Escape lets go of the selection before it puts the tool down
- **easels:** Easel tools now drop real stickies, sections, tables, code blocks and growing text, Mermaid joins the inserts, and right-click offers Zoom to selection
- **easels:** HTML exports show sticky notes as real paper and sections with their title tab and border, in light and dark, and leave hidden contents out
- **easels:** Easel objects can now be turned and mirrored, drawing, exporting and taking clicks at their new angle
- **easels:** Grab just past a corner to spin things in tidy 15° steps (or freely with ⌘), flip with ⇧H and ⇧V, nudge the angle with ⌥ and the arrows, or pick Flip and Rotate from the menu and VoiceOver
- **easels:** Shapes come in 32 Notes-coloured flavours that hold centred text, swap outlines from the Shape menu and export to HTML as real vectors
- **easels:** Pick a custom text size for shapes and stickies too, not just text boxes
- **easels:** Click a selected connector to label it, and VoiceOver can add the next sticky or shape
- **easels:** Copy, cut and paste any mix of Easel objects with their styles and pictures, between Easels and Profiles, landing right under your pointer
- **easels:** Right-click anything on an Easel for a Notes-style menu with paste here, order, align, tidy up, group, lock and copy as image
- **easels:** Copy as Image on a selection says Copied Image, just like the page menu does
- **easels:** Command-D duplicates the table rows or columns you've selected instead of the whole table
- **easels:** Press backtick for a code block with Notes' syntax colours in 39 languages, smart Tab and Return, a language menu, one-click Copy and ⌘Return for the next one, previewed at its real size as you place it
- **easels:** MP4 and MOV videos land as a poster with a play button and play right on the Easel with the native controls, and a picture dropped on a selected image swaps in place
- **easels:** New doodles pick up the colour and width you last gave a drawing, and long strokes stay quick by repainting only their newest bit
- **easels:** Copy Link to Object hands out a link that opens the Easel with that object picked and glided into view
- **easels:** ⌘F reaches table cells too, and replacing in a table rewrites its cells in one go and refits the rows
- **easels:** Easel History keeps a snapshot every few minutes while you work, previews each one and restores it as a single undo
- **easels:** Highlighter, washi tape and the eraser are switched on, with an eraser cursor that matches its reach
- **easels:** The selection toolbar now restyles anything with one colour and style picker, swaps shapes, flips, rotates and copies as image, and table alignment and colour show what the cells really use
- **easels:** A countdown timer lives in the Easel's corner, up to 99:59, with arrow-key minutes, +1 min mid-run and a gentle shake when time's up
- **notes:** Easel blocks get a + button and ⌘/ for adding stickies, shapes and friends, keep the selection toolbar inside the block as the note scrolls, and stay hands-off in locked notes
- **easels:** ⇧⌘E exports just the picked objects as an image, PDF or HTML, and stickies head out as a tidy CSV from a selection or the whole Easel
- **easels:** Press E for a wheel of stamps at your pointer, with recents, every emoji and a drawer of icons; click to stamp, hold to grow, ⌘Return stamps the selection
- **easels:** New objects pop in, deleted ones fade away, copies glide out of their source and Align or Tidy up slides everything into place
- **easels:** Start a board from seven templates, from Kanban to Mind Map, picked from the toolbar, the ••• menu or right on an empty Easel
- **easels:** An empty Easel now teaches the keys with clickable chips that fade away once the first object lands, plus a one-time tip for making the next sticky or shape
- **easels:** Icon stamps take any colour from the style button or the right-click colours, palette shades included
- **easels:** An empty Easel is one tidy welcome now, with the words, key chips and template cards laid out together, and a picked template pops right in
- **easels:** Mind maps grow on Easels with ⌘Return for a child, ⇧⌘Return for a sibling, Tab to move nodes, + buttons, drag-to-reparent and collapsible branches
- **easels:** The Mind Map template starts as a real mind map, branches and all, ready for ⌘Return
- **easels:** Type straight into sticky notes, which grow as you write, keep their padding and stay in proportion when scaled up
- **easels:** Easels get pages, with a Notes-style page switcher, Page Up and Page Down to flip, Move to Page, page links, per-page find and exports that know their pages

### Fixed

- **notes:** YouTube, Vimeo, Loom and Spotify links given to a video or audio block play as an embed, and a stuck one offers Play here
- **notes:** Pasted links with no file extension, like Google's Copy Image Address, offer Image, Video, Audio or PDF once the server says what they are
- **easels:** The Custom text size field sticks around until you've typed your size instead of risking a vanishing act
- **easels:** The selection toolbar steps aside for selections bigger than the view, keeps − and + while you type and shows up for VoiceOver with the canvas
- **easels:** Table moves hop over merged cells instead of splitting them, big spreadsheet pastes say what they left out, and mail laid out in tables pastes as text
- **easels:** Table edits stand down quietly once their Easel is deleted instead of raising an error mid-drag
- **easels:** Accented first letters start a table cell properly, and table controls never leave smudges behind at low zoom
- **easels:** Coloured table cells in HTML exports follow the reader's light or dark mode like every other Easel colour
- **easels:** Aligning text from the selection toolbar works while you're typing in a table cell, not just on selected cells
- **easels:** Giant or tangled Mermaid pastes get a quick polite no instead of a spinning beach ball, and pasted arrows arrive already bent around their shapes
- **easels:** A Mermaid diagram too big to paste says so instead of landing as a wall of text, the Add sheet keeps up as you type, and ER entity names come out bold
- **easels:** Elbows leave rotated shapes and pinned spots cleanly, loops on one object hop a corner, freed curves keep their shape, whole diagrams drag smoothly and connectors share the colour picker's line styles
- **easels:** Scaled text keeps every run on a whole point from 8 to 400 and stays inside the capture editor's board, where double-clicking a side no longer widens text past it
- **easels:** A link badge only opens real web addresses, never ones carrying a password or missing a host
- **easels:** Emoji shortcodes only turn into emoji as you type them, never when pasted, dropped or dictated, and never inside inline code
- **easels:** The right-click menu's link, alignment, colour and Auto Width rows always act on the objects you right-clicked
- **easels:** Duplicating a whole Easel keeps its arrows hooked up and its stickers stuck on
- **easels:** Highlights and washi tape stay stuck on top of their object when it changes layers, and tag along when it's duplicated or copied
- **easels:** Cancelling an Option-drag puts the selection back on the original, and picking a group never sweeps up its locked members
- **notes:** ⌘G and friends inside an Easel block now belong to the Easel instead of the note around it
- **easels:** Doodles drawn before smoothing keep their sharp corners on the board and in exports, and exported highlights keep their glow even outside the page
- **easels:** Easel Replace only changes the match you can see, steps past locked objects and card titles, and says what Replace All skipped
- **easels:** Right-click a shape to switch its outline to any of the 32 shapes again in the new Notes-style menu
- **easels:** Adding a label to a connector is one undo step, even when you clicked a spot along it
- **easels:** Command-Return quick create plays by the shared shortcut rules and waits while you're still composing text
- **easels:** The connector tools draw real, snapping connectors as you drag instead of plain lines
- **easels:** Highlights keep their blend and opacity in a standalone SVG, with tests for taps, Shift lines, tape and curves
- **easels:** Tight crops zoom the right way, big GIFs play smoothly off the main thread, and crops tidy up after undo or a window hop
- **easels:** Pasting a hostile Mermaid diagram gets a polite no, the Add sheet reads and parses it once, and Command-Return adds from anywhere in it
- **easels:** Locked objects show a pointing hand on their lock badge, and the canvas menu says Paste when nothing has a spot to land
- **easels:** Escape or switching windows cancels a tool dragged off the toolbar, and a click puts stickies, sections and text right where you pressed
- **easels:** Older QuickTime and AV1 movies import again, and GIFs stay sharp when cropped or zoomed in
- **easels:** Sidebar previews and note exports frame what you actually see, rotated, with thick arrows and labels, and never peek inside closed sections
- **easels:** Connector labels open right where you double-clicked, connectors you draw take the colour you picked and end where you let go
- **easels:** The capture editor keeps its toolbar, menus and paste to things a screenshot can hold, and the colour well follows what you pick
- **easels:** Stickies exported as CSV can't sneak formulas into a spreadsheet, the timer says time's up just once and blinks while paused
- **easels:** Easel animations stop cleanly when a board moves windows or hides, fading objects never linger, and huge selections only animate what you can see
- **easels:** Undo, Redo, shape cells, template cards and the empty Easel's chips show Parc's own tooltips with keycaps for their shortcuts
- **easels:** Easels with a tangled mind map still open, and pasting part of a map never leaves a loose branch behind
- **easels:** Stamps you're holding never get lost, the stamp wheel tidies itself away with its window, and ⌘Return stamping plays by the shared shortcut rules
- **easels:** Easels with scrambled stacking order open safely, so adding a sticky or table on top never crashes
- **easels:** Easel History stays put if its Easel closes underneath it, instead of crashing on Restore
- **easels:** Giant boards export and copy as a sensibly sized image instead of gigapixels that stall Parc
- **easels:** Big stickies keep roomy margins that grow with them
- **easels:** Timer, web card and in-note Easel controls show Parc's own tooltips
- **easels:** Pasting a table cell stuffed with blank lines no longer stalls Parc
- **easels:** Pasting a novel into an image's alt text trims it instantly instead of freezing
- **easels:** Image exports and Copy as Image hug your board instead of dragging along empty canvas
- **easels:** The emoji list stays fully visible in Easels inside notes
- **easels:** Easel menus, tooltips and VoiceOver speak with one voice now, from colors and connectors to ellipses and stamps
- **easels:** Undo says Add connector and Add ellipse, and Mermaid hints talk about shapes instead of nodes
- **easels:** VoiceOver calls the timer a timer and reads running, paused or time’s up as its value
- **easels:** Deleting a page with one thing on it reads right, and says Undo brings it all back
- **easels:** VoiceOver can't nudge a connector's ends while you're pinching to zoom, since the handles are hidden then
- **easels:** Colour swatches in Easel style and table colour menus show up reliably on every macOS version

### Faster

- **easels:** Link badges skip re-reading every object's address on each redraw, so busy Easels stay smooth
- **easels:** Boards full of sticky notes stay smooth because each paper is drawn once and reused, and see-through stickies keep their shadow outside the sheet
- **easels:** Big mind maps with lots of folded branches stay snappy while you work

## 2.14.0 (2026-11-21)

### New

- **notes:** Web links in notes open in a Peek, following your Settings → Links choices for other-site links and Shift-click
- **notes:** Captures can be sent to a new or recent note, landing as an image that remembers its page for Make Live
- **notes:** Put an Easel in a note with /easel or a pasted Easel link, and edit its live canvas right there at the width and height you drag
- **notes:** Put an Easel in a note with /easel or a pasted Easel link, and edit its live canvas right there at the width and height you drag
- **notes:** Captured images in notes show their page with a Snapshot label, and Make live shows the same region from the live page with Back to snapshot
- **notes:** Tab hops right over an Easel in a note until you click into it, so the keyboard never gets lost on the canvas
- **sidebar:** Hovering a note or Easel tab shows a preview card with a picture of the page or canvas, Copy Link and Open in Split View
- **notes:** Drag an Easel from the sidebar onto a note's text and it lands as an Easel block right where the drop line shows
- **easels:** Turn an Easel into vector SVG and a self-contained HTML page with its fonts, images, links and both light and dark ink
- **easels:** Give Easels the Notes page menu with Copy Link, Copy as Image, Image, HTML and PDF export, Show in Library, Duplicate and Delete
- **notes:** Webpages and live captures on an Easel inside a note are real live pages now, with Make live and Back to snapshot right there
- **capture:** The capture palette tidies up into a Notes-style menu with Easel and Note submenus, one highlight and search that finds every action and document
- **capture:** Capture mode gets a bar with Element, Region, Visible Area and Full Page a click or a letter away, plus a size readout and an accent outline, so Visible Area stops playing hide-and-seek
- **capture:** Frame in Portrait Mode opens right inside the capture palette, with picture tiles, a big live preview on the capture itself and an Apply button that only lights up when there's something to apply

### Fixed

- **notes:** Printing a note no longer crashes, and prints the same pages Export to PDF makes
- **notes:** Adding a PDF to a note no longer crashes Parc
- **notes:** Note previews show spaces, ampersands and other characters instead of codes like &#32;
- **notes:** Pasting into a block's link field fills the field, pasted image, video and audio links can become media blocks, and pasting a link onto an empty media block fills it
- **notes:** YouTube and other player embeds in notes play instead of showing Error 153
- **notes:** A link copied from any app or web page pastes as a link, not plain text
- **notes:** Bookmarks stop refetching in a loop, web videos and sounds that fail to load offer Try again, and empty media blocks take dropped links and images
- **notes:** Deleting a property while its value is being typed no longer beeps or writes that text into another property
- **notes:** Images dragged from a web page into a note land as images instead of links
- **notes:** Return in a property's menu now does the row picked with the arrow keys, such as Delete Property or a type
- **split:** New notes and Easels, and notes or Easels opened from a split pane's address bar, now open in that pane instead of a new tab
- **notes:** Note previews skip synced-block markers and other hidden comments and show the note's words
- **notes:** Notes without their own icon show the Library's note mark in the sidebar, tab switcher, command bar and note links
- **notes:** The @, slash, [[ and emoji menus come back when you edit after the trigger again, such as backspacing to a bare @, while Escape keeps them closed for that trigger
- **notes:** Reminders play the notification sound when they go off
- **notes:** Date and reminder suggestions show their weekday and date, times without am or pm offer both readings, and passed reminders say Already passed
- **notes:** Markdown exports and Copy as Markdown write plain, portable Markdown, with synced blocks as their content and no hidden Parc markup
- **easels:** Drawing in an Easel no longer crashes Parc when you finish a stroke
- **easels:** Easels opened in a split pane showing a page sit on top of it like notes, so Back returns to the page as it was and Forward to the Easel
- **notes:** The date picker's reminder line and reminder notifications name days by weekday and date, and notifications say Today or Tomorrow as of when they ring
- **easels:** Easels wear the Notes look, with the Space theme behind Notes paper and ink, text, selection and controls that stay readable in dark mode
- **easels:** Easel web items wear the Notes embed header, with a clear Snapshot or Live label, a Make live button that is always there for captured regions, and Back to snapshot
- **navigation:** Notes and Easels opened over a page stack like web history, so Back walks through every one to the page and Forward retraces them
- **capture:** Selecting a capture region at the window's edges no longer moves the window, and the hidden sidebar stays put while capturing
- **easels:** Live element captures show just the captured element, never the whole page, and go back to the snapshot with a clear note when the page can't line up
- **easels:** Easels without their own icon show the Library's Easel mark in the sidebar, tab switcher, command bar, history and note blocks
- **easels:** Easel text with damaged font settings no longer crashes Parc when it is shown
- **easels:** One damaged Easel file no longer hides every other Easel from the Library, pickers and command bar
- **easels:** Easels with repeated object IDs open with those objects re-IDed, and the canvas, live pages and drag guides no longer crash on them
- **easels:** Live captures from sites that scroll inside a panel now scroll that panel back into place too, instead of giving up and staying a snapshot
- **notes:** Live captures in notes line up regions from sites that scroll inside a panel, just like Easels do
- **easels:** Show in Library on an Easel or note now opens Easels & Notes with that card selected, scrolled into view and searched clear
- **capture:** The Portrait Frame page answers Return from its color slider, keeps Cancel and Apply in view in narrow split panes and says Back like every other back button
- **capture:** The capture palette opens with Save to Library highlighted again, so one Return right after a capture saves it
- **navigation:** Pages you open after a note or Easel now join the same history, so Back and Forward weave through pages and documents in the order you went
- **notes:** Closing note Find, media zoom or the PDF viewer only hands focus back to a view that is still visible in that window

## 2.13.0 (2026-11-20)

### New

- **notes:** Teach equation macros TeX's sneakier tricks: delimited \def parameters, \expandafter, \noexpand, \csname, and cells that keep their definitions to themselves
- **notes:** Teach tabs to remember a note opened over a page, so Back and Forward can hop between them
- **notes:** Chemistry speaks the rest of mhchem: every \bond flavour, radical dots, italic variables, upright braces, and \pu with comma decimals, written-out powers of ten and ranges
- **notes:** Emoji and CJK in equation scripts borrow a properly shrunk system font instead of wobbling off the baseline
- **notes:** Open a page's Markdown links right in its tab, with Back returning to the page just as you left it and Forward hopping back to the note
- **notes:** Live embeds in notes take your very first click and let scrolls spill into the note once the page runs out of road
- **notes:** Equations number themselves across the whole note, and \label, \eqref and \ref link up so a click jumps to the right one
- **notes:** Escape hops out of a live embed back to your note, and retired notes now tuck their pages in for good
- **notes:** Swipe forward from a page right into the note you just left, and ⌘-click Forward to pop that note open in a background tab
- **notes:** A live embed in a split pane you weren't using still takes your very first click
- **notes:** Swipe back off a note to its page, hold Back or Forward to see the note in the list, and ⌘-click Back to fork the page behind it into a new tab
- **notes:** Nest blocks under any text, like Notion, saved as tidy ::: indent fences that read fine on GitHub
- **notes:** Equations learn KaTeX's size dial, raisebox, smash, substack, genfrac, colour boxes, clickable \href and \url links and over/undergroups, and mhchem's dashed bonds finally draw like KaTeX instead of a dash pileup
- **notes:** Equations learn alignat, multline, subarray, dcases, darray, starred matrices and dashed array lines, numbering right along with the rest of the note
- **notes:** Commutative diagrams arrive: \begin{CD} draws @>>>, @<<<, @VVV, @AAA, @= and @| arrows with labels riding above, below and beside them
- **notes:** Equations pick up the rest of KaTeX's symbol zoo, mathtools colons, \char, \verb, \mathchoice, \vcenter, \pmb, the TeX logos and the dd/cc/sp units nobody remembers
- **notes:** Equations stretch \utilde, \Overrightarrow, harpoons and line segments over anything, draw \phase and actuarial \angl, and two-headed and long-equals x-arrows finally grow with their labels
- **notes:** \text grows up with accents, nested bold and italics, colours, sizes, links, \(…\) math and proper curly quotes and dashes
- **notes:** Physicists get \bra, \ket, \braket and friends, and set-builder \set and \Set put the bar where it belongs
- **notes:** Mermaid joins the language list with highlighting, remembers Code, Preview or Split in invisible metadata, and HTML exports can carry the drawings in light and dark
- **notes:** Heading 4 and Toggle heading 4 join the slash menu (/h4, /####) and every Turn into list, and the table of contents now lists H4s too
- **notes:** Typing ->, <-, <->, =>, >=, <= or -- turns into proper arrows, comparisons and an em dash, never in code or equations, and one ⌘Z brings back exactly what you typed
- **notes:** Photo credits ride along with images and covers, saved quietly in the note and shown with links in HTML and PDF exports
- **notes:** Notes remember inline PDFs with their size, alignment and caption, plain-text notes keep them as file references, and HTML exports show them in place
- **notes:** Select a few blocks and Turn into 2 to 5 columns lays them out side by side, from the block menu, the format bar or the keyboard
- **notes:** Custom emoji get a Markdown home, so :name: shortcodes read, write and export to HTML as little images while escaped ones stay text
- **notes:** Notes read and write synced blocks as invisible comment markers, so the file still reads like plain Markdown on GitHub
- **notes:** Images remember a crop and a shape in the note's Markdown, and HTML exports draw both
- **notes:** Mermaid code blocks draw live diagrams with Code, Preview and Split views, crossfading between them and keeping the last good drawing when the diagram breaks
- **notes:** The block menu gets a View submenu for Mermaid diagrams, so Code, Preview and Split are a right-click away
- **notes:** Date mentions take ranges like @Jan 3 → Jan 5 or @Jan 3 - 5, remember their end, reminder lead, time zone and format in the file, and Jan 3 typed in November means the coming one
- **notes:** HTML exports embed Mermaid diagrams as SVG for light and dark, and PDF exports wait for the drawings and print them as crisp vectors
- **notes:** Image blocks and the cover picker get an Unsplash tab to search free photos, save the pick into Attachments and credit the photographer under it
- **notes:** Notes keep a live index of every note that links or mentions them, and renaming or moving a note rewrites those links so nothing breaks
- **notes:** Tables keep merged cells and cell colours in the file, export them as real colspan and rowspan, and read merges back from pasted HTML
- **notes:** Notes show how many notes link to them under the title, with a popup or an inline list of each linking note and the sentence around the link, and the page menu picks Expanded, Show in Popup or Off
- **notes:** PDFs read right in the note, from /pdf, a dropped file or a pasted link, with scrolling pages, a page indicator, zoom, full screen, download, resizing and password unlock
- **notes:** The date picker gets an End date toggle with a range band on the calendar, Format and Time zone pages, a full Remind list, reminders turn red the day they're due, and relative dates redraw themselves as days pass
- **notes:** Make your own emoji with the picker's plus button, then use them inline with :name:, as page and callout icons, and rename or delete them, all saved in the notes folder
- **notes:** Synced blocks stay live across notes: edit any copy and the original and every other copy follow, undo works from either side, and copies find originals that moved
- **notes:** Crop images with a draggable frame, clip them to circles, hearts and six other shapes, and give them alt text with an ALT badge, all from the image's ••• menu
- **notes:** /bread adds a breadcrumb that shows where the note lives, keeps up when it moves or gets renamed, and opens any folder on the path in Easels & Notes
- **notes:** Merge and unmerge table cells and colour them from a cell's ••• menu, fill down with ⌘D and right with ⌘R, and drag a table's corner to add or drop rows and columns
- **notes:** Button blocks: /button makes a pill that adds blocks below, above, at the top or bottom of the note, asks first or opens a note or link, saved as GitHub-friendly details and undone one press at a time
- **notes:** The button's gear opens its editor: name and emoji, a list of actions to add, reorder or delete, and the blocks it inserts edited right there with the full note editor, every change saved as you go and undone as one step
- **notes:** Make synced blocks from the block menu or /synced, copy them anywhere, and see where else they live from a border that lights up while you edit
- **notes:** Synced copies stay live while the original's note is closed, which quietly opens in the background and lets go when you're done
- **notes:** Copies in closed notes catch up a couple of seconds after the original changes, so their files read right on GitHub too
- **notes:** Releases carry the Unsplash key from the packager's keychain, so the Unsplash tab works without a key in the repo

### Fixed

- **notes:** Read-only locked notes stop dangling a dud Unlock button, ⌘↩ opens page links even when locked, and Redo finally admits it's ⇧⌘Z
- **notes:** Underscores and stars right after an emoji italicize again instead of mistaking half an emoji for a word
- **notes:** Selections respect their field, IME never eats keys, and Replace All stops fibbing about its count
- **notes:** Moving blocks to another note is one honest action now: undo from either note puts them back, and unrelated undos stop raiding the other note
- **notes:** Tab icons notice swapped pictures and closed notes, and imports chase notes that wander off mid-copy
- **notes:** Typing over a vanished block selection lands in the nearest text instead of the void
- **notes:** Note links now say exactly how they were clicked, and target=_blank ones skip the raw-text detour
- **notes:** A note that moves mid-import takes its picture along instead of leaving a twin in the old Attachments
- **notes:** Moved blocks stay findable even after the other note closes and reopens, and a redo that can't reach it leaves them home
- **notes:** Keep the emoji grid's last column out from under the scroller, with matching margins on both sides
- **notes:** Exported equations keep counting across the note, and their references link straight to the labelled one, while open drafts renumber everything live
- **notes:** Undo a move in one note and Redo works from the other, since both notes now share the same step instead of one starting fresh
- **notes:** Tabs forked from the page behind a note now line up after their source, and picking from the note's history list refreshes the page like the usual list
- **notes:** Keep the Mermaid view mode beside the block model so every windowless notes test builds again
- **notes:** Drop the duplicate Mermaid view enum so the block model's copy is the only one
- **notes:** Rename the Unsplash thumbnail's picture so it stops clashing with the button's own image
- **notes:** Spell out the Unsplash tile's photographer link so it builds cleanly
- **notes:** Notes renamed or moved in Finder keep their backlinks and links to them follow, and a rename never makes the backlink count blink
- **notes:** Wrap the synced-note search in parentheses so the guard parses
- **notes:** Keep the custom emoji picker pieces self-contained so the picker's windowless checks build them too
- **notes:** The crop bar swaps to icons cleanly on narrow pages, and VoiceOver's grow and shrink keep the crop inside the picture
- **notes:** Button heights measure off the main actor so the canvas estimate compiles
- **notes:** Synced blocks dropped from another note stay live, and dropping one inside another unwraps it instead of nesting
- **notes:** Editing a button's blocks never touches the note's date reminders, and closing the editor stops its timers
- **notes:** Give the synced block's header controls their own property names so they stop colliding with the button's
- **notes:** Backspace at the start of a synced block selects it instead of spilling its lines out, and joins lines inside like anywhere else
- **notes:** Clearing out a synced block leaves one empty line to type in, everywhere it's synced and in the same undo step
- **notes:** Look for the Original Again really searches again, even in notes it already checked
- **notes:** Parc claims Markdown and text files as a default editor, so they open in Parc unless you've picked another app
- **notes:** Mermaid treats Windows line endings like any other, and the button, emoji, image menu and diagram test suites build and pass again

### Faster

- **notes:** Typing in notes without synced blocks skips the synced bookkeeping, and the border stops rescanning the page on every keystroke

## 2.12.0 (2026-11-20)

### New

- **notes:** Pick where new notes live in Settings, like downloads
- **notes:** Put Parc on Finder's Open With list for Markdown and text files, so they open as notes you can actually edit
- **notes:** Draw dividers, and a table of contents that keeps up with your headings and waves at the one you jump to
- **notes:** Give every Notes menu a real Parc card that pops open, glides its highlight and tucks itself away
- **notes:** Hover any block to find a + and a grip waiting in the margin, ready to add a line or pick the block up
- **notes:** Hand Notes squishy toolbar buttons, chips, Parc keycaps and a search field that filters menus as you type
- **notes:** Typeset equations natively in STIX Two Math, with brackets that grow, limits that stack and matrices that line up
- **notes:** Pick emoji from a bouncy grid with search, skin tones, recents and a Random button for the indecisive
- **notes:** Give code blocks live colours, a language picker, Wrap and a Copy that says thanks, and let equations and leftover Markdown look the part
- **notes:** Label arrows with \xrightarrow, cross things out with \cancel and write \R for the reals in equations
- **notes:** Colour code blocks by kind in Parc's palette and keep inline code sitting on the same line as its words
- **notes:** Find and replace inside a note, with every match glowing, ⌘G to hop between them and Replace All as one tidy undo
- **notes:** Lay pages out like a proper editor, with columns you can drag wider, callouts that hug their kids and blocks that glide into place
- **notes:** Give equation scripts their proper small-print glyphs and flatten accents on tall letters instead of just shrinking everything
- **notes:** Teach equations your own \newcommand shortcuts and write chemistry with \ce and \pu, arrows, charges, isotopes and all
- **notes:** Drag a selection across blocks, rubber-band whole blocks from the margin and arrow between them like they were one page
- **notes:** Number display equations with \tag, \tag* and auto-numbered align, gather and equation, tags hugging the right edge
- **notes:** Find notes in the command bar by what's written inside them, not just their names
- **notes:** Click a block's grip for a searchable menu of everything it can do, or drag it anywhere, even into columns, with the page scrolling along
- **notes:** Drop Markdown and text files on the sidebar to open them as notes
- **notes:** Type like it's Notion, with Markdown shortcuts that become blocks, rounded code and highlight pills, live inline math, mention pills and to-dos that pop when you tick them
- **notes:** Dress pages up with a cover, a big emoji icon, a title that renames the file, properties and a time machine for older versions
- **notes:** Let code blocks say "Write some code" when empty, keep Markdown shortcuts out of code, and tuck an empty caption away when you leave it
- **notes:** Add tables you can Tab through, drag wider, shuffle by their grips and fill straight from a spreadsheet paste
- **notes:** Highlight some text and a toolbar floats up to bold it, link it, paint it or turn it into a heading, plus a hover card for every link
- **notes:** Copy, cut and paste in text blocks through the Notes clipboard, so blocks, links and Markdown travel intact
- **notes:** Give properties tidy dates and tags that only show their little x on hover, and let the find bar's chevron flip without fighting the press bounce
- **notes:** Tuck fonts, small text, full width, lock, copy, export, history and the trash into a page menu that counts your words
- **notes:** Copy notes as rich text that Mail, Pages and Docs understand, and paste web pages and docs back in as real blocks
- **notes:** Type / for every block with a peek at each, @ for notes, dates and reminders, and :smile: for emoji
- **notes:** Click a date or reminder in your text to change it in the date picker
- **notes:** Give notes real images, videos, sounds, files, bookmarks and note links that shimmer in, resize on a spring and zoom when you double-click
- **notes:** Pop the math editor open the moment / adds an inline equation, and let a click back in the text close the emoji picker
- **notes:** List your Notes folder in the Library with emoji, a peek at the text and when you last touched it, plus Show in Finder and Move to Trash
- **notes:** Let the command bar find words inside notes you have open, even ones saved outside your Notes folder
- **notes:** Pin a page menu to every note's top corner, let Print and every Find command reach notes, and keep ⌘⇧H on your last colour instead of a surprise Heading 1
- **notes:** Click a note reminder and Parc opens that note for you, in a regular window and never a private one
- **notes:** Copy a link to any block with ⌃⌘L, peek at media with Space, and drag callouts around with their real boxes on
- **notes:** Drag Markdown or text files onto the sidebar and the insertion line shows where they'll land, then they open right there
- **notes:** Open a note link with a #heading or block anchor from Finder, a page, a reminder or another note and Parc scrolls straight to that spot
- **notes:** Open the find bar just under the page menu button so the two stop playing Tetris in the corner
- **notes:** Give GitHub and Obsidian alert callouts their proper emoji and colour without scribbling defaults into the file
- **notes:** Keep your selection a soft Parc purple when the window steps away, and teach text to line up left, centre or right on its own
- **notes:** Let code sit snug in its box, with language, caption, wrap and copy floating in only when you hover
- **notes:** Find now lights up titles, captions and table cells, the title tucks in under its icon, rename slip-ups show right below it, and → steps into an equation to edit it
- **notes:** Lift dragged blocks as a crisp full-size ghost on Retina screens instead of a shrunken copy in the corner
- **notes:** Paint tip, warning, caution and friends' callout boxes in their alert colours unless you pick one yourself
- **notes:** Give Small Text, Full Width and Lock Page real little switches in the page menu so you can see what's on at a glance
- **notes:** Stretch tables to the same right edge as everything else, with the add-column bar peeking in from outside on hover
- **notes:** Embeds now hold a real live page right in your note, sign-ins and all, with a tidy header and a handle to make it taller
- **notes:** Give live embeds a Caption button in their header, so a page can still get a little footnote
- **notes:** Export to PDF prints the real page with its cover, icon, colours and page breaks between blocks, and HTML exports typeset your equations

### Fixed

- **notes:** Keep typed code in Space Mono with its tab stops, let Cmd-Return leave a code block, and tint the exact TeX typo
- **notes:** Hand a block its new text before measuring it, so a merged line gets the room it needs right away
- **notes:** Stop reminders from nagging about notes you already sent to the Trash
- **notes:** Open a page's Markdown links straight into a note tab, leaving the page and its back button right where you left them
- **notes:** Keep property tags, page menus, find and cover pickers readable the moment your Space flips between light and dark
- **notes:** Let the Library and command bar notice when the note index wakes up, so your first body search actually finds things
- **notes:** Keep big tables from crashing when undo or a delete pulls a row out from under the cursor, and keep tab-indented code in one cell
- **notes:** Make drops beside a block and links pasted over a selection undo in one go, and refuse to open javascript, vbscript and data links
- **notes:** Guess an embed's height from its real size so the page stops jumping when one scrolls in, and retire the old bookmark-style embed
- **notes:** Drop in a giant video or an iCloud file and keep typing, it shimmers in while the copy happens behind the scenes
- **notes:** Let ⌘F, ⌘G and friends search the live page you're clicked into instead of the note wrapped around it
- **notes:** Make menu picks swallow the whole query, close on a click away, and let reminders follow notes through renames, moves and the trash
- **notes:** Copying a note as rich text never phones home for pictures, it just writes their alt text instead
- **notes:** Turn away javascript: and data: links, stop the fading toolbar from formatting old selections, and tidy up after image menus and audio players
- **notes:** Stop /tog from dragging Link to note along, so the slash menu only shows near-misses when nothing really matches
- **notes:** Tuck blocks inside a GitHub-style tip or warning in past its icon, even when the icon comes free with the alert
- **notes:** Give every note one tab and one save brain, however you spell its path, so Plan.md, plan.md and that symlinked folder stop fighting over the same file
- **notes:** Show hand-written GitHub NOTE alerts in blue with their ℹ️, while Parc's own plain callouts stay plain after a reload
- **notes:** Print the real page with its cover, colours and all, and show rename slip-ups right under the title where they stick around long enough to read
- **notes:** Notes never save a placeholder mid-copy anymore, so quitting early still leaves a link that works, and Replace and cover uploads copy in the background too
- **notes:** Hang on to unsaved words when a file vanishes, moves or won't save, answer other apps' save requests without stalling, and spot renamed folders with dots in their names
- **notes:** Stop calling every note an Easel in the sidebar's address pill, so Plan.md finally gets to be Plan.md
- **notes:** Give note tabs their own emoji instead of a generic page glyph, in the sidebar, Favorites, the switcher and the command bar
- **notes:** Make Put It Back actually put a vanished note back, folders and all, even when nothing was unsaved, and say so when something else took its spot
- **notes:** Scan big notes folders in the background, so the Library and command bar show names right away and stop freezing while 20,000 files get a once-over
- **notes:** Saving a note never quietly changes what it means, so a divider up top stays a divider, a [x] before a line break stays text, and stray HTML under a link definition, callout title or empty tag stays exactly where you left it
- **notes:** Polish the Notes wording so menus, toasts and errors say exactly what happens, and save block downloads to your Space's download folder
- **notes:** Hook the Put It Back button up to the thing that actually puts it back
- **notes:** Curl the last stray apostrophes in media and cover errors, and name the conflict undo after the button you pressed

## 2.11.0 (2026-11-18)

### New

- **files:** Put Parc on Finder's Open With list for the PDFs, pictures, text, music and videos it can already show, and name a local file's tab after the file while it loads
- **history:** Find pages you've visited in Parc straight from Spotlight, like Safari, with deleted history leaving Spotlight too

## 2.10.2 (2026-11-18)

### Fixed

- **splits:** Teach Split This Pane to start a Split View on a lone page instead of just shrugging
- **peek:** Let Shift-click Peek catch pages that sites pop open themselves, so dashboard tiles stop sneaking off into new windows
- **peek:** Round up the Shift-click strays, so PDF links, search forms and pages sites open themselves land in a Peek, or the Peek you're in, instead of new windows
- **peek:** Let Shift-clicked forms keep their paperwork, so sign-ins and app launches that post data open in a Peek, or the Peek you're in, with everything they sent

## 2.10.1 (2026-11-18)

### Fixed

- **settings:** Sweep the last Google-only and do-nothing rows out of More Settings, and teach Reset to keep its settings report to itself
- **settings:** Stop wearing Chrome's brand badge, show Enhanced protection only to people already on it, hush its warning-page upsell, and tuck away Live Caption, which never heard a word
- **privacy:** Stop sharing Chrome's install-tracking drawer, and take the do-nothing Live Caption switches out of the media popup and picture in picture

## 2.10.0 (2026-11-18)

### New

- **splits:** Give split panes bunk beds, stacking a new page below or beside any pane from its menu or Control-Shift-Backslash
- **splits:** Let a tab or link dropped near a pane's top or bottom edge, or its sides in a top-and-bottom split, bunk right there with it while the panes scoot over to save its seat

### Fixed

- **media:** Let videos and calls keep their seat while half the window still peeks out, and hop into picture in picture once another app or Parc window swallows the rest, even if it creeps over later
- **media:** Let videos in a Parc window that never had focus stay put while you can plainly see them, instead of bolting into picture in picture the moment they start
- **settings:** Give More Settings a spring clean, tucking away the switches that do nothing in Parc or only work with a Google account
- **branding:** Put Parc's P on every Chromium page Parc opens, dark mode included, so Settings, its About page and the version page stop moonlighting as Chromium
- **settings:** Make a cancelled Restart truly stand down, so your next Quit just quits instead of sneaking Parc back open
- **splits:** Let the divider between top and bottom panes snap to the middle from either direction, and only when you ease into it, instead of grabbing everything from above
- **splits:** Squeeze split panes into a cramped window instead of shoving the end ones off the page, with drop previews and drag cards that match where a new pane really lands
- **splits:** Teach drop previews some patience, so a tab or link flying across a split stops shoving panes around for every spot it passes on the way

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

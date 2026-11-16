import AppKit
import ImageIO
import UniformTypeIdentifiers
@MainActor private final class DownloadHoverWindow: NSWindow {
 var key = true
 var pointer = NSPoint.zero
 override var isKeyWindow: Bool { key }
 override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
}
@MainActor private final class CountingMediaSource: NSObject, NSCollectionViewDataSource {
 let base: NSCollectionViewDataSource
 var made = 0
 init(_ base: NSCollectionViewDataSource) { self.base = base }
 func numberOfSections(in collectionView: NSCollectionView) -> Int { base.numberOfSections?(in: collectionView) ?? 1 }
 func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { base.collectionView(collectionView, numberOfItemsInSection: section) }
 func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
  made += 1; return base.collectionView(collectionView, itemForRepresentedObjectAt: indexPath)
 }
}
private final class LiveCloud: ExternalMediaCloudObservation, @unchecked Sendable {
 private let lock = NSLock()
 private var evicted = Set<String>(), handler: (@Sendable (Set<String>) -> Void)?
 var source: ExternalMediaCloud {
  ExternalMediaCloud(isSynced: { _ in true }, isLocal: { [self] path, flags in flags & UInt32(SF_DATALESS) == 0 && !lock.withLock { evicted.contains(path) } },
   observe: { [self] report in lock.withLock { handler = report }; return self })
 }
 func present(_ paths: Set<String>) {}
 func evict(_ path: String) { lock.withLock { _ = evicted.insert(path) }; lock.withLock { handler }?([path]) }
}
@main @MainActor struct ViewCheck {
 static var count=0
 static func expect(_ c: @autoclosure () -> Bool, _ s: String) {count += 1; precondition(c(),s)}
 static func main() { exitOnFailure(runChecks) }
 static func runChecks() throws {
  _ = NSApplication.shared
  NSApp.setActivationPolicy(.prohibited)
  SystemOverrides.install()
  expect(LibraryArtwork.directory==Bundle.main.resourceURL?.appendingPathComponent("Library",isDirectory:true) && LibraryArtwork.emptyFavicon != nil,"the artwork loads from the bundle's Library resources")
  let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
  defer {try? FileManager.default.removeItem(at:directory)}
  let store=try BrowserStore(directory:directory); let profile=store.state.profiles[0].id
  if Bundle.main.object(forInfoDictionaryKey:"ParcRowsComponent") as? Bool == true {
   let root=LayoutView(frame:NSRect(x:0,y:0,width:800,height:450))
   let owner=NSWindow(contentRect:root.frame,styleMask:[.titled,.closable],backing:.buffered,defer:false)
   owner.isRestorable=false;owner.isReleasedWhenClosed=false;owner.contentView=root;owner.title="Downloads Rows Component — synthetic records"
   let source=store.independentEngineProfilePath(for:profile),now=Calendar.current.startOfDay(for:Date()).addingTimeInterval(12*3600).timeIntervalSince1970
   for (index,status) in ["completed","downloading","paused","failed","review"].enumerated() {
    store.recordDownload(["id":status,"profilePath":source,"name":["Mountain photograph.png","Project resources.zip","Reference video.mov","Document.pdf","Review required.zip"][index],"status":status=="review" ? "downloading":status,"available":true,"itemIdentity":status,"canOpen":status=="completed","canCopyFile":status=="completed","canReveal":status=="completed","canPause":status=="downloading","canResume":status=="paused","canRetry":status=="failed","canReview":status=="review","requiresReview":status=="review","statusText":status=="review" ? "Review required":"","sourceURL":"https://example.invalid/"+status,"startedAt":now-Double(index*60),"receivedBytes":5000,"totalBytes":10000])
   }
   SystemOverrides.reduceMotion=true
   for dark in [false,true] {
    let sample=DownloadLibraryView(store:store,ownerValid:{true})
    sample.frame=NSRect(x:dark ? 400:0,y:0,width:400,height:450)
    sample.appearance=NSAppearance(named:dark ? .darkAqua:.aqua);sample.palette=ThemeChromePalette(theme:SpaceTheme(),isDark:dark)
    sample.wantsLayer=true;sample.effectiveAppearance.performAsCurrentDrawingAppearance {sample.layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor}
    root.addSubview(sample);sample.layoutSubtreeIfNeeded()
    func descendants(_ view:NSView)->[NSView] { [view]+view.subviews.flatMap(descendants) }
    let table=descendants(sample).compactMap { $0 as? DownloadLibraryTable }.first!
    table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
   }
   let token=NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:owner,queue:.main) {_ in MainActor.assumeIsolated {NSApp.terminate(nil)}}
   defer {NotificationCenter.default.removeObserver(token)}
   NSApp.setActivationPolicy(.regular);owner.center();owner.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
   DispatchQueue.main.asyncAfter(deadline:.now()+90) {owner.close();NSApp.terminate(nil)}
   NSApp.run();return
  }
  if Bundle.main.object(forInfoDictionaryKey:"ParcSearchComponent") as? Bool == true {
   for owned in NSApp.windows { owned.orderOut(nil) }
   let root=LayoutView(frame:NSRect(x:0,y:0,width:640,height:400))
   let owner=NSWindow(contentRect:root.frame,styleMask:[.titled,.closable],backing:.buffered,defer:false)
   owner.isRestorable=false;owner.isReleasedWhenClosed=false;owner.contentView=root;owner.title="Downloads Search Component — synthetic records"
   SystemOverrides.reduceMotion=true
   for dark in [false,true] {
    let sample=DownloadLibraryView(store:store,ownerValid:{true})
    sample.frame=NSRect(x:dark ? 320:0,y:0,width:304,height:400)
    sample.appearance=NSAppearance(named:dark ? .darkAqua:.aqua)
    sample.palette=ThemeChromePalette(theme:SpaceTheme(),isDark:dark)
    sample.wantsLayer=true
    sample.effectiveAppearance.performAsCurrentDrawingAppearance { sample.layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor }
    root.addSubview(sample);sample.layoutSubtreeIfNeeded()
   }
   let closeToken=NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:owner,queue:.main) {_ in MainActor.assumeIsolated {NSApp.terminate(nil)}}
   defer {NotificationCenter.default.removeObserver(closeToken)}
   NSApp.setActivationPolicy(.regular);owner.center();owner.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
   DispatchQueue.main.asyncAfter(deadline:.now()+90) {owner.close();NSApp.terminate(nil)}
   NSApp.run();return
  }
  let path=store.independentEngineProfilePath(for:profile)
  func publish(_ id:String,_ incarnation:String,_ canOpen:Bool=true,_ name:String?=nil) {
   store.recordDownload(["id":id,"profilePath":path,"name":name ?? id,"status":"completed","available":true,"itemIdentity":incarnation,"canOpen":canOpen,"canRemove":true,"canCopyFile":true,"sourceURL":"https://example.invalid/"+id,"startedAt":1000])
  }
  publish("a","a1");publish("b","b1")
  let view=DownloadLibraryView(store:store,ownerValid:{true});view.frame=NSRect(x:0,y:0,width:400,height:600)
  let window=NSWindow(contentRect:view.frame,styleMask:[.titled],backing:.buffered,defer:false);window.contentView=view
  defer { view.invalidate();window.contentView=nil }
  func all(_ v:NSView)->[NSView] { [v]+v.subviews.flatMap(all) }
  let documentStore = try EaselEditorViewController.sharedStore(directory: store.easelsDirectory(for: profile))
  _ = try documentStore.create(title: "First disposable Easel")
  _ = try documentStore.create(title: "Second disposable Easel")
  let documents = DocumentsLibraryView(store: store, profileID: profile)
  documents.ownerValid = { true }
  documents.appearance = NSAppearance(named: .aqua)
  documents.palette = ThemeChromePalette(theme: SpaceTheme(), isDark: false)
  let documentWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 304, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
  documentWindow.contentView = documents
  func srgb(_ color: NSColor?) -> [CGFloat] {
   guard let c = color?.usingColorSpace(.sRGB) else { return [] }
   return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
  }
  for width: CGFloat in [304, 248] {
   documents.frame = NSRect(x: 0, y: 0, width: width, height: 600)
   documents.needsLayout = true; documents.layoutSubtreeIfNeeded()
   let grid = all(documents).compactMap { $0 as? NSTableView }.first!
   let row = grid.view(atColumn: 0, row: 0, makeIfNecessary: true)!
   row.layoutSubtreeIfNeeded(); row.displayIfNeeded()
   let cards = row.subviews.filter { $0.identifier?.rawValue.hasPrefix("document-") == true }.sorted { $0.frame.minX < $1.frame.minX }
   expect(cards.count == 2, "Both original documents appear in one grid row")
   expect(cards.allSatisfy { $0.frame.minX >= 0 && $0.frame.maxX <= row.bounds.width }, "Both document cards fit the actual Library pane")
   expect(cards[0].frame.maxX <= cards[1].frame.minX, "Document cards remain distinct pointer targets")
   expect(abs(grid.rowHeight - (cards[0].frame.height + 24)) < 0.01, "Grid row height \(grid.rowHeight) must fit card \(cards[0].frame.height) plus 12pt top and bottom at width \(width); row \(row.bounds), grid \(grid.bounds), column \(grid.rect(ofColumn: 0)), content \(grid.enclosingScrollView?.contentSize ?? .zero)")
   cards.forEach { $0.needsDisplay = true; $0.displayIfNeeded() }
   expect(cards.allSatisfy { card in
    guard let cg = card.layer?.backgroundColor, let color = NSColor(cgColor: cg) else { return false }
    let value = srgb(color)
    return value.count == 4 && value[0] > 0.99 && value[1] > 0.99 && value[2] > 0.99 && value[3] > 0.99
   }, "Document cards use opaque white tiles")
   let titles = cards.compactMap { card in card.subviews.compactMap { $0 as? NSTextField }.first }
   expect(titles.count == 2 && titles.allSatisfy { $0.font?.pointSize == 15 && $0.maximumNumberOfLines > 1 }, "Document titles wrap at 15pt")
   expect(titles.allSatisfy { srgb($0.textColor) == srgb(DocumentCardChrome.title(dark: false)) && srgb($0.textColor) != srgb(documents.palette?.foregroundPrimary) }, "Card titles use chrome ink, not Space foregroundPrimary")
   expect(documentWindow.makeFirstResponder(cards[0]) && documentWindow.firstResponder === cards[0], "Grid allows document card keyboard focus")
  }
  let create = all(documents).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "New Note" }!
  expect(create.title.isEmpty && abs(create.frame.width - 36) < 0.01 && abs(create.frame.height - 36) < 0.01, "New Note is a 36pt icon-only control")
  let notes = try NoteStore.sharedStore(directory: store.notesDirectory(for: profile))
  let createdNote = try notes.create()
  documents.needsLayout = true; documents.layoutSubtreeIfNeeded()
  let documentsGrid = all(documents).compactMap { $0 as? NSTableView }.first!
  expect(documentsGrid.numberOfRows == 2, "A newly persisted note appears in the documents grid")
  func documentTitles() -> [String] {
   (0..<documentsGrid.numberOfRows).flatMap { row -> [String] in
    guard let view = documentsGrid.view(atColumn: 0, row: row, makeIfNecessary: true) else { return [] }
    return view.subviews.filter { $0.identifier?.rawValue.hasPrefix("document-") == true }
     .sorted { $0.frame.minX < $1.frame.minX }
     .compactMap { card in card.subviews.compactMap { $0 as? NSTextField }.first?.stringValue }
   }
  }
  let visibleTitles = documentTitles()
  expect(visibleTitles.contains("Untitled Note"), "The new note's title is visible")
  expect(documentWindow.makeFirstResponder(documentsGrid.view(atColumn: 0, row: 0, makeIfNecessary: true)?.subviews.first) == true, "Document selection stays on a card")
  var body = createdNote.document.body
  body.text = "keystroke body that is not a card title"
  body.richText = .init(runs: [.init(location: 0, length: body.text.utf16.count,
    attributes: .init(font: .init(name: "Helvetica", size: 15), ink: "#252525FF"))])
  try createdNote.updateBody(body, replacing: createdNote.document.body)
  expect(documentsGrid.numberOfRows == 2 && documentTitles() == visibleTitles, "Body-only persist keeps visible document cards and titles")
  expect(documentWindow.firstResponder is NSView, "Body-only persist does not clear document card selection")
  try createdNote.updateTitle("Named Library Note", replacing: createdNote.document.title)
  expect(documentTitles().contains("Named Library Note"), "A note title change still refreshes the Documents catalog")
  let titlesAfterTitle = documentTitles()
  let rowsAfterTitle = documentsGrid.numberOfRows
  let selectedAfterTitle = documentWindow.firstResponder
  notes.changes.send()
  for _ in 0..<5 { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01)) }
  expect(documentsGrid.numberOfRows == rowsAfterTitle && documentTitles() == titlesAfterTitle,
         "Identical Documents catalog re-publish remains a fingerprint no-op")
  expect(documentWindow.firstResponder === selectedAfterTitle,
         "Identical Documents re-publish keeps card selection")
  documents.reload()
  expect(documentTitles() == titlesAfterTitle, "Explicit reload with an unchanged catalog stays a fingerprint no-op")
  let documentsSearch = all(documents).compactMap { $0 as? NSTextField }.first { $0.placeholderString == "Search Easels & Notes…" }!
  documentsSearch.stringValue = "no-match-filter"
  documents.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: documentsSearch))
  expect(documentTitles().isEmpty, "Search filter force-reloads past the Documents fingerprint")
  documentsSearch.stringValue = ""
  documents.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: documentsSearch))
  expect(documentTitles() == titlesAfterTitle, "Clearing Documents search force-reloads membership")
  documentWindow.contentView = nil
  let documentsFingerprintRoot = directory.appendingPathComponent("documents-fingerprint", isDirectory: true)
  let documentsFingerprintStore = try BrowserStore(directory: documentsFingerprintRoot)
  let documentsFingerprintProfile = documentsFingerprintStore.activeSpace.profileID
  let documentsFingerprintNotes = try NoteStore.sharedStore(
   directory: documentsFingerprintStore.notesDirectory(for: documentsFingerprintProfile), diskSaveDelay: 0)
  let documentsFingerprintNote = try documentsFingerprintNotes.create()
  try documentsFingerprintNote.updateTitle("Documents fingerprint note",
                                           replacing: documentsFingerprintNote.document.title)
  let documentsFingerprintView = DocumentsLibraryView(store: documentsFingerprintStore,
                                                      profileID: documentsFingerprintProfile)
  documentsFingerprintView.ownerValid = { true }
  documentsFingerprintView.frame = NSRect(x: 0, y: 0, width: 400, height: 600)
  let documentsFingerprintWindow = NSWindow(contentRect: documentsFingerprintView.frame, styleMask: [.titled],
                                            backing: .buffered, defer: false)
  documentsFingerprintWindow.isReleasedWhenClosed = false
  documentsFingerprintWindow.contentView = documentsFingerprintView
  documentsFingerprintView.layoutSubtreeIfNeeded()
  let documentsFingerprintGrid = all(documentsFingerprintView).compactMap { $0 as? NSTableView }.first!
  func documentsFingerprintTitles() -> [String] {
   (0..<documentsFingerprintGrid.numberOfRows).flatMap { row -> [String] in
    guard let view = documentsFingerprintGrid.view(atColumn: 0, row: row, makeIfNecessary: true) else { return [] }
    return view.subviews.filter { $0.identifier?.rawValue.hasPrefix("document-") == true }
     .sorted { $0.frame.minX < $1.frame.minX }
     .compactMap { card in card.subviews.compactMap { $0 as? NSTextField }.first?.stringValue }
   }
  }
  let documentsFingerprintBefore = documentsFingerprintTitles()
  expect(documentsFingerprintBefore == ["Documents fingerprint note"],
         "Isolated Documents fingerprint starts with the titled note")
  documentsFingerprintNotes.changes.send()
  for _ in 0..<5 { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01)) }
  expect(documentsFingerprintTitles() == documentsFingerprintBefore,
         "Identical isolated Documents re-publish remains a fingerprint no-op")
  var documentsFingerprintBody = documentsFingerprintNote.document.body
  documentsFingerprintBody.text = "documents-fingerprint-body-match"
  documentsFingerprintBody.richText = .init(runs: [.init(location: 0,
    length: documentsFingerprintBody.text.utf16.count,
    attributes: .init(font: .init(name: "Helvetica", size: 15), ink: "#252525FF"))])
  try documentsFingerprintNote.updateBody(documentsFingerprintBody,
                                          replacing: documentsFingerprintNote.document.body)
  for _ in 0..<5 { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01)) }
  let documentsFingerprintSearch = all(documentsFingerprintView).compactMap { $0 as? NSTextField }
   .first { $0.placeholderString == "Search Easels & Notes…" }!
  documentsFingerprintSearch.stringValue = "fingerprint-body-match"
  documentsFingerprintView.controlTextDidChange(
   Notification(name: NSControl.textDidChangeNotification, object: documentsFingerprintSearch))
  expect(documentsFingerprintTitles() == ["Documents fingerprint note"],
         "Body persist still reloads Documents-visible searchable text for filters")
  documentsFingerprintSearch.stringValue = "no-match-filter"
  documentsFingerprintView.controlTextDidChange(
   Notification(name: NSControl.textDidChangeNotification, object: documentsFingerprintSearch))
  expect(documentsFingerprintTitles().isEmpty, "Non-matching Documents search clears rows")
  try documentsFingerprintNote.updateTitle("Documents fingerprint renamed",
                                           replacing: documentsFingerprintNote.document.title)
  documentsFingerprintSearch.stringValue = ""
  documentsFingerprintView.controlTextDidChange(
   Notification(name: NSControl.textDidChangeNotification, object: documentsFingerprintSearch))
  expect(documentsFingerprintTitles() == ["Documents fingerprint renamed"],
         "A note title change still refreshes the isolated Documents catalog")
  documentsFingerprintWindow.contentView = nil
  documentsFingerprintWindow.close()
  SystemOverrides.reduceMotion = true
  let documentsLibrary = LibraryView(store: store, kind: .documents, profileID: profile)
  documentsLibrary.frame = NSRect(x: 0, y: 0, width: 416, height: 600)
  let documentsLibraryWindow = NSWindow(contentRect: documentsLibrary.frame, styleMask: [.titled], backing: .buffered, defer: false)
  documentsLibraryWindow.isReleasedWhenClosed = false
  documentsLibraryWindow.contentView = documentsLibrary
  documentsLibrary.layoutSubtreeIfNeeded()
  let hostedDocuments = all(documentsLibrary).compactMap { $0 as? DocumentsLibraryView }.first!
  let hostedGrid = all(hostedDocuments).compactMap { $0 as? NSTableView }.first!
  func hostedDocumentTitles() -> [String] {
   (0..<hostedGrid.numberOfRows).flatMap { row -> [String] in
    guard let view = hostedGrid.view(atColumn: 0, row: row, makeIfNecessary: true) else { return [] }
    return view.subviews.filter { $0.identifier?.rawValue.hasPrefix("document-") == true }
     .sorted { $0.frame.minX < $1.frame.minX }
     .compactMap { card in card.subviews.compactMap { $0 as? NSTextField }.first?.stringValue }
   }
  }
  let hostedTitlesBefore = hostedDocumentTitles()
  expect(hostedTitlesBefore.contains("Named Library Note"), "Library Documents pane shows the note catalog")
  let liveDocumentTab = store.open("https://unrelated-documents-title.example.invalid")
  store.updateTab(liveDocumentTab, title: "Unrelated documents live title")
  for _ in 0..<5 { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01)) }
  expect(hostedDocumentTitles() == hostedTitlesBefore, "Unrelated live tab titles do not rebuild Library Documents via store.statePublisher")
  documentsLibraryWindow.contentView = nil
  documentsLibraryWindow.close()
  SystemOverrides.reduceMotion = nil
  let table=all(view).compactMap{$0 as? DownloadLibraryTable}.first!
  let search=all(view).compactMap{$0 as? NSTextField}.first{$0.accessibilityLabel()=="Search Downloads"}!
  var actions:[String]=[];view.onAction={ item,action in actions.append(item.nativeID!+":"+String(describing:action));return true }
  func menu(_ name:String)->NSMenuItem {table.makeMenu!()!.items.first{$0.title==name}!}
  func invoke(_ item:NSMenuItem) { _ = NSApp.sendAction(item.action!,to:item.target,from:item) }
  table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
  func drainMain() {
   for _ in 0..<5 { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01)) }
  }
  func downloadLabels() -> [String] {
   (0..<table.numberOfRows).compactMap { table.view(atColumn: 0, row: $0, makeIfNecessary: true)?.accessibilityLabel() }
  }
  let liveTab=store.open("https://unrelated-library-title.example.invalid")
  let downloadSelection=table.selectedRowIndexes
  let labelsBeforeTitle=downloadLabels()
  let rowsBeforeTitle=table.numberOfRows
  store.updateTab(liveTab,title:"Unrelated live title")
  drainMain()
  expect(table.numberOfRows==rowsBeforeTitle && table.selectedRowIndexes==downloadSelection && downloadLabels()==labelsBeforeTitle,"Unrelated tab titles do not change Downloads rows or selection")
  store.updateTab(liveTab,url:"https://unrelated-library-url.example.invalid")
  drainMain()
  expect(downloadLabels()==labelsBeforeTitle,"Unrelated live tab URL publishes do not rebuild Downloads rows")
  store.recordDownload(["id":"a","profilePath":path,"name":"a","status":"downloading","available":true,"itemIdentity":"a1","canOpen":false,"receivedBytes":250000,"totalBytes":1000000,"sourceURL":"https://example.invalid/a","startedAt":1000])
  drainMain()
  let labelsAtBaseline=downloadLabels()
  store.recordDownload(["id":"a","profilePath":path,"name":"a","status":"downloading","available":true,"itemIdentity":"a1","canOpen":false,"receivedBytes":250000,"totalBytes":1000000,"sourceURL":"https://example.invalid/a","startedAt":1000])
  drainMain()
  expect(table.selectedRowIndexes==downloadSelection && downloadLabels()==labelsAtBaseline,"Identical download re-publish does not rebuild Downloads rows")
  store.recordDownload(["id":"a","profilePath":path,"name":"a","status":"downloading","available":true,"itemIdentity":"a1","canOpen":false,"receivedBytes":500000,"totalBytes":1000000,"sourceURL":"https://example.invalid/a","startedAt":1000])
  drainMain()
  expect(table.selectedRowIndexes==downloadSelection,"Download progress through the store sink keeps the original selected row")
  expect(downloadLabels() != labelsBeforeTitle && downloadLabels() != labelsAtBaseline,"Visible download progress updates when bytes change")
  let labelsAfterProgress=downloadLabels()
  store.updateTab(liveTab,title:"Still unrelated after progress")
  drainMain()
  expect(downloadLabels()==labelsAfterProgress,"Unrelated title publishes after progress keep the applied progress rows")
  let original=menu("Open");publish("a","a1",true,"renamed");view.setLoading(count:0,message:nil)
  expect(table.selectedRowIndexes==IndexSet(integer:1),"Progress/title refresh retains original selected row")
  invoke(original);expect(actions==["a:open"],"Captured menu executes actual original current item")
  let replaced=menu("Open");publish("a","a2");view.setLoading(count:0,message:nil)
  expect(table.selectedRowIndexes.isEmpty,"New incarnation clears actual native table selection")
  invoke(replaced);expect(actions.count==1,"Replaced item rejects retained menu callback")
  expect(!table.allowsMultipleSelection,"Actual Downloads table uses the original single-item cursor")
  table.selectRowIndexes(IndexSet(integer:2),byExtendingSelection:false)
  publish("b","b1",false);view.setLoading(count:0,message:nil)
  expect(!menu("Open").isEnabled,"Selected original capability disables actual native menu item")
  table.onConfirmSelection?();expect(actions.count==1,"Return confirms an ineligible original without file output")
  publish("b","b1");view.setLoading(count:0,message:nil)
  table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
  let busyItem=store.state.downloads.first{$0.nativeID=="a"}!
  view.setOperation(busyItem,message:"Moving to Trash…")
  expect(!menu("Open").isEnabled,"Accepted asynchronous file operation disables selected mutation/open")
  table.onConfirmSelection?();expect(actions.count==1,"Confirming a busy original cannot dispatch file output")
  view.setOperation(busyItem,message:nil)
  expect(menu("Open").isEnabled,"Completion restores manager-derived action eligibility")
  let selectionMenu=menu("Open");table.selectRowIndexes(IndexSet(integer:2),byExtendingSelection:false)
  invoke(selectionMenu);expect(actions.count==1,"Selection intervention expires original item menu")
  let expired=menu("Open");view.invalidate();invoke(expired)
  expect(actions.count==1,"Category/window invalidation expires menu context")
  table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
  let searchMenu=menu("Open");search.stringValue="a";view.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification))
  invoke(searchMenu);expect(actions.count==1,"Search context expires old item command")
  let editor=NSTextView();editor.setMarkedText("input",selectedRange:NSRange(location:5,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
  expect(!view.control(search,textView:editor,doCommandBy:#selector(NSResponder.insertNewline(_:))),"Composition Return stays owned by native text input")
  editor.unmarkText()
  let actionsBeforeReturn = actions.count
  table.deselectAll(nil); table.onConfirmSelection?()
  expect(table.selectedRowIndexes == IndexSet(integer:1) && actions.count == actionsBeforeReturn,"Actual Return owner selects first filtered item without opening it")
  table.onConfirmSelection?()
  expect(table.selectedRowIndexes == IndexSet(integer:1) && actions.count == actionsBeforeReturn,"Repeated Return retains the selected original without output")
  expect(view.control(search,textView:editor,doCommandBy:#selector(NSResponder.insertNewline(_:))),"Unmarked search Return is consumed by the original cursor owner")
  expect(window.firstResponder === table && actions.count == actionsBeforeReturn,"Search Return hands focus to the native table without launching the file")
  search.stringValue="no matching download";view.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification))
  table.onConfirmSelection?()
  expect(table.selectedRowIndexes.isEmpty && actions.count == actionsBeforeReturn,"Empty filtered results cannot manufacture a Return target")
  search.stringValue="a";view.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification))
  table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
  let hide = menu("Hide from Parc")
  expect(!hide.title.hasSuffix("…"),"Direct Hide does not advertise a nonexistent dialog")
  invoke(hide)
  expect(window.attachedSheet == nil && actions.last=="a:remove","Hide dispatches the exact original directly without a confirmation sheet")
  let trash = menu("Move to Trash")
  expect(trash.isEnabled,"Original completed file admits explicit Trash")
  invoke(trash)
  expect(window.attachedSheet == nil && actions.last=="a:trash","Trash passes the original to the real asynchronous boundary without a second confirmation")
  let afterDirectActions=actions.count
  let retiredHide=menu("Hide from Parc")
  publish("a","a3");view.setLoading(count:0,message:nil)
  invoke(retiredHide)
  expect(actions.count==afterDirectActions,"A replaced original cannot accept a previously captured Hide")
  search.stringValue="";view.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification))
  table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
  let outgoingURL=directory.appendingPathComponent("original.png")
  view.fileURL={_ in outgoingURL}
  expect(table.canDrag?(IndexSet(integer:1))==true,"One original completed selected row admits file drag")
  expect(table.canDrag?(IndexSet([1,2]))==false,"No invented plural file drag")
  expect(table.canDrag?(IndexSet(integer:0))==false,"Date headings cannot be dragged")
  let outgoing=view.tableView(table,pasteboardWriterForRow:1) as! NSPasteboardItem
  expect(outgoing.string(forType:.fileURL)==outgoingURL.absoluteString,"Actual table drag supplies the original completed file URL")
  let changedSelection=view.tableView(table,pasteboardWriterForRow:1) as! NSPasteboardItem
  table.selectRowIndexes(IndexSet(integer:2),byExtendingSelection:false)
  table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
  expect(changedSelection.string(forType:.fileURL)==nil,"Selection intervention permanently expires pending file delivery")
  let changedContext=view.tableView(table,pasteboardWriterForRow:1) as! NSPasteboardItem
  view.invalidate()
  expect(changedContext.string(forType:.fileURL)==nil,"Library retirement cancels pending outgoing file provider")
  let replacedFile=view.tableView(table,pasteboardWriterForRow:1) as! NSPasteboardItem
  view.fileURL={_ in directory.appendingPathComponent("replacement.png")}
  expect(replacedFile.string(forType:.fileURL)==nil,"Drag cannot retarget a changed path under the same record")
  view.fileURL={_ in outgoingURL}
  let replacedLease=view.tableView(table,pasteboardWriterForRow:1) as! NSPasteboardItem
  publish("a","a4");view.setLoading(count:0,message:nil)
  expect(replacedLease.string(forType:.fileURL)==nil,"New manager incarnation expires file delivery")
  table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
  let draggingItem=store.state.downloads.first{$0.nativeID=="a"}!
  view.setOperation(draggingItem,message:"Moving to Trash…")
  expect(view.tableView(table,pasteboardWriterForRow:1)==nil,"Busy original file refuses outgoing drag")
  view.setOperation(draggingItem,message:nil)
  var replies:[@MainActor (DownloadThumbnailProvider.Delivery)->Void]=[], cancelled=0, delivered=0
  let provider=DownloadThumbnailProvider(loader:{ _, reply in replies.append(reply);return {cancelled += 1} })
  let first=store.state.downloads.first!
  let key=DownloadThumbnailProvider.Key(item:DownloadLibraryIdentity(first),url:directory.appendingPathComponent("fixture.png"),bytes:1)
  var currentThumbnail = first
  currentThumbnail.receivedBytes = key.bytes; currentThumbnail.canCopyFile = true
  expect(key.admits(currentThumbnail,url:key.url),"Thumbnail lease admits the original eligible bytes")
  currentThumbnail.canCopyFile = false
  expect(!key.admits(currentThumbnail,url:key.url),"Same-item security change revokes the pending thumbnail")
  currentThumbnail.canCopyFile = true; currentThumbnail.receivedBytes += 1
  expect(!key.admits(currentThumbnail,url:key.url),"Same-item byte replacement revokes the pending thumbnail")
  currentThumbnail.receivedBytes = key.bytes
  expect(!key.admits(currentThumbnail,url:key.url.appendingPathExtension("changed")),"File URL replacement revokes the pending thumbnail")
  currentThumbnail.nativeIdentity = "replacement-incarnation"
  expect(!key.admits(currentThumbnail,url:key.url),"Same native GUID in a new incarnation cannot reuse the thumbnail")
  var valid=true
  let request=provider.request(key,valid:{valid},completion:{_ in delivered += 1})
  provider.cancel(request);replies[0](.finished(NSImage(size:NSSize(width:2,height:2))))
  expect(cancelled==1 && delivered==0,"Cancelled thumbnail cannot publish")
  _=provider.request(key,valid:{valid},completion:{_ in delivered += 1});valid=false
  replies[1](.finished(NSImage(size:NSSize(width:2,height:2))))
  expect(delivered==0,"Retired original profile/item cannot publish image")
  valid=true
  _=provider.request(key,valid:{valid},completion:{_ in delivered += 1})
  replies[2](.finished(NSImage(size:NSSize(width:2,height:2))))
  expect(delivered==1,"Genuine eligible completed request publishes image")
  _=provider.request(key,valid:{valid},completion:{_ in delivered += 1})
  expect(delivered==2 && replies.count==3,"Same exact original identity reuses bounded cache")
  provider.invalidate()
  _=provider.request(key,valid:{valid},completion:{_ in delivered += 1})
  expect(replies.count==4,"Category retirement clears file image cache")
  provider.invalidate();replies[3](.finished(NSImage(size:NSSize(width:2,height:2))))
  expect(delivered==2 && cancelled==3,"Invalidated generator callback remains harmless")
  var phaseImages:[NSImage?]=[]
  let provisional=NSImage(size:NSSize(width:14,height:14))
  let finalImage=NSImage(size:NSSize(width:24,height:24))
  _=provider.request(key,valid:{true},completion:{phaseImages.append($0)})
  replies[4](.provisional(provisional))
  expect(phaseImages.count==1 && phaseImages.last! === provisional,"Original file icon can appear while thumbnail remains pending")
  replies[4](.finished(finalImage))
  replies[4](.provisional(provisional))
  expect(phaseImages.count==2 && phaseImages.last! === finalImage,"Late icon cannot replace the finished thumbnail")
  provider.invalidate()
  _=provider.request(key,valid:{true},completion:{_ in provider.invalidate()})
  replies[5](.provisional(provisional));replies[5](.finished(finalImage))
  expect(cancelled==4,"Provisional callback can retire its exact pending owner reentrantly")
  var validateCount=0, staleDelivery=0
  _=provider.request(key,valid:{validateCount += 1;if validateCount>1 {provider.invalidate()};return true},completion:{_ in staleDelivery += 1})
  replies[6](.finished(finalImage))
  expect(staleDelivery==0,"Validation reentry cannot deliver or cache a retired original token")
  _=provider.request(key,valid:{true},completion:{_ in staleDelivery += 1})
  expect(replies.count==8 && staleDelivery==0,"Retired validation did not seed the original cache")
  provider.invalidate()
  var iconReply:((NSImage?)->Void)?, thumbReply:((NSImage?)->Void)?
  var nativePhases:[DownloadThumbnailProvider.Delivery]=[], nativeCancels=0
  func nativeRequest() -> DownloadArtworkRequest {
   DownloadArtworkRequest(url:key.url,iconLoader:{_,reply in iconReply=reply;return {nativeCancels += 1}},
     thumbnailLoader:{_,reply in thumbReply=reply;return {nativeCancels += 1}},completion:{nativePhases.append($0)})
  }
  let firstNative=nativeRequest();firstNative.start();iconReply?(provisional)
  expect(nativePhases.count==1,"Actual artwork request publishes its first original icon provisionally")
  thumbReply?(finalImage);iconReply?(provisional)
  expect(nativePhases.count==2,"Actual thumbnail wins once and rejects later original icon response")
  nativePhases=[]
  let fallbackNative=nativeRequest();fallbackNative.start();thumbReply?(nil)
  expect(nativePhases.isEmpty,"Missing thumbnail waits for the original asynchronous file icon")
  iconReply?(provisional)
  expect(nativePhases.count==1,"Original icon completes the real request when thumbnail is unavailable")
  nativePhases=[]
  let earlyNative=nativeRequest();earlyNative.start();thumbReply?(finalImage);iconReply?(provisional)
  expect(nativePhases.count==1,"Fast thumbnail bypasses and cancels pending icon without replacement")
  nativePhases=[]
  let cancelledNative=nativeRequest();cancelledNative.start();cancelledNative.cancel();iconReply?(provisional);thumbReply?(finalImage)
  expect(nativePhases.isEmpty && nativeCancels==5,"Retirement cancels both actual producers and refuses delayed results")
  var artworkItem=first
  artworkItem.path="/owned/Original Photo.PNG";artworkItem.status = .completed;artworkItem.fileMissing=false
  artworkItem.requiresReview=false
  expect(DownloadRowArtwork.title(for:artworkItem)=="original photo.png" && artworkItem.path=="/owned/Original Photo.PNG","Displayed lowercase filename never changes original file path")
  expect(DownloadRowArtwork.kind(for:artworkItem) == .file && !DownloadRowArtwork.dimsTitle(artworkItem),"Completed available file owns image and ordinary title")
  artworkItem.fileMissing=true
  expect(DownloadRowArtwork.kind(for:artworkItem) == .emptyFavicon && DownloadRowArtwork.dimsTitle(artworkItem),"Known missing file owns empty artwork and secondary title")
  for status in [BrowserDownloadStatus.failed,.cancelled,.pending,.paused,.downloading] {
   artworkItem.status=status;artworkItem.fileMissing=false
   expect(DownloadRowArtwork.dimsTitle(artworkItem)==(status == .failed || status == .cancelled),"Only failed and cancelled incomplete titles are dimmed")
  }
  artworkItem.requiresReview=true
  expect(DownloadRowArtwork.kind(for:artworkItem) == .security,"Actual security review retains its explicit native warning artwork")
  let preview=DownloadLibraryPreview();var moved:[Bool]=[], opened=0, closed=0
  preview.onMove={moved.append($0)};preview.onOpen={opened += 1};preview.onClosed={closed += 1}
  preview.update(url:key.url,title:"Fixture",ordinal:2,count:3,canOpen:false,canMovePrevious:true,canMoveNext:false)
  func keyEvent(_ code:UInt16)->NSEvent {NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:preview.window!.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:code)!}
  preview.window!.sendEvent(keyEvent(126));preview.window!.sendEvent(keyEvent(125));preview.window!.sendEvent(keyEvent(36))
  expect(moved==[false] && opened==0,"Preview keys respect actual disabled bounds and original open capability")
  preview.window!.sendEvent(keyEvent(49));preview.close()
  expect(closed==1,"Space closes one preview owner exactly once")
  let previewParent=NSWindow(contentRect:NSRect(x:150,y:150,width:1000,height:700),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
  previewParent.isReleasedWhenClosed=false
  SystemOverrides.reduceMotion=true
  let overlay=DownloadLibraryPreview();var overlayClosed=0
  overlay.onClosed={overlayClosed += 1};overlay.onMenu={NSMenu(title:"Original fixture")}
  overlay.sourceRect={NSRect(x:20,y:40,width:32,height:32)}
  overlay.sourceImage=NSImage(size:NSSize(width:32,height:32))
  overlay.update(url:key.url,title:"Original downloaded file.png",ordinal:1,count:2,canOpen:true,canMovePrevious:false,canMoveNext:true)
  overlay.present(on:previewParent)
  let overlayWindow=overlay.window!, overlayRoot=overlayWindow.contentView!, modal=overlayRoot.subviews.last!
  expect(overlayWindow.parent === previewParent && overlayWindow.frame==previewParent.frame,"Preview stays a child covering its exact original parent")
  expect(overlayWindow.styleMask == .borderless && !overlayWindow.isOpaque && !overlayWindow.hasShadow,"Preview uses transparent borderless overlay rather than a second floating document window")
  expect(modal.frame==DownloadPreviewGeometry.modalFrame(in:overlayRoot.bounds),"Actual content uses centered parent-relative preview geometry")
  expect(abs(modal.frame.midX-overlayRoot.bounds.midX)<0.01 && abs(modal.frame.midY-overlayRoot.bounds.midY)<0.01,"Native layer center remains consistent with AppKit modal frame")
  expect(modal.layer?.animationKeys()?.isEmpty != false,"Reduce Motion suppresses spatial opening animation")
  expect(modal.subviews.first?.layer?.opacity==1 && modal.subviews.last?.layer?.opacity==0,"Reduce Motion immediately shows live content rather than snapshot")
  let overlayButtons=all(modal).compactMap{$0 as? NSButton}
  expect(overlayButtons.first{$0.toolTip=="Close preview"} === overlayWindow.firstResponder,"Opening preview gives its native close control keyboard focus")
  expect(overlayButtons.first{$0.toolTip=="Previous download"}?.isEnabled==false && overlayButtons.first{$0.toolTip=="Next download"}?.isEnabled==true,"Toolbar reflects original selection endpoints")
  expect(overlayButtons.first{$0.toolTip=="Download actions"}?.isHidden==false,"Preview exposes original-item More menu")
  expect(overlayButtons.allSatisfy{$0.isHidden || modal.bounds.contains($0.frame)},"Actual preview toolbar controls fit original modal")
  expect(all(modal).compactMap{$0 as? NSTextField}.first?.toolTip=="Original downloaded file.png · 1 of 2","Full original title and position remain accessible")
  previewParent.setFrame(NSRect(x:170,y:180,width:800,height:500),display:false)
  overlayRoot.layoutSubtreeIfNeeded()
  expect(overlayWindow.frame==previewParent.frame,"Original parent move/resize updates the same overlay")
  expect(modal.frame==DownloadPreviewGeometry.modalFrame(in:overlayRoot.bounds),"Resizing reflows actual preview content")
  overlay.dismiss();overlay.close()
  expect(overlayClosed==1 && overlayWindow.parent==nil && !overlayWindow.isVisible,"Reduced-motion dismissal retires exactly once and removes child ownership")
  previewParent.setFrameOrigin(NSPoint(x:180,y:190))
  expect(overlayClosed==1,"Retired parent observer cannot re-present or close another preview")
  let retired=DownloadLibraryPreview();var retiredCount=0
  retired.onClosed={retiredCount += 1};retired.update(url:key.url,title:"Owned",ordinal:1,count:1,canOpen:false,canMovePrevious:false,canMoveNext:false)
  retired.present(on:previewParent)
  let ownedSheet=NSWindow(contentRect:NSRect(x:0,y:0,width:100,height:80),styleMask:.titled,backing:.buffered,defer:false)
  previewParent.beginSheet(ownedSheet)
  expect(retiredCount==1 && retired.window?.parent==nil,"A real competing parent sheet retires preview before its command can outlive that owner")
  previewParent.endSheet(ownedSheet);ownedSheet.orderOut(nil)
  SystemOverrides.reduceMotion=false
  let moving=DownloadLibraryPreview();var movingClosed=0
  moving.onClosed={movingClosed += 1};moving.sourceRect={NSRect(x:20,y:40,width:32,height:16)}
  let sourceArtwork=NSImage(size:NSSize(width:32,height:16));moving.sourceImage=sourceArtwork
  moving.update(url:key.url,title:"Animated fixture",ordinal:1,count:1,canOpen:false,canMovePrevious:false,canMoveNext:false)
  moving.present(on:previewParent)
  let movingModal=moving.window!.contentView!.subviews.last!
  expect(movingModal.layer?.animation(forKey:"transform") is CASpringAnimation,"Valid original artwork admits the actual recovered spring transition")
  let transitionImage=movingModal.subviews.compactMap{$0 as? NSImageView}.first!
  let liveContent=movingModal.subviews.first!
  expect(transitionImage.image === sourceArtwork,"Preview retains original row snapshot, not a new live-content screenshot")
  expect(transitionImage.frame.height==movingModal.bounds.width/2 && transitionImage.frame.midY==movingModal.bounds.midY,"Image keeps original aspect centered through uniform outer scaling")
  expect(transitionImage.layer?.animation(forKey:"opacity") is CASpringAnimation && liveContent.layer?.animation(forKey:"opacity") is CASpringAnimation,"Source image and live content crossfade independently")
  expect(transitionImage.layer?.opacity==0 && liveContent.layer?.opacity==1 && movingModal.layer?.animation(forKey:"opacity")==nil,"Final visible layer is live content; entire modal does not fade")
  expect(transitionImage.hitTest(.zero)==nil && !transitionImage.isAccessibilityElement() && transitionImage.isAccessibilityHidden(),"Transparent transition artwork cannot steal pointer or accessibility focus")
  expect(movingModal.layer?.shadowRadius==5 && movingModal.layer?.shadowOffset==NSSize(width:0,height:-3) && movingModal.layer?.masksToBounds==false,"Owned outer shadow remains visible outside the clipped content")
  moving.update(url:directory.appendingPathComponent("next.png"),title:"Next preview",ordinal:2,count:2,canOpen:false,canMovePrevious:true,canMoveNext:false)
  expect(transitionImage.image === sourceArtwork,"Changing selected preview retains the invocation's source image")
  moving.dismiss()
  expect(transitionImage.layer?.opacity==1 && liveContent.layer?.opacity==0,"Closing reverses image/content without replacing the source")
  expect(movingModal.layer?.shadowOpacity==0,"Closing retires original shadow with the backdrop")
  expect(movingModal.layer?.animation(forKey:"transform")?.isRemovedOnCompletion==false,"Interrupted opening transitions toward source without resetting the visible layer")
  moving.close()
  RunLoop.main.run(until:Date().addingTimeInterval(0.1))
  expect(movingClosed==1 && moving.window?.parent==nil,"Immediate owner retirement supersedes an active close animation exactly once")
  expect(moving.sourceImage==nil && transitionImage.image==nil,"Retirement releases the source snapshot and all image presentation")
  let resizing=DownloadLibraryPreview();resizing.sourceImage=sourceArtwork
  resizing.sourceRect={NSRect(x:20,y:40,width:32,height:16)}
  resizing.update(url:key.url,title:"Resizing",ordinal:1,count:1,canOpen:false,canMovePrevious:false,canMoveNext:false)
  resizing.present(on:previewParent)
  let resizingModal=resizing.window!.contentView!.subviews.last!
  previewParent.setFrame(NSRect(x:180,y:190,width:750,height:480),display:false)
  resizing.window!.contentView!.layoutSubtreeIfNeeded()
  expect(resizingModal.subviews.allSatisfy{$0.layer?.animationKeys()?.isEmpty != false},"Parent geometry change settles both image/content animations together")
  expect(resizingModal.subviews.first?.layer?.opacity==1 && resizingModal.subviews.last?.layer?.opacity==0,"Resize never leaves transparent live content or a stranded snapshot")
  resizing.close()
  let expiredSource=DownloadLibraryPreview();var expiredClosed=0
  expiredSource.onClosed={expiredClosed += 1};expiredSource.sourceRect={nil}
  expiredSource.update(url:key.url,title:"Offscreen row",ordinal:1,count:1,canOpen:false,canMovePrevious:false,canMoveNext:false)
  expiredSource.present(on:previewParent)
  expect(expiredSource.window!.contentView!.subviews.last!.layer?.animationKeys()?.isEmpty != false,"Absent/offscreen original row does not invent a transition destination")
  expiredSource.dismiss();expect(expiredClosed==1,"Expired source dismisses immediately without retaining an animation owner")
  expect(DownloadPreviewGeometry.modalFrame(in:NSRect(x:5,y:10,width:80,height:60))==NSRect(x:5,y:10,width:80,height:60),"Tiny parent adaptation clamps content to real owner bounds")
  previewParent.close()
  SystemOverrides.reduceMotion=true
  let archiveView=LibraryView(store:store,kind:.archive,profileID:profile)
  archiveView.frame=NSRect(x:0,y:0,width:416,height:600)
  let archiveWindow=NSWindow(contentRect:archiveView.frame,styleMask:.titled,backing:.buffered,defer:false)
  archiveWindow.isReleasedWhenClosed=false;archiveWindow.contentView=archiveView;archiveView.layoutSubtreeIfNeeded()
  let archiveSearch=all(archiveView).compactMap{$0 as? NSTextField}.first{$0.accessibilityLabel()=="Search Library"}!
  let archiveFilter=all(archiveView).compactMap{$0 as? NSButton}.first{$0.title=="Filter"}!
  expect(archiveFilter.frame.width==archiveFilter.fittingSize.width && archiveFilter.fittingSize.width>72,"Archive Filter uses its fitting width so the title is not clipped to 72")
  expect(archiveSearch is DownloadSearchField && archiveSearch.superview is DownloadSearchBackdrop && (archiveFilter as? DownloadFilterButton)?.style == .header,
         "Archive header is the shared search field, its backdrop and the header Filter")
  let filterText=ceil(("Filter" as NSString).size(withAttributes:[.font:archiveFilter.font!]).width)
  expect(archiveFilter.fittingSize.width==10+LibraryHeaderGlyph.side+4+filterText+10,"Filter pads its 15-point glyph and title by 10 points")
  let headerReference=LibraryView(store:store,kind:.downloads,profileID:profile)
  headerReference.frame=archiveView.frame
  let headerReferenceWindow=NSWindow(contentRect:headerReference.frame,styleMask:.titled,backing:.buffered,defer:false)
  headerReferenceWindow.isReleasedWhenClosed=false;headerReferenceWindow.contentView=headerReference;headerReference.layoutSubtreeIfNeeded()
  func headerFrames(_ library:LibraryView)->[NSRect] {
   let field=all(library).compactMap{$0 as? DownloadSearchField}.first{!$0.isHiddenOrHasHiddenAncestor}!
   let action=all(library).compactMap{$0 as? DownloadFilterButton}.first{$0.style == .header && !$0.isHiddenOrHasHiddenAncestor}!
   return [field.superview!,field,action].map{library.convert($0.bounds,from:$0)}
  }
  let archiveHeader=headerFrames(archiveView), pageX=LibraryRailLayout.width+LibraryPageHeader.inset
  let downloadsField=all(headerReference).compactMap{$0 as? DownloadSearchField}.first{!$0.isHiddenOrHasHiddenAncestor}!
  let downloadsBackdrop=headerReference.convert(downloadsField.superview!.bounds,from:downloadsField.superview!)
  expect(!all(headerReference).contains{($0 as? DownloadFilterButton)?.style == .header && !$0.isHiddenOrHasHiddenAncestor},
         "The Downloads page has no Filter now that its only filter was by profile")
  expect(downloadsBackdrop.minX==archiveHeader[0].minX && downloadsBackdrop.minY==archiveHeader[0].minY
         && downloadsBackdrop.height==archiveHeader[0].height
         && abs(downloadsBackdrop.maxX-(headerReference.bounds.width-LibraryPageHeader.inset))<0.5,
         "Downloads search starts where Archive's does and runs to the page inset without a Filter")
  expect(archiveHeader[0]==NSRect(x:pageX,y:LibraryPageHeader.top,width:archiveHeader[2].minX-LibraryPageHeader.spacing-pageX,height:LibraryPageHeader.height)
         && archiveHeader[2].maxX==archiveView.bounds.width-LibraryPageHeader.inset && archiveHeader[2].minY==LibraryPageHeader.top
         && archiveHeader[2].height==LibraryPageHeader.height,"Archive header uses LibraryPageHeader's inset, top, height and field-action gap")
  headerReferenceWindow.contentView=nil;headerReferenceWindow.close()
  let archiveList=all(archiveView).compactMap{$0 as? NSTableView}.first!.enclosingScrollView!
  expect(abs(archiveList.frame.maxY-archiveView.bounds.height)<0.5,"Archive list reaches the bottom; there is no footer bar")
  let depthFrame=NSRect(x:0,y:0,width:145,height:archiveView.bounds.height)
  expect(archiveView.subviews.contains{$0.frame==depthFrame && $0.hitTest(NSPoint(x:8,y:8))==nil && !($0 is WindowStandardButtons)},"Archive paints the non-interactive depth layer over the rail and its 33-point edge only")
  expect(archiveSearch.placeholderAttributedString?.string=="Search Archive…","Archive shows its search placeholder")
  for dark in [false,true,false] {
   archiveView.palette=ThemeChromePalette(theme:SpaceTheme(),isDark:dark)
   expect(archiveSearch.placeholderAttributedString?.string=="Search Archive…","A theme change keeps the Archive search placeholder")
   expect(archiveSearch.placeholderAttributedString?.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor == .placeholderTextColor
          && archiveSearch.textColor == .labelColor && archiveSearch.font == DownloadSearchField.textFont,
          "A theme change keeps the shared field's placeholder grey, primary query and 14-point medium type")
  }
  func pressArchive(_ button:NSButton) { _=NSApp.sendAction(button.action!,to:button.target,from:button) }
  archiveSearch.stringValue="query";archiveWindow.makeFirstResponder(archiveSearch)
  let archiveEditor=archiveSearch.currentEditor() as! NSTextView
  archiveEditor.setSelectedRange(NSRange(location:1,length:2))
  archiveEditor.setMarkedText("input",selectedRange:NSRange(location:5,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
  pressArchive(archiveFilter)
  expect(archiveFilter.title=="Filter" && archiveEditor.hasMarkedText(),"Archive refuses to hide an active composition")
  let archiveRail=all(archiveView).compactMap{$0 as? NSButton}.first{$0.title=="Archived Tabs"}!
  let downloadsRail=all(archiveView).compactMap{$0 as? NSButton}.first{$0.title=="Downloads"}!
  archiveRail.performClick(nil)
  expect(archiveEditor.hasMarkedText() && archiveRail.state == .on,"Reselecting Archive preserves composition and selected rail state")
  downloadsRail.performClick(nil)
  expect(archiveView.kind == .archive && archiveEditor.hasMarkedText() && archiveRail.state == .on && downloadsRail.state == .off,"Rejected category switch preserves composition and original rail state")
  archiveEditor.unmarkText();archiveSearch.stringValue="query";archiveEditor.setSelectedRange(NSRange(location:1,length:2))
  pressArchive(archiveFilter);archiveView.layoutSubtreeIfNeeded()
  expect(archiveFilter.title=="Done" && archiveSearch.isHiddenOrHasHiddenAncestor && archiveSearch.stringValue=="query","Archive filter replaces Search while retaining query")
  expect(archiveFilter.frame.width==archiveFilter.fittingSize.width,"Done keeps the header action sized to its title")
  let archiveDoneText=ceil(("Done" as NSString).size(withAttributes:[.font:archiveFilter.font!]).width)
  expect(archiveFilter.fittingSize.width==12+archiveDoneText+12 && archiveFilter.frame.maxX==archiveView.bounds.width-LibraryPageHeader.inset
         && archiveFilter.frame.minY==LibraryPageHeader.top && archiveFilter.frame.height==LibraryPageHeader.height,
         "Archive Done pads its title by PageFilterView's 12 points in the header's trailing slot")
  expect(all(archiveView).compactMap{$0 as? NSTextField}.contains{$0.stringValue=="Filter Archived Tabs" && !$0.isHidden},"Archive exposes filter heading")
  let oldChip=all(archiveView).compactMap{$0 as? NSButton}.first{$0.title=="Auto-Closed" && !$0.isHiddenOrHasHiddenAncestor}!
  pressArchive(oldChip)
  let replacementChip=all(archiveView).compactMap{$0 as? NSButton}.first{$0.title=="Auto-Closed"}!
  expect(replacementChip.state == .on,"Archive closure chip selects its filter")
  pressArchive(oldChip)
  expect(replacementChip.state == .on,"Retired chip cannot repeat a stale filter action")
  let manualChip=all(archiveView).compactMap{$0 as? NSButton}.first{$0.title=="Manually Closed"}!
  pressArchive(manualChip)
  func archiveChip(_ name:String)->NSButton { all(archiveView).compactMap{$0 as? NSButton}.first{$0.title==name}! }
  expect(archiveChip("Auto-Closed").state == .off && archiveChip("Manually Closed").state == .on,"Selecting the other closure type replaces the first")
  pressArchive(archiveChip("Manually Closed"))
  expect(archiveChip("Auto-Closed").state == .off && archiveChip("Manually Closed").state == .off,"Reselecting the active closure type returns to All")
  pressArchive(archiveFilter)
  expect(!archiveSearch.isHiddenOrHasHiddenAncestor && archiveSearch.currentEditor()?.selectedRange==NSRange(location:1,length:2),"Done restores the original query range")
  (archiveSearch.currentEditor() as! NSTextView).setSelectedRange(NSRange(location:5,length:0))
  pressArchive(archiveFilter);pressArchive(archiveFilter)
  expect(archiveSearch.currentEditor()?.selectedRange==NSRange(location:5,length:0),"Done restores an end-of-query caret")
  archiveSearch.stringValue="";(archiveSearch.currentEditor() as! NSTextView).setSelectedRange(NSRange(location:0,length:0))
  pressArchive(archiveFilter);pressArchive(archiveFilter)
  expect(archiveSearch.currentEditor()?.selectedRange==NSRange(location:0,length:0),"Done restores an empty-query caret")
  pressArchive(archiveFilter)
  archiveView.show(.downloads);archiveView.frame.size.width=380;archiveView.layoutSubtreeIfNeeded()
  expect(archiveSearch.isHiddenOrHasHiddenAncestor,"Resizing another Library category cannot reveal Archive search")
  archiveView.show(.archive);pressArchive(archiveFilter)
  let priorWindowChip=all(archiveView).compactMap{$0 as? NSButton}.first{$0.title=="Manually Closed"}!
  archiveWindow.contentView=nil;pressArchive(archiveFilter)
  expect(archiveFilter.title=="Done","Detached Archive rejects stale filter action")
  let replacementWindow=NSWindow(contentRect:archiveView.frame,styleMask:.titled,backing:.buffered,defer:false)
  replacementWindow.isReleasedWhenClosed=false;replacementWindow.contentView=archiveView
  let newWindowChip=all(archiveView).compactMap{$0 as? NSButton}.first{$0.title=="Manually Closed"}!
  pressArchive(priorWindowChip)
  expect(newWindowChip.state == .off,"A chip captured in the original window cannot act in a replacement window")
  pressArchive(newWindowChip)
  expect(all(archiveView).compactMap{$0 as? NSButton}.first{$0.title=="Manually Closed"}!.state == .on,"Reattached Archive gets live controls for its new window")
  replacementWindow.contentView=nil;replacementWindow.close();archiveWindow.close()
  let reasonStore=try BrowserStore(directory:directory.appendingPathComponent("archive-reasons",isDirectory:true))
  let reasonProfile=reasonStore.activeSpace.profileID
  let automaticID=reasonStore.open("https://auto.example.invalid")
  let manualID=reasonStore.open("https://manual.example.invalid")
  reasonStore.closeTabs([automaticID],reason:.automatic)
  reasonStore.closeTabs([manualID],reason:.manual)
  let reasonView=LibraryView(store:reasonStore,kind:.archive,profileID:reasonProfile)
  reasonView.frame=NSRect(x:0,y:0,width:416,height:600)
  let reasonWindow=NSWindow(contentRect:reasonView.frame,styleMask:.titled,backing:.buffered,defer:false)
  reasonWindow.isReleasedWhenClosed=false;reasonWindow.contentView=reasonView;reasonView.layoutSubtreeIfNeeded()
  let reasonTable=all(reasonView).compactMap{$0 as? NSTableView}.first!
  func displayedArchiveTitles()->[String] {
   (0..<reasonTable.numberOfRows).flatMap { row in
    all(reasonTable.view(atColumn:0,row:row,makeIfNecessary:true)!).compactMap { ($0 as? NSTextField)?.stringValue }
   }
  }
  func reasonChip(_ name:String)->NSButton {all(reasonView).compactMap{$0 as? NSButton}.first{$0.title==name}!}
  expect(displayedArchiveTitles().contains("auto.example.invalid") && displayedArchiveTitles().contains("manual.example.invalid"),"All shows both original closure reasons")
  pressArchive(reasonChip("Filter"));pressArchive(reasonChip("Auto-Closed"))
  expect(displayedArchiveTitles().contains("auto.example.invalid") && !displayedArchiveTitles().contains("manual.example.invalid"),"Auto filter displays only automatic records")
  pressArchive(reasonChip("Manually Closed"))
  expect(!displayedArchiveTitles().contains("auto.example.invalid") && displayedArchiveTitles().contains("manual.example.invalid"),"Manual replaces Auto in the actual rows")
  pressArchive(reasonChip("Manually Closed"))
  expect(displayedArchiveTitles().contains("auto.example.invalid") && displayedArchiveTitles().contains("manual.example.invalid"),"Reselecting Manual restores all original rows")
  reasonWindow.contentView=nil;reasonWindow.close()
  var archiveNow = Date(timeIntervalSince1970: 1_900_000_000)
  let menuStore=try BrowserStore(directory:directory.appendingPathComponent("archive-menu",isDirectory:true),now:{archiveNow})
  let menuProfile=menuStore.activeSpace.profileID, originalSpace=menuStore.activeSpaceID
  let groupA=menuStore.open("https://group-a.example.invalid"), groupB=menuStore.open("https://group-b.example.invalid")
  menuStore.setSplit([groupA,groupB]);menuStore.closeTabs([groupA,groupB])
  archiveNow.addTimeInterval(1)
  let other=menuStore.open("https://other.example.invalid");menuStore.closeTabs([other])
  let menuView=LibraryView(store:menuStore,kind:.archive,profileID:menuProfile)
  var ownerValid=true;menuView.archiveOwnerValid={ownerValid}
  var restored:[([UUID],UUID?)]=[];menuView.onRestore={restored.append(($0,$1))}
  menuView.frame=NSRect(x:0,y:0,width:416,height:600)
  let menuWindow=NSWindow(contentRect:menuView.frame,styleMask:.titled,backing:.buffered,defer:false)
  menuWindow.isReleasedWhenClosed=false;menuWindow.contentView=menuView;menuView.layoutSubtreeIfNeeded()
  let archiveTable=all(menuView).compactMap{$0 as? NSTableView}.first!
  func archiveRow(_ title:String)->Int {
   (0..<archiveTable.numberOfRows).first { row in
    guard let cell=archiveTable.view(atColumn:0,row:row,makeIfNecessary:true) else {return false}
    return all(cell).compactMap{$0 as? NSTextField}.contains{$0.stringValue.contains(title)}
   }!
  }
  func archiveMenu(_ row:Int)->NSMenu {
   let point=archiveTable.convert(NSPoint(x:20,y:archiveTable.rect(ofRow:row).midY),to:nil)
   let event=NSEvent.mouseEvent(with:.rightMouseDown,location:point,modifierFlags:[],timestamp:0,windowNumber:menuWindow.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
   return archiveTable.menu(for:event)!
  }
  let groupRow=archiveRow("group-a.example.invalid"), otherRow=archiveRow("other.example.invalid")
  func archiveKey(_ code:UInt16, _ flags:NSEvent.ModifierFlags = []) {
   let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:menuWindow.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:code)!
   archiveTable.keyDown(with:event)
  }
  let archiveRows=[groupRow,otherRow].sorted()
  expect(!archiveTable.allowsMultipleSelection,"Archive table has one cursor")
  archiveTable.deselectAll(nil);archiveKey(126)
  expect(archiveTable.selectedRowIndexes==IndexSet(integer:archiveRows[0]),"Up from no Archive cursor selects the first item")
  archiveKey(125,[.shift,.function])
  expect(archiveTable.selectedRowIndexes==IndexSet(integer:archiveRows[1]),"Shift Down moves the single Archive cursor")
  archiveKey(125)
  expect(archiveTable.selectedRowIndexes==IndexSet(integer:archiveRows[1]),"Archive cursor stops at the last item")
  archiveKey(126,.shift);archiveKey(126)
  expect(archiveTable.selectedRowIndexes==IndexSet(integer:archiveRows[0]),"Archive cursor stops at the first item")
  archiveTable.selectAll(nil)
  expect(archiveTable.selectedRowIndexes==IndexSet(integer:archiveRows[0]) && !archiveTable.validateUserInterfaceItem(NSMenuItem(title:"Select All",action:#selector(NSTableView.selectAll(_:)),keyEquivalent:"a")),"Archive Select All cannot create plural selection")
  menuView.show(.archive)
  expect(!archiveTable.allowsMultipleSelection,"Returning to Archive restores single selection")
  var fingerprintNow=Date(timeIntervalSince1970:1_910_000_000)
  let fingerprintStore=try BrowserStore(directory:directory.appendingPathComponent("archive-fingerprint",isDirectory:true),now:{fingerprintNow})
  let fingerprintProfile=fingerprintStore.activeSpace.profileID
  let fingerprintArchived=fingerprintStore.open("https://fingerprint-archived.example.invalid")
  fingerprintStore.closeTabs([fingerprintArchived])
  fingerprintNow.addTimeInterval(1)
  let fingerprintView=LibraryView(store:fingerprintStore,kind:.archive,profileID:fingerprintProfile)
  fingerprintView.frame=NSRect(x:0,y:0,width:416,height:600)
  let fingerprintWindow=NSWindow(contentRect:fingerprintView.frame,styleMask:.titled,backing:.buffered,defer:false)
  fingerprintWindow.isReleasedWhenClosed=false;fingerprintWindow.contentView=fingerprintView;fingerprintView.layoutSubtreeIfNeeded()
  let fingerprintTable=all(fingerprintView).compactMap{$0 as? NSTableView}.first!
  func fingerprintTitles()->[String] {
   (0..<fingerprintTable.numberOfRows).flatMap { row in
    all(fingerprintTable.view(atColumn:0,row:row,makeIfNecessary:true)!).compactMap { ($0 as? NSTextField)?.stringValue }
   }
  }
  let titlesBeforeLive=fingerprintTitles()
  let rowsBeforeLive=fingerprintTable.numberOfRows
  let liveFingerprintTab=fingerprintStore.open("https://fingerprint-live.example.invalid")
  fingerprintStore.updateTab(liveFingerprintTab,title:"Unrelated archive live title")
  drainMain()
  expect(fingerprintTable.numberOfRows==rowsBeforeLive && fingerprintTitles()==titlesBeforeLive,"Unrelated live tab titles do not rebuild Archive rows")
  fingerprintStore.updateTab(liveFingerprintTab,url:"https://fingerprint-live-url.example.invalid")
  drainMain()
  expect(fingerprintTitles()==titlesBeforeLive,"Unrelated live tab URL publishes do not rebuild Archive rows")
  fingerprintNow.addTimeInterval(1)
  let freshlyFingerprinted=fingerprintStore.open("https://fingerprint-fresh.example.invalid")
  fingerprintStore.closeTabs([freshlyFingerprinted])
  drainMain()
  expect(fingerprintTitles().contains("fingerprint-fresh.example.invalid"),"A newly archived tab still reloads the Archive catalog")
  fingerprintWindow.contentView=nil;fingerprintWindow.close()
  let spacesStore=try BrowserStore(directory:directory.appendingPathComponent("spaces-fingerprint",isDirectory:true))
  let spacesView=LibraryView(store:spacesStore,kind:.spaces,profileID:spacesStore.activeSpace.profileID)
  spacesView.frame=NSRect(x:0,y:0,width:800,height:600)
  let spacesWindow=NSWindow(contentRect:spacesView.frame,styleMask:.titled,backing:.buffered,defer:false)
  spacesWindow.isReleasedWhenClosed=false;spacesWindow.contentView=spacesView;spacesView.layoutSubtreeIfNeeded()
  expect(all(spacesView).contains{$0 is SpaceManagerView && !$0.isHidden},"Spaces pane hosts SpaceManagerView")
  let spacesBeforeSettings=all(spacesView).compactMap{$0 as? SpaceManagerView}.first!
  spacesStore.updateSettings { $0.showSpaceHeaderOnSingleUnnamedSpaces = true }
  drainMain()
  expect(all(spacesView).contains{$0 === spacesBeforeSettings && !$0.isHidden},"Settings publishes keep Spaces hosted and force catalog reload admission")
  let liveSpaceTab=spacesStore.open("https://spaces-live-title.example.invalid")
  spacesStore.updateTab(liveSpaceTab,title:"Spaces live title")
  drainMain()
  expect(all(spacesView).contains{$0 === spacesBeforeSettings && !$0.isHidden},"Live tab title publishes still reach Spaces reload")
  spacesWindow.contentView=nil;spacesWindow.close()
  let downloadsFingerprintStore=try BrowserStore(directory:directory.appendingPathComponent("downloads-fingerprint",isDirectory:true))
  let downloadsFingerprintPath=downloadsFingerprintStore.independentEngineProfilePath(for:downloadsFingerprintStore.activeSpace.profileID)
  downloadsFingerprintStore.recordDownload(["id":"dl-fp","profilePath":downloadsFingerprintPath,"name":"dl-fp","status":"downloading","available":true,"itemIdentity":"dl-fp-1","canOpen":false,"receivedBytes":100,"totalBytes":1000,"sourceURL":"https://example.invalid/dl-fp","startedAt":2000])
  let downloadsFingerprintView=DownloadLibraryView(store:downloadsFingerprintStore,ownerValid:{true})
  downloadsFingerprintView.frame=NSRect(x:0,y:0,width:400,height:600)
  let downloadsFingerprintWindow=NSWindow(contentRect:downloadsFingerprintView.frame,styleMask:.titled,backing:.buffered,defer:false)
  downloadsFingerprintWindow.isReleasedWhenClosed=false
  downloadsFingerprintWindow.contentView=downloadsFingerprintView
  downloadsFingerprintView.layoutSubtreeIfNeeded()
  let downloadsFingerprintTable=all(downloadsFingerprintView).compactMap{$0 as? DownloadLibraryTable}.first!
  func downloadsFingerprintLabels()->[String] {
   (0..<downloadsFingerprintTable.numberOfRows).compactMap { downloadsFingerprintTable.view(atColumn:0,row:$0,makeIfNecessary:true)?.accessibilityLabel() }
  }
  let downloadsLabelsBeforeLive=downloadsFingerprintLabels()
  let downloadsRowsBeforeLive=downloadsFingerprintTable.numberOfRows
  let liveDownloadsTab=downloadsFingerprintStore.open("https://downloads-fingerprint-live.example.invalid")
  downloadsFingerprintStore.updateTab(liveDownloadsTab,title:"Unrelated downloads live title")
  drainMain()
  expect(downloadsFingerprintTable.numberOfRows==downloadsRowsBeforeLive && downloadsFingerprintLabels()==downloadsLabelsBeforeLive,"Unrelated live tab titles do not rebuild isolated Downloads rows")
  downloadsFingerprintStore.updateTab(liveDownloadsTab,url:"https://downloads-fingerprint-live-url.example.invalid")
  drainMain()
  expect(downloadsFingerprintLabels()==downloadsLabelsBeforeLive,"Unrelated live tab URL publishes do not rebuild isolated Downloads rows")
  downloadsFingerprintStore.recordDownload(["id":"dl-fp","profilePath":downloadsFingerprintPath,"name":"dl-fp","status":"downloading","available":true,"itemIdentity":"dl-fp-1","canOpen":false,"receivedBytes":100,"totalBytes":1000,"sourceURL":"https://example.invalid/dl-fp","startedAt":2000])
  drainMain()
  expect(downloadsFingerprintLabels()==downloadsLabelsBeforeLive,"Identical Downloads catalog re-publish remains a fingerprint no-op")
  downloadsFingerprintStore.recordDownload(["id":"dl-fp","profilePath":downloadsFingerprintPath,"name":"dl-fp","status":"downloading","available":true,"itemIdentity":"dl-fp-1","canOpen":false,"receivedBytes":700,"totalBytes":1000,"sourceURL":"https://example.invalid/dl-fp","startedAt":2000])
  drainMain()
  expect(downloadsFingerprintLabels() != downloadsLabelsBeforeLive,"Progress byte flips still reload Downloads through the store sink")
  let downloadsLabelsAfterProgress=downloadsFingerprintLabels()
  downloadsFingerprintStore.recordDownload(["id":"dl-fp-new","profilePath":downloadsFingerprintPath,"name":"dl-fp-new","status":"completed","available":true,"itemIdentity":"dl-fp-new-1","canOpen":true,"canCopyFile":true,"sourceURL":"https://example.invalid/dl-fp-new","startedAt":2001])
  drainMain()
  expect(downloadsFingerprintLabels().contains{ $0.contains("dl-fp-new") },"A new download membership still reloads the Downloads catalog")
  expect(downloadsFingerprintLabels() != downloadsLabelsAfterProgress,"Membership change is distinct from the prior progress fingerprint")
  downloadsFingerprintWindow.contentView=nil;downloadsFingerprintWindow.close()
  archiveTable.selectRowIndexes(IndexSet(integer:otherRow),byExtendingSelection:false)
  let groupMenu=archiveMenu(groupRow)
  expect(groupMenu.items.map(\.title)==["Restore","Delete","","Clear Archive…"],"Archive row offers its direct actions, then Clear Archive")
  expect(archiveTable.selectedRowIndexes==IndexSet(integer:otherRow),"Archive row menu preserves the independent selection")
  invoke(groupMenu.items[0]);expect(restored.count==1 && restored[0].0==[groupA] && restored[0].1==originalSpace,"Restore dispatches the invoked original grouped row and previous Space")
  ownerValid=false;invoke(groupMenu.items[0]);invoke(groupMenu.items[1]);ownerValid=true
  expect(restored.count==1 && menuStore.archivedItems(profileID:menuProfile).count==2,"Retired window/Profile owner refuses both retained actions")
  menuView.show(.downloads);menuView.show(.archive);invoke(groupMenu.items[1])
  expect(menuStore.archivedItems(profileID:menuProfile).count==2,"Leaving and returning to Archive permanently refuses the retained action")
  let movedMenu=archiveMenu(archiveRow("group-a.example.invalid"))
  menuWindow.contentView=nil
  let newMenuWindow=NSWindow(contentRect:menuView.frame,styleMask:.titled,backing:.buffered,defer:false)
  newMenuWindow.isReleasedWhenClosed=false;newMenuWindow.contentView=menuView
  invoke(movedMenu.items[1]);expect(menuStore.archivedItems(profileID:menuProfile).count==2,"Moving the view to another physical window refuses the old menu")
  newMenuWindow.contentView=nil;menuWindow.contentView=menuView;menuView.layoutSubtreeIfNeeded()
  invoke(movedMenu.items[1]);expect(menuStore.archivedItems(profileID:menuProfile).count==2,"Returning to the original window does not revive its old menu")
  let staleGroup=archiveMenu(archiveRow("group-a.example.invalid"))
  menuStore.deleteArchivedTabs([groupB],profileID:menuProfile)
  invoke(staleGroup.items[1]);expect(menuStore.state.tabs.contains{$0.id==groupA && $0.archivedAt != nil},"A changed group cannot delete its surviving member")
  let otherMenu=archiveMenu(archiveRow("other.example.invalid"))
  _ = menuStore.restoreArchivedTab(other,profileID:menuProfile,destination:.previousSpace(fallbackSpaceID:originalSpace))
  menuStore.closeTabs([other])
  invoke(otherMenu.items[1]);expect(menuStore.state.tabs.contains{$0.id==other && $0.archivedAt == archiveNow},"A rearchived replacement with the same ID and timestamp survives the old action")
  let hoverTab=menuStore.open("https://hover-only.example.invalid");menuStore.closeTabs([hoverTab]);drainMain();menuView.layoutSubtreeIfNeeded()
  let hoverHost=DownloadHoverWindow(contentRect:menuView.frame,styleMask:.borderless,backing:.buffered,defer:false)
  hoverHost.isReleasedWhenClosed=false;hoverHost.key=true
  menuWindow.contentView=nil;hoverHost.contentView=menuView;menuView.layoutSubtreeIfNeeded()
  let hoverIndex=archiveRow("hover-only.example.invalid")
  let hoverItem=menuStore.archivedItems(profileID:menuProfile).first{$0.urls.contains("https://hover-only.example.invalid")}!
  func point(of row:Int)->NSPoint { archiveTable.convert(NSPoint(x:archiveTable.rect(ofRow:row).midX,y:archiveTable.rect(ofRow:row).midY),to:nil) }
  func moveHover(_ row:Int) {
   hoverHost.pointer=point(of:row)
   let event=NSEvent.mouseEvent(with:.mouseMoved,location:hoverHost.pointer,modifierFlags:[],timestamp:0,windowNumber:hoverHost.windowNumber,context:nil,eventNumber:2,clickCount:0,pressure:0)!
   archiveTable.mouseMoved(with:event)
  }
  func shownActions(_ row:Int)->[NSButton] {
   all(archiveTable.view(atColumn:0,row:row,makeIfNecessary:true)!).compactMap{$0 as? NSButton}.filter{!$0.isHidden}
  }
  expect(archiveTable.view(atColumn:0,row:hoverIndex,makeIfNecessary:true)!.accessibilityCustomActions()?.map(\.name)==["Put Back","Delete"],"VoiceOver reaches Put Back and Delete without hovering")
  moveHover(hoverIndex)
  expect(Set(shownActions(hoverIndex).compactMap{$0.accessibilityLabel()})==["Delete","Put Back"],"Hovering a live Archive row shows trash and put-back")
  let headingRow=(0..<archiveTable.numberOfRows).first{menuView.tableView(archiveTable,isGroupRow:$0)}!
  moveHover(headingRow)
  expect(shownActions(headingRow).isEmpty,"A heading shows neither trash nor put-back")
  moveHover(hoverIndex)
  menuView.archiveOwnerValid={false}
  shownActions(hoverIndex).first{$0.accessibilityLabel()=="Put Back"}!.performClick(nil)
  expect(!restored.contains{$0.0==[hoverItem.id]},"Put Back does nothing when this window no longer owns the Archive")
  menuView.archiveOwnerValid={true}
  shownActions(hoverIndex).first{$0.accessibilityLabel()=="Put Back"}!.performClick(nil)
  expect(restored.contains{$0.0==[hoverItem.id] && $0.1==originalSpace},"Put Back records the live archived item and its Space")
  shownActions(hoverIndex).first{$0.accessibilityLabel()=="Delete"}!.performClick(nil)
  expect(!menuStore.archivedItems(profileID:menuProfile).contains{$0.id==hoverItem.id},"Trash removes that live archive record")
  hoverHost.contentView=nil;menuWindow.contentView=menuView;hoverHost.close()
  let directStore=try BrowserStore(directory:directory.appendingPathComponent("archive-direct",isDirectory:true))
  let directProfile=directStore.activeSpace.profileID
  let directA=directStore.open("https://direct-a.example.invalid"),directB=directStore.open("https://direct-b.example.invalid")
  directStore.setSplit([directA,directB]);directStore.closeTabs([directA,directB])
  let directView=LibraryView(store:directStore,kind:.archive,profileID:directProfile)
  directView.archiveOwnerValid={true};directView.frame=menuView.frame
  let directWindow=NSWindow(contentRect:directView.frame,styleMask:.titled,backing:.buffered,defer:false)
  directWindow.isReleasedWhenClosed=false;directWindow.contentView=directView;directView.layoutSubtreeIfNeeded()
  let directTable=all(directView).compactMap{$0 as? NSTableView}.first!
  let directRow=(0..<directTable.numberOfRows).first{directTable.delegate?.tableView?(directTable,shouldSelectRow:$0) == true}!
  let directPoint=directTable.convert(NSPoint(x:20,y:directTable.rect(ofRow:directRow).midY),to:nil)
  let directEvent=NSEvent.mouseEvent(with:.rightMouseDown,location:directPoint,modifierFlags:[],timestamp:0,windowNumber:directWindow.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
  let directMenu=directTable.menu(for:directEvent)!
  invoke(directMenu.items[1])
  expect(directWindow.attachedSheet == nil && directStore.archivedItems(profileID:directProfile).isEmpty,"Delete directly removes the entire original group without a confirmation sheet")
  menuWindow.contentView=nil;menuWindow.close();newMenuWindow.close();directWindow.contentView=nil;directWindow.close()
  let filterStore=try BrowserStore(directory:directory.appendingPathComponent("filter",isDirectory:true))
  let filterDefault=filterStore.state.profiles[0].id
  let secondProfile=filterStore.createProfile(name:"Second Profile")
  let filterPath=filterStore.independentEngineProfilePath(for:filterDefault)
  let secondPath=filterStore.independentEngineProfilePath(for:secondProfile)
  func filterPublish(_ id:String,_ path:String) {
   filterStore.recordDownload(["id":id,"profilePath":path,"name":id,"status":"completed","available":true,"itemIdentity":id+"1","canOpen":true,"startedAt":1000])
  }
  filterPublish("z-original",filterPath);filterPublish("a-later",filterPath);filterPublish("other",secondPath)
  var filterClosed=0
  let filterView=DownloadLibraryView(store:filterStore,ownerValid:{true})
  filterView.frame=NSRect(x:0,y:0,width:304,height:600)
  let filterWindow=DownloadHoverWindow(contentRect:filterView.frame,styleMask:[.titled],backing:.buffered,defer:false)
  filterWindow.isReleasedWhenClosed=false;filterWindow.contentView=filterView
  filterView.onClose={filterClosed += 1}
  filterView.layoutSubtreeIfNeeded()
  let filterSearch=all(filterView).compactMap{$0 as? NSTextField}.first{$0.accessibilityLabel()=="Search Downloads"}!
  let filterTable=all(filterView).compactMap{$0 as? DownloadLibraryTable}.first!
  expect(!all(filterView).compactMap{$0 as? NSButton}.contains{$0.title=="Filter" || $0.title=="Done"},"Downloads has no Filter control now that profiles are invisible")
  expect(!all(filterView).compactMap{$0 as? NSTextField}.contains{$0.stringValue=="Profiles"},"Downloads shows no Profiles heading")
  let searchBackground=filterView.subviews.first!
  expect(abs(filterSearch.frame.midY-searchBackground.bounds.midY)<=0.5 && filterSearch.frame.height==filterSearch.cell!.cellSize.height,"Plain native editor line stays centered in the original header surface")
  expect(searchBackground.frame.height==36 && searchBackground.bounds.contains(filterSearch.frame) && !searchBackground.isAccessibilityElement() && !searchBackground.isAccessibilityHidden(),"Search padding keeps the full header hit area without introducing a second accessibility control")
  let searchGlyph=searchBackground.subviews.compactMap{$0 as? NSImageView}.first!
  expect(filterSearch is DownloadSearchField && !(filterSearch.cell is NSSearchFieldCell),"Actual query uses a plain native field without duplicate search/clear accessories")
  expect(filterSearch.textColor == .labelColor && filterSearch.placeholderAttributedString?.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor == .placeholderTextColor,
         "Typed query is primary while the placeholder keeps the system placeholder grey")
  expect(searchBackground.frame.minX==8 && searchBackground.frame.minY==10 && searchBackground.frame.maxX==filterView.bounds.width-8 && searchBackground.frame.height==36,
         "Header: 8pt page inset and a full-width 36pt search field")
  expect(filterSearch.font?.pointSize==14 && !filterSearch.isBezeled && !filterSearch.drawsBackground && filterSearch.focusRingType == .none,"Native editor has original typography without system bezel/focus shadow")
  let optical=searchGlyph.image!.alignmentRect
  expect(optical.size==NSSize(width:15,height:15) && searchGlyph.frame.size==searchGlyph.image!.size && optical.minX>=1 && optical.minY>=1
         && searchGlyph.image!.size.width>=optical.maxX+1 && searchGlyph.image!.size.height>=optical.maxY+1,
         "Magnifier keeps a 15-point optical box inside a canvas with margin so the stroke is not clipped")
  expect(abs(searchGlyph.frame.minX+optical.minX-14.5)<0.01 && abs(searchGlyph.frame.minX+optical.maxX+11.5-filterSearch.frame.minX)<0.01,
         "Separate magnifier and editor retain original inset/spacing without overlap")
  expect(!all(searchBackground).contains{$0 is NSButton},"Typed query has no invented clear or search-history action")
  let headerPoint=NSPoint(x:searchBackground.frame.minX+searchGlyph.frame.midX,y:searchBackground.frame.minY+searchGlyph.frame.midY)
  expect(searchBackground.hitTest(headerPoint) === searchBackground,"Passive magnifier forwards pointer focus to the original search surface")
  func visibleNames()->[String] {(0..<filterTable.numberOfRows).compactMap{row in
   guard let cell=filterView.tableView(filterTable,viewFor:filterTable.tableColumns[0],row:row) as? NSTableCellView else{return nil}
   return all(cell).compactMap{$0 as? NSTextField}.first?.stringValue
  }}
  expect(visibleNames()==filterStore.downloadItems.map(\.name),"Equal original dates retain source order rather than lexical record IDs")
  expect(visibleNames().count==3,"Downloads from every profile appear in one list")
  searchBackground.appearance=NSAppearance(named:.aqua);searchBackground.updateLayer()
  let lightSurface=NSColor(cgColor:searchBackground.layer!.backgroundColor!)!.usingColorSpace(.deviceRGB)!
  expect(lightSurface.redComponent<0.1 && abs(lightSurface.alphaComponent-0.05)<0.001,"Semantic search surface resolves in its actual light view appearance")
  searchBackground.appearance=NSAppearance(named:.darkAqua);searchBackground.updateLayer()
  let darkSurface=NSColor(cgColor:searchBackground.layer!.backgroundColor!)!.usingColorSpace(.deviceRGB)!
  expect(darkSurface.redComponent>0.9 && abs(darkSurface.alphaComponent-0.05)<0.001,"Appearance changes re-resolve semantic ink without retaining an earlier light color")
  searchBackground.appearance=nil;searchBackground.updateLayer()
  let hoverEvent=NSEvent.mouseEvent(with:.mouseMoved,location:.zero,modifierFlags:[],timestamp:0,windowNumber:filterWindow.windowNumber,context:nil,eventNumber:0,clickCount:0,pressure:0)!
  filterWindow.pointer=searchBackground.convert(NSPoint(x:20,y:18),to:nil)
  searchBackground.mouseMoved(with:hoverEvent);searchBackground.updateLayer()
  expect(abs(NSColor(cgColor:searchBackground.layer!.backgroundColor!)!.alphaComponent-0.1)<0.001,"Actual same-window pointer hit raises only original surface opacity")
  filterWindow.pointer=NSPoint(x:1000,y:1000)
  searchBackground.updateTrackingAreas();searchBackground.updateLayer()
  expect(abs(NSColor(cgColor:searchBackground.layer!.backgroundColor!)!.alphaComponent-0.05)<0.001,"Replacing tracking resamples the current original pointer instead of retaining old hover")
  filterWindow.pointer=searchBackground.convert(NSPoint(x:20,y:18),to:nil)
  searchBackground.mouseMoved(with:hoverEvent);searchBackground.updateLayer()
  let staleHover=NSEvent.enterExitEvent(with:.mouseEntered,location:.zero,modifierFlags:[],timestamp:0,windowNumber:filterWindow.windowNumber,context:nil,eventNumber:0,trackingNumber:0,userData:nil)!
  searchBackground.mouseExited(with:staleHover);searchBackground.updateLayer()
  expect(abs(NSColor(cgColor:searchBackground.layer!.backgroundColor!)!.alphaComponent-0.1)<0.001,"An obsolete tracking exit cannot clear a newer original hover")
  filterWindow.key=false
  NotificationCenter.default.post(name:NSWindow.didResignKeyNotification,object:filterWindow)
  searchBackground.mouseEntered(with:staleHover);searchBackground.updateLayer()
  expect(abs(NSColor(cgColor:searchBackground.layer!.backgroundColor!)!.alphaComponent-0.05)<0.001,"Key resignation and stale queued entry cannot retain or reassert hover")
  filterWindow.key=true;filterWindow.pointer=NSPoint(x:1000,y:1000)
  searchBackground.mouseMoved(with:hoverEvent);searchBackground.updateLayer()
  expect(abs(NSColor(cgColor:searchBackground.layer!.backgroundColor!)!.alphaComponent-0.05)<0.001,"Current outside hit restores original idle opacity without a delayed effect")
  filterSearch.stringValue="original"
  filterWindow.makeFirstResponder(filterSearch)
  let filterEditor=filterSearch.currentEditor() as! NSTextView
  filterEditor.setSelectedRange(NSRange(location:2,length:3))
  let surfaceClick=NSEvent.mouseEvent(with:.leftMouseDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:filterWindow.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
  searchBackground.mouseDown(with:surfaceClick)
  expect(filterSearch.currentEditor() === filterEditor && filterEditor.selectedRange()==NSRange(location:2,length:3),"Original background focus preserves the already editing query range")
  filterWindow.makeFirstResponder(filterSearch)
  let composingFilter=filterSearch.currentEditor() as! NSTextView
  composingFilter.setMarkedText("input",selectedRange:NSRange(location:5,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
  searchBackground.mouseDown(with:surfaceClick)
  expect(composingFilter.hasMarkedText(),"Search surface pointer focus never commits or replaces original IME composition")
  composingFilter.unmarkText();filterSearch.stringValue="original"
  filterWindow.makeFirstResponder(filterTable)
  filterView.cancelOperation(nil)
  expect(filterSearch.stringValue.isEmpty && filterClosed==0,"Escape clears only search")
  filterView.cancelOperation(nil);expect(filterClosed==1,"Only subsequent empty-state Escape exits Library")
  filterWindow.close()
  var subtitleItem=BrowserDownload(id:"subtitle",name:"photo.png",path:"",receivedBytes:1000000,totalBytes:2000000,status:.completed)
  subtitleItem.sourceURL="https://files.example.co.uk/photo.png";subtitleItem.sourceDomain="example.co.uk"
  expect(DownloadRowSubtitle.text(for:subtitleItem)=="Image from example.co.uk","Completed image names its type and source domain")
  for (ext,title) in [("dmg","Disk Image"),("pdf","PDF"),("mov","Movie"),("mp3","Audio"),("zip","Zip Archive"),("tar","Archive"),("unknown-parc","Download")] {
   subtitleItem.name="original."+ext
   expect(DownloadRowSubtitle.kind(for:subtitleItem)==title,"Original supported file category "+ext)
  }
  subtitleItem.name="original";subtitleItem.mimeType="image/png"
  expect(DownloadRowSubtitle.kind(for:subtitleItem)=="Image","Actual MIME provides type when no extension exists")
  subtitleItem.status = .paused
  expect(DownloadRowSubtitle.text(for:subtitleItem)=="Paused · from example.co.uk","Pause uses original source, without replacing it with byte count")
  subtitleItem.status = .cancelled
  expect(DownloadRowSubtitle.text(for:subtitleItem)=="Cancelled · from example.co.uk","Canceled original retains its source")
  subtitleItem.status = .failed;subtitleItem.statusText="Network connection interrupted"
  expect(DownloadRowSubtitle.text(for:subtitleItem)=="Failed to Download","Ordinary failure uses the reference row label")
  subtitleItem.status = .completed;subtitleItem.fileMissing=true
  expect(DownloadRowSubtitle.text(for:subtitleItem)=="File deleted or moved","Missing completed original has the explicit missing-file subtitle")
  subtitleItem.fileMissing=false;subtitleItem.requiresReview=true;subtitleItem.statusText="This file may be dangerous"
  expect(DownloadRowSubtitle.text(for:subtitleItem)=="This file may be dangerous","Actual security text overrides ordinary presentation")
  subtitleItem.requiresReview=false;subtitleItem.status = .downloading;subtitleItem.openWhenComplete=true;subtitleItem.receivedBytes=1299999
  expect(DownloadRowSubtitle.text(for:subtitleItem)=="Opening… (64%)","Open-on-finish displays truncated actual progress")
  subtitleItem.totalBytes=0
  expect(DownloadRowSubtitle.text(for:subtitleItem).isEmpty,"Unknown total does not invent an opening percentage")
  subtitleItem.totalBytes=2000000;subtitleItem.receivedBytes=1000000;subtitleItem.openWhenComplete=false
  let format=ByteCountFormatter();format.allowedUnits=[.useKB,.useMB,.useGB,.useTB];format.includesUnit=true;format.isAdaptive=true;format.allowsNonnumericFormatting=true;format.zeroPadsFractionDigits=true
  let received=format.string(fromByteCount:1000000),total=format.string(fromByteCount:2000000)
  let head=received.prefix(upTo:received.lastIndex(where:\.isWhitespace)!)
  expect(DownloadRowSubtitle.text(for:subtitleItem)==String(head)+"/"+total,"Progress elides only the duplicated matching unit")
  subtitleItem.receivedBytes=1000
  expect(DownloadRowSubtitle.text(for:subtitleItem)==format.string(fromByteCount:1000)+"/"+total,"Different byte magnitudes retain both units")
  subtitleItem.timeRemaining=120
  let remaining=DateComponentsFormatter();remaining.unitsStyle = .abbreviated;remaining.zeroFormattingBehavior = .dropAll;remaining.allowedUnits=[.day,.hour,.minute,.second]
  expect(DownloadRowSubtitle.text(for:subtitleItem).hasSuffix(" · "+remaining.string(from:120)!),"Actual time estimate uses the recovered Foundation duration")
  subtitleItem.timeRemaining = .nan
  expect(!DownloadRowSubtitle.text(for:subtitleItem).contains(" · "),"Nonfinite estimates cannot reach formatter")
  subtitleItem.receivedBytes=0;subtitleItem.timeRemaining=nil
  expect(DownloadRowSubtitle.text(for:subtitleItem).isEmpty,"Zero-byte progress does not manufacture a size")
  var subtitleSnapshot:[String:Any] = ["name":"photo.png","status":"downloading","available":true,"itemIdentity":"source","sourceDomain":"example.co.uk","mimeType":"image/png","timeRemaining":120.0]
  let liveSubtitle=BrowserDownload.snapshot(subtitleSnapshot,id:"s",nativeID:"s",profileID:profile)
  expect(liveSubtitle.timeRemaining==120 && liveSubtitle.mimeType=="image/png" && liveSubtitle.sourceDomain=="example.co.uk","Native original snapshot metadata reaches the real row model")
  let restoredSubtitle=try JSONDecoder().decode(BrowserDownload.self,from:JSONEncoder().encode(liveSubtitle))
  expect(restoredSubtitle.timeRemaining==nil && restoredSubtitle.mimeType==nil && restoredSubtitle.sourceDomain==nil,"A disk-restored record cannot advertise a live estimate")
  for invalid in [-1.0,0,.infinity,.nan] {
   subtitleSnapshot["timeRemaining"]=invalid
   expect(BrowserDownload.snapshot(subtitleSnapshot,id:"s",nativeID:"s",profileID:profile).timeRemaining==nil,"Invalid native estimate is absent")
  }
  subtitleSnapshot["available"]=false;subtitleSnapshot["timeRemaining"]=30
  expect(BrowserDownload.snapshot(subtitleSnapshot,id:"s",nativeID:"s",profileID:profile).timeRemaining==nil,"Retired native manager cannot publish estimated remaining time")
  let headingCalendar=Calendar.current
  let headingNow=Date()
  let headingFormatter=RelativeDateTimeFormatter();headingFormatter.unitsStyle = .full
  func heading(_ date:Date)->String { DownloadSectionHeading.title(for:date,now:headingNow) }
  let headingYesterday=headingCalendar.date(byAdding:.day,value:-1,to:headingNow)!
  let headingOlder=headingNow.addingTimeInterval(-3*86400)
  expect(heading(headingNow)=="Today" && heading(headingYesterday)=="Yesterday",
         "Today and Yesterday follow calendar checks on the item's own date")
  expect(heading(headingOlder)==headingFormatter.localizedString(for:headingOlder,relativeTo:headingNow)
         && heading(headingOlder) != "Today" && heading(headingOlder) != "Yesterday",
         "Older downloads use the relative formatter on the item's own timestamp")
  var splitCalendar=Calendar(identifier:.gregorian);splitCalendar.timeZone=TimeZone(identifier:"UTC")!
  let splitNow=splitCalendar.date(from:DateComponents(year:2025,month:1,day:15,hour:12))!
  let splitDay=splitCalendar.date(byAdding:.day,value:-4,to:splitCalendar.startOfDay(for:splitNow))!
  var splitPair:(Date,Date)?
  for early in 0..<24 {
   for late in (early+1)..<24 {
    let first=splitDay.addingTimeInterval(Double(early)*3600), second=splitDay.addingTimeInterval(Double(late)*3600)
    if DownloadSectionHeading.title(for:first,now:splitNow) != DownloadSectionHeading.title(for:second,now:splitNow) { splitPair=(first,second); break }
   }
   if splitPair != nil { break }
  }
  expect(splitPair != nil,"Per-timestamp titles can split one calendar day")
  let sectionStore=try BrowserStore(directory:directory.appendingPathComponent("sections",isDirectory:true))
  let sectionPath=sectionStore.independentEngineProfilePath(for:sectionStore.state.profiles[0].id)
  let sectionNow=Date()
  let sectionDates:[(String,TimeInterval?)]=[
   ("today-late",sectionNow.timeIntervalSince1970),
   ("today-early",sectionNow.addingTimeInterval(-1).timeIntervalSince1970),
   ("yesterday",headingCalendar.date(byAdding:.day,value:-1,to:sectionNow)!.timeIntervalSince1970),
   ("older",sectionNow.addingTimeInterval(-10*86400).timeIntervalSince1970),
   ("undated",nil)]
  for sample in sectionDates {
   var record:[String:Any]=["id":sample.0,"profilePath":sectionPath,"name":sample.0,"status":"completed","available":true,
    "itemIdentity":sample.0,"canRemove":true,"sourceURL":"https://example.invalid/"+sample.0,"receivedBytes":1,"totalBytes":1]
   if let started=sample.1 { record["startedAt"]=started }
   sectionStore.recordDownload(record)
  }
  let sectionView=DownloadLibraryView(store:sectionStore,ownerValid:{true})
  let sectionWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:700),styleMask:[.titled],backing:.buffered,defer:false)
  sectionWindow.contentView=sectionView;sectionView.frame=sectionWindow.contentView!.bounds
  defer {sectionView.invalidate();sectionWindow.contentView=nil}
  sectionView.layoutSubtreeIfNeeded()
  let sectionTable=all(sectionView).compactMap{$0 as? DownloadLibraryTable}.first!
  let sectionHeadings=(0..<sectionTable.numberOfRows).compactMap{row->String? in
   guard let cell=sectionTable.view(atColumn:0,row:row,makeIfNecessary:true) as? DownloadSectionHeading else { return nil }
   return all(cell).compactMap{$0 as? NSTextField}.first?.stringValue
  }
  let sectionOrdered=sectionDates.map{_,started->(Date,String) in
   let date=started.map{Date(timeIntervalSince1970:$0)}
   return (date ?? .distantPast, date.map{heading($0)} ?? DownloadSectionHeading.undatedTitle)
  }.sorted{$0.0>$1.0}
  var expectedHeadings:[String]=[], previousHeading:String?
  for entry in sectionOrdered where entry.1 != previousHeading { expectedHeadings.append(entry.1); previousHeading=entry.1 }
  expect(sectionHeadings==expectedHeadings && expectedHeadings.last==DownloadSectionHeading.undatedTitle
         && expectedHeadings.first=="Today" && expectedHeadings.contains("Yesterday")
         && expectedHeadings.contains{$0 != "Today" && $0 != "Yesterday" && $0 != DownloadSectionHeading.undatedTitle},
         "Sections follow each item's own section title, and an undated download is Earlier at the bottom; got \(sectionHeadings), expected \(expectedHeadings)")
  expect(sectionHeadings.filter{$0=="Today"}.count==1,"Items that share a title share one section")
  let layoutStore=try BrowserStore(directory:directory.appendingPathComponent("layout",isDirectory:true))
  let layoutProfile=layoutStore.state.profiles[0].id, layoutPath=layoutStore.independentEngineProfilePath(for:layoutProfile)
  let now=Calendar.current.startOfDay(for:Date()).addingTimeInterval(12*3600).timeIntervalSince1970
  let fixtures:[(String,String,String,Int64,Int64)]=[
   ("image","Mountain photograph.png","completed",2400000,2400000),
   ("active","Project resources.zip","downloading",52000000,100000000),
   ("paused","Reference video.mov","paused",7000000,12000000),
   ("failed","Document.pdf","failed",0,0)]
  for (index,fixture) in fixtures.enumerated() {
   layoutStore.recordDownload(["id":fixture.0,"profilePath":layoutPath,"name":fixture.1,"status":fixture.2,
    "available":true,"itemIdentity":fixture.0,"canOpen":fixture.2=="completed","canReveal":fixture.2=="completed",
    "canCopyFile":fixture.2=="completed","canPause":fixture.2=="downloading","canResume":fixture.2=="paused",
    "canRetry":fixture.2=="failed","canCancel":fixture.2=="downloading","canRemove":true,
    "sourceURL":"https://example.invalid/"+fixture.0,"startedAt":now-Double(index*60),
    "receivedBytes":fixture.3,"totalBytes":fixture.4])
  }
  let layoutView=DownloadLibraryView(store:layoutStore,ownerValid:{true})
  let layoutWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:590),styleMask:[.titled],backing:.buffered,defer:false)
  layoutWindow.contentView=layoutView;layoutView.frame=NSRect(x:0,y:0,width:400,height:590)
  defer {layoutView.invalidate();layoutWindow.contentView=nil}
  layoutView.layoutSubtreeIfNeeded()
  let layoutTable=all(layoutView).compactMap{$0 as? DownloadLibraryTable}.first!
  let layoutSearch=all(layoutView).compactMap{$0 as? NSTextField}.first{$0.accessibilityLabel()=="Search Downloads"}!
  expect(!all(layoutView).compactMap{$0 as? NSTextField}.contains{$0.stringValue=="4 downloads"},
         "Downloads has no fabricated count footer")
  let todayHeading=layoutTable.view(atColumn:0,row:0,makeIfNecessary:true)!
  expect(todayHeading is DownloadSectionHeading && all(todayHeading).compactMap{$0 as? NSTextField}.first?.stringValue=="Today",
         "A download from today uses the Today heading")
  let completedIcon=all(layoutTable.view(atColumn:0,row:1,makeIfNecessary:true)!).compactMap{$0 as? NSImageView}.first{$0.frame.width==24}!
  expect(completedIcon.frame==NSRect(x:20,y:16,width:24,height:24),"Completed file row uses the 24-point file image, not the empty placeholder")
  let layoutScroll=layoutTable.enclosingScrollView!, idleListHeight=layoutScroll.frame.height
  func statusLine()->NSTextField? {
   all(layoutView).compactMap{$0 as? NSTextField}.first{!$0.isHidden && ($0.stringValue.hasPrefix("Loading ") || $0.stringValue=="Profile unavailable")}
  }
  expect(statusLine()==nil && idleListHeight==layoutView.bounds.height-layoutScroll.frame.minY,"Idle Downloads list reaches the bottom with no status line")
  layoutView.setLoading(count:1,message:nil);layoutView.layoutSubtreeIfNeeded()
  expect(statusLine()?.stringValue=="Loading downloads…" && layoutScroll.frame.height==idleListHeight-36,
         "Loading shows the bottom status line and shortens the list")
  layoutView.setLoading(count:0,message:"Profile unavailable");layoutView.layoutSubtreeIfNeeded()
  expect(statusLine()?.stringValue=="Profile unavailable" && layoutScroll.frame.height==idleListHeight-36,
         "A load failure keeps the status line and the shortened list")
  layoutView.setLoading(count:0,message:nil);layoutView.layoutSubtreeIfNeeded()
  expect(statusLine()==nil && layoutScroll.frame.height==idleListHeight,"Clearing the status restores the full list height")
  let originalCell=layoutTable.view(atColumn:0,row:1,makeIfNecessary:true)!
  layoutView.setLoading(count:0,message:nil)
  expect(layoutTable.view(atColumn:0,row:1,makeIfNecessary:true)===originalCell,"Unchanged publication preserves existing native row and thumbnail owner")
  layoutSearch.stringValue="example";layoutView.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification))
  let refreshedCell=layoutTable.view(atColumn:0,row:1,makeIfNecessary:true)!
  expect(refreshedCell !== originalCell,"Identical rows under new search context receive current action and thumbnail leases")
  layoutTable.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
  var layoutActions=0;layoutView.onAction={_,_ in layoutActions += 1;return true}
  let reveal=layoutTable.makeMenu!()!.items.first{$0.title=="Show in Finder"}!
  invoke(reveal)
  expect(layoutActions==1,"Rebuilt original cell routes actual current command after context change")
  layoutSearch.stringValue="";layoutView.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification))
  layoutView.layoutSubtreeIfNeeded()
  func updateActive(_ status:String="downloading",bytes:Int64=60000000,identity:String="active",review:Bool=false,total:Int64=100000000) {
   layoutStore.recordDownload(["id":"active","profilePath":layoutPath,"name":"Project resources.zip","status":status,
    "available":true,"itemIdentity":identity,"canPause":status=="downloading","canResume":status=="paused",
    "canCancel":status=="downloading","canRemove":true,"requiresReview":review,"canReview":review,
    "sourceURL":"https://example.invalid/active","startedAt":now-60,"receivedBytes":bytes,"totalBytes":total])
   layoutView.setLoading(count:0,message:nil);layoutView.layoutSubtreeIfNeeded()
  }
  let activeCell=layoutTable.view(atColumn:0,row:2,makeIfNecessary:true)!
  activeCell.layoutSubtreeIfNeeded()
  let activeBadge=all(activeCell).compactMap{$0 as? DownloadActivityBadge}.first!
  let activeIcon=activeCell.subviews.compactMap{$0 as? NSImageView}.first!
  expect(activeBadge.activity?.progress==0.52 && !activeBadge.isHidden && activeIcon.isHidden,"In-progress original uses circular leading badge instead of fallback icon")
  expect(activeBadge.frame==NSRect(x:16,y:12,width:28,height:32),"Progress preserves actual32-point slot with4-point trailing padding")
  expect(all(activeCell).allSatisfy{!($0 is NSProgressIndicator)},"No provisional bottom progress bar remains")
  let animationOwner=activeBadge.subviews.first!
  expect(!animationOwner.isAccessibilityElement() && animationOwner.accessibilityChildren()?.isEmpty==true,"Progress artwork does not introduce a second accessible control")
  layoutTable.selectRowIndexes(IndexSet(integer:2),byExtendingSelection:false)
  let moreControl=activeCell.subviews.compactMap{$0 as? NSButton}.first{$0.parcTooltip?.label=="More download actions"}!
  expect(activeCell.subviews.compactMap{$0 as? NSButton}.count==1,"Original DownloadCell has one More control instead of provisional inline actions")
  let pauseMenu=layoutTable.makeMenu!()!.items.first{$0.title=="Pause"}!
  expect(pauseMenu.isEnabled,"Original manager Pause remains available in captured-item menu")
  layoutWindow.makeFirstResponder(moreControl)
  moreControl.mouseEntered(with:NSEvent.enterExitEvent(with:.mouseEntered,location:.zero,modifierFlags:[],timestamp:0,windowNumber:layoutWindow.windowNumber,context:nil,eventNumber:0,trackingNumber:0,userData:nil)!)
  let moreHoverInk=moreControl.contentTintColor
  updateActive()
  expect(moreControl.contentTintColor==moreHoverInk,"Original More keeps its actual hover color during progress publication")
  expect(layoutTable.view(atColumn:0,row:2,makeIfNecessary:true)===activeCell && activeBadge.subviews.first===animationOwner,"Real progress publication retains original row and SwiftUI animation state")
  expect(activeBadge.activity?.progress==0.6 && layoutWindow.firstResponder===moreControl,"Same original More control retains native focus while progress changes")
  updateActive("paused")
  expect(activeBadge.activity==nil && activeBadge.subviews.isEmpty && activeIcon.isHidden,"Paused branch removes animated artwork and has the recovered empty leading view")
  expect(layoutWindow.firstResponder===moreControl,"Status change retains the original selected More focus owner")
  let resumeMenu=layoutTable.makeMenu!()!.items.first{$0.title=="Resume"}!
  expect(resumeMenu.isEnabled && !layoutTable.makeMenu!()!.items.contains{$0.title=="Pause"},"Paused state replaces menu capability without inventing a new inline control")
  updateActive("pending")
  expect(activeBadge.activity==nil && !activeIcon.isHidden,"Not-started branch uses fallback artwork rather than active progress")
  updateActive(total:0)
  expect(activeBadge.activity?.progress==nil && !activeBadge.isHidden,"Unknown total remains truthful while shared badge supplies its indeterminate artwork")
  updateActive(review:true)
  expect(activeBadge.activity==nil && !activeIcon.isHidden,"Chromium security review retains its visible shield/status instead of ordinary progress")
  let reviewMenu=layoutTable.makeMenu!()!.items.first{$0.title=="Review…"}!
  expect(reviewMenu.isEnabled,"Required Chromium Review remains connected to genuine captured-item consent")
  updateActive()
  let completedOwner=activeBadge.subviews.first!
  updateActive("completed",bytes:100000000)
  expect(activeBadge.activity==nil && activeBadge.subviews.isEmpty && completedOwner.superview==nil && !activeIcon.isHidden,"Completed row exits progress immediately without the entry-only delayed retirement")
  updateActive()
  layoutView.invalidate()
  expect(activeBadge.activity==nil && activeBadge.subviews.isEmpty,"Library invalidation retires visible original row animation even while attached")
  layoutView.setLoading(count:0,message:nil);layoutView.layoutSubtreeIfNeeded()
  let revivedCell=layoutTable.view(atColumn:0,row:2,makeIfNecessary:true)!
  let revivedBadge=all(revivedCell).compactMap{$0 as? DownloadActivityBadge}.first!
  expect(revivedCell !== activeCell && revivedBadge.activity != nil,"Reopened context obtains a new row-owned animation lease")
  updateActive(identity:"replacement")
  expect(revivedBadge.activity==nil && revivedBadge.subviews.isEmpty,"Replacement incarnation detaches and retires original badge")
  let replacementCell=layoutTable.view(atColumn:0,row:2,makeIfNecessary:true)!
  let replacementBadge=all(replacementCell).compactMap{$0 as? DownloadActivityBadge}.first!
  expect(replacementBadge.activity?.identity.incarnation=="replacement","New incarnation owns its own progress host")
  for width:CGFloat in [320,400] {
   layoutView.frame.size.width=width;layoutView.needsLayout=true;layoutView.layoutSubtreeIfNeeded()
   for row in 1...4 {
    let cell=layoutTable.view(atColumn:0,row:row,makeIfNecessary:true)!;cell.needsLayout=true;cell.layoutSubtreeIfNeeded()
    expect(cell.subviews.allSatisfy{$0.isHidden || ($0.frame.minX>=0 && $0.frame.maxX<=cell.bounds.width+1)},"Real row controls remain within narrow and regular Library bounds")
    expect(layoutView.tableView(layoutTable,heightOfRow:row)==56,"Download list uses recovered compact row height")
    let labels=cell.subviews.compactMap{$0 as? NSTextField}
    expect(labels.count==2 && labels[0].font?.pointSize==14 && labels[1].font?.pointSize==12,"Actual row preserves recovered two-line type hierarchy")
    let titleLine=labels[0].font!.ascender-labels[0].font!.descender+labels[0].font!.leading
    expect(abs(labels[1].frame.minY-labels[0].frame.minY-titleLine-2)<=0.5,"Title and subtitle lines have recovered two-point VStack gap")
    let image=cell.subviews.compactMap{$0 as? NSImageView}.first!
    if row==4 {
     let placeholder=image.layer!.sublayers!.first!
     expect(placeholder.frame==NSRect(x:9,y:9,width:14,height:14) && !placeholder.isHidden,"Failed row centers original14-point EmptyFavicon inside its32-point slot")
     let favicon=LibraryArtwork.emptyFavicon!
     expect(favicon.isTemplate && favicon.size==NSSize(width:14,height:14) && placeholder.mask?.frame==placeholder.bounds,"EmptyFavicon is a 14-point template asset, masking the placeholder")
     expect(favicon.representations.compactMap{$0 as? NSBitmapImageRep}.map(\.pixelsWide).sorted()==[14,28],"The bundled 1× and 2× EmptyFavicon renditions are used unchanged")
     image.effectiveAppearance.performAsCurrentDrawingAppearance {
      let primary=NSColor.labelColor.alphaComponent
      expect(abs((placeholder.backgroundColor?.alpha ?? 0)-primary)<0.001,"EmptyFavicon tints its template with semantic primary")
      let side=28,context=CGContext(data:nil,width:side,height:side,bitsPerComponent:8,bytesPerRow:side*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
      context.scaleBy(x:2,y:2)
      placeholder.render(in:context)
      let pixels=context.data!.bindMemory(to:UInt8.self,capacity:side*side*4)
      func alpha(_ x:Int,_ y:Int)->Double { Double(pixels[(y*side+x)*4+3])/255 }
      expect(abs(alpha(14,14)-primary*72/255)<2.0/255,"EmptyFavicon reproduces original 72/255 template opacity through semantic primary")
      expect(alpha(0,0)<0.05 && alpha(27,27)<0.05,"EmptyFavicon keeps its rounded silhouette: its corners stay clear")
      expect(labels[0].textColor == NSColor.secondaryLabelColor,"Failed original title uses secondary semantic color")
     }
    }
    expect(image.frame.size==NSSize(width:row==1 ? 24:32,height:row==1 ? 24:32),"Actual file image uses24 points while independent accessories retain32-point frames")
    let actions=cell.subviews.compactMap{$0 as? NSButton}.filter{!$0.isHidden}.sorted{$0.frame.minX<$1.frame.minX}
    expect(cell.subviews.compactMap{$0 as? NSButton}.count==1 && actions.allSatisfy{$0.parcTooltip?.label=="More download actions" && $0.toolTip==nil && $0.frame.size==NSSize(width:32,height:32) && $0.frame.maxY<=56},"Every row state has only the recovered conditional More target")
    expect(labels.allSatisfy{$0.isAccessibilityHidden()} && image.isAccessibilityHidden(),"Native item label owns text/artwork semantics once while More remains independent")
    expect(actions.first.map{labels[0].frame.maxX+8 <= $0.frame.minX} ?? (labels[0].frame.maxX<=cell.bounds.width-12),"Long titles cannot overlap actual actions")
    expect(labels[1].toolTip?.contains("example.invalid")==true,"Original source remains available without a third visual line")
    expect((cell.accessibilityLabel() ?? "").components(separatedBy:"example.invalid").count==2,"Source context is spoken once per row")
    let children = cell.accessibilityChildren() ?? []
    expect(children.allSatisfy { $0 is NSButton } && children.count <= 1,"Actual native cell accessibility excludes synthesized decorative text and artwork")
   }
   if let output=ProcessInfo.processInfo.environment["PARC_COMPONENT_IMAGES"] {
    let destination=URL(fileURLWithPath:output,isDirectory:true);try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
    for appearance in [NSAppearance.Name.aqua,.darkAqua] {
     layoutView.appearance=NSAppearance(named:appearance)
     layoutView.palette=ThemeChromePalette(theme:SpaceTheme(),isDark:appearance == .darkAqua)
     layoutView.wantsLayer=true
     layoutView.effectiveAppearance.performAsCurrentDrawingAppearance {
      layoutView.layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor
     }
     layoutView.needsDisplay=true;layoutView.layoutSubtreeIfNeeded()
     if let bitmap=layoutView.bitmapImageRepForCachingDisplay(in:layoutView.bounds) {
      layoutView.cacheDisplay(in:layoutView.bounds,to:bitmap)
      if let png=bitmap.representation(using:.png,properties:[:]) {try png.write(to:destination.appendingPathComponent("downloads-\(Int(width))-\(appearance.rawValue).png"))}
     }
    }
   }
  }
  layoutTable.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
  let originalPreviewFile=directory.appendingPathComponent("owned-preview.png")
  layoutView.fileURL={_ in originalPreviewFile}
  layoutTable.onPreview?()
  let actualPreview=layoutWindow.childWindows!.first!
  let actualModal=actualPreview.contentView!.subviews.last!
  let actualSource=actualModal.subviews.compactMap{$0 as? NSImageView}.first!
  expect(actualSource.image?.representations.first?.pixelsWide==48 && actualSource.image?.size==NSSize(width:24,height:24),"Actual row admission renders its24-point artwork at2x without another file load")
  layoutView.invalidate()
  expect(actualPreview.parent==nil && actualSource.image==nil,"Original Library invalidation releases real source image and child together")
  layoutView.fileURL=nil
  layoutTable.selectRowIndexes([],byExtendingSelection:false)
  let accessoryRow=layoutTable.rowView(atRow:1,makeIfNecessary:true)!
  let accessoryCell=layoutTable.view(atColumn:0,row:1,makeIfNecessary:true)!
  let rowBackdrop=accessoryRow.subviews.compactMap { $0 as? DownloadRowBackdrop }.first!
  accessoryRow.layoutSubtreeIfNeeded();rowBackdrop.updateLayer()
  expect(rowBackdrop.frame==NSRect(x:8,y:0,width:accessoryRow.bounds.width-16,height:56),"Original full-height row background is inside8-point horizontal padding")
  expect(rowBackdrop.layer?.cornerRadius==12 && rowBackdrop.layer?.cornerCurve == .continuous,"Original row background retains continuous12-point corners")
  expect(rowBackdrop.hitTest(NSPoint(x:16,y:16))==nil && rowBackdrop.isAccessibilityHidden() && rowBackdrop.accessibilityChildren()?.isEmpty==true,"Background neither intercepts native row input nor adds a second accessible item")
  expect(!rowBackdrop.highlighted && rowBackdrop.layer?.backgroundColor?.alpha==0,"Unselected unhovered original row is clear")
  let accessory=all(accessoryCell).compactMap{$0 as? NSButton}.first{$0.parcTooltip?.label=="More download actions"}!
  let accessoryTitle=all(accessoryCell).compactMap{$0 as? NSTextField}.first!
  accessoryCell.layoutSubtreeIfNeeded()
  let collapsedTitleWidth=accessoryTitle.frame.width
  var primaryAlpha:CGFloat=0
  accessoryTitle.effectiveAppearance.performAsCurrentDrawingAppearance { primaryAlpha=NSColor.labelColor.alphaComponent }
  expect(abs((accessoryTitle.textColor?.alphaComponent ?? 0)-primaryAlpha*0.85)<0.001,"Ordinary title applies opacity to semantic primary instead of replacing its alpha")
  let fileArtwork=accessoryCell.subviews.compactMap{$0 as? NSImageView}.first!
  let filePlaceholder=fileArtwork.layer!.sublayers!.first!
  expect(filePlaceholder.frame.size==NSSize(width:24,height:24) && filePlaceholder.cornerRadius==8 && filePlaceholder.cornerCurve == .continuous,"Actual unavailable image draws original24-point continuous placeholder")
  expect(abs((filePlaceholder.backgroundColor?.alpha ?? 0)-primaryAlpha*0.05)<0.001,"File placeholder preserves semantic primary5percent alpha")
  for appearance in [NSAppearance.Name.aqua,.darkAqua] {
   layoutView.appearance=NSAppearance(named:appearance);layoutView.layoutSubtreeIfNeeded()
   accessoryTitle.effectiveAppearance.performAsCurrentDrawingAppearance {
    expect(abs((accessoryTitle.textColor?.alphaComponent ?? 0)-NSColor.labelColor.alphaComponent*0.85)<0.001,"Actual light/dark title preserves semantic alpha")
   }
  }
  expect(accessory.isHidden,"Unhighlighted unselected row collapses More")
  let enter=NSEvent.enterExitEvent(with:.mouseEntered,location:.zero,modifierFlags:[],timestamp:0,windowNumber:layoutWindow.windowNumber,context:nil,eventNumber:0,trackingNumber:0,userData:nil)!
  let leave=NSEvent.enterExitEvent(with:.mouseExited,location:.zero,modifierFlags:[],timestamp:0,windowNumber:layoutWindow.windowNumber,context:nil,eventNumber:0,trackingNumber:0,userData:nil)!
  accessoryRow.mouseEntered(with:enter);accessoryCell.layoutSubtreeIfNeeded()
  expect(abs((accessoryTitle.textColor?.alphaComponent ?? 0)-primaryAlpha)<0.001,"Actual hover restores full semantic primary title")
  expect(!accessory.isHidden && accessory.frame.size==NSSize(width:32,height:32),"Original hovered row exposes recovered32-point More")
  rowBackdrop.updateLayer()
  expect(rowBackdrop.highlighted && abs((rowBackdrop.layer?.backgroundColor?.alpha ?? 0)-NSColor.labelColor.alphaComponent*0.1)<0.001,"Actual hover owner supplies recovered primary10percent background")
  expect(collapsedTitleWidth-accessoryTitle.frame.width==32,"Original zero-sized More returns its32-point width while the HStack gap stays fixed")
  accessoryRow.mouseExited(with:leave)
  expect(accessory.isHidden,"Pointer exit collapses unselected More immediately")
  layoutTable.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
  expect(!accessory.isHidden,"Native keyboard/table selection exposes More without pointer hover")
  expect(accessory.isAccessibilityElement() && accessory.accessibilityRole() == .button,"The actual selected image-only More control exposes its native button role")
  accessoryRow.isEmphasized=false;rowBackdrop.updateLayer()
  expect(rowBackdrop.highlighted && abs((rowBackdrop.layer?.backgroundColor?.alpha ?? 0)-NSColor.labelColor.alphaComponent*0.1)<0.001,"Inactive original selection keeps the same recovered background rather than provisional8percent")
  accessoryRow.isEmphasized=true;rowBackdrop.updateLayer()
  expect(rowBackdrop.highlighted && rowBackdrop.emphasized,"Original selected state and native contrast-focus state remain distinct")
  let originalScroll=layoutTable.enclosingScrollView!
  NotificationCenter.default.post(name:NSScrollView.willStartLiveScrollNotification,object:NSScrollView())
  expect(!accessory.isHidden,"Another scroll owner cannot hide this row's selected action")
  layoutWindow.makeFirstResponder(accessory)
  NotificationCenter.default.post(name:NSScrollView.willStartLiveScrollNotification,object:originalScroll)
  expect(layoutWindow.firstResponder===layoutTable,"Removing original More during scroll returns its exact native focus to the table")
  expect(accessory.isHidden,"Actual original live-scroll notification suppresses even selected More")
  expect(rowBackdrop.highlighted,"Original selection keeps its background while live scroll suppresses only the right accessory")
  accessoryRow.mouseEntered(with:enter)
  expect(accessory.isHidden,"Pointer crossing during scrolling does not revive the accessory")
  NotificationCenter.default.post(name:NSScrollView.didEndLiveScrollNotification,object:originalScroll)
  expect(!accessory.isHidden,"Original scroll completion restores selected row accessory")
  layoutTable.selectRowIndexes([],byExtendingSelection:false);accessoryRow.mouseExited(with:leave)
  expect(accessory.isHidden,"Deselecting original row retires its nonhovered accessory")
  rowBackdrop.updateLayer()
  expect(!rowBackdrop.highlighted && rowBackdrop.layer?.backgroundColor?.alpha==0,"Deselect/exit clears the exact retained background without a delayed transition")
  accessoryRow.mouseEntered(with:enter)
  NotificationCenter.default.post(name:NSWindow.didResignKeyNotification,object:layoutWindow)
  expect(accessory.isHidden,"Original window focus loss clears inactive pointer presentation")
  for (appearance,rest,hover,press) in [(NSAppearance.Name.aqua,0.565,0.910,0.141),(.darkAqua,0.592,0.923,0.172)] {
   accessory.appearance=NSAppearance(named:appearance)
   accessoryRow.mouseEntered(with:enter);accessory.mouseExited(with:leave)
   expect(abs(accessory.contentTintColor!.alphaComponent-rest)<0.001,"Idle native More glyph uses recovered appearance-specific GrayA11")
   accessory.mouseEntered(with:enter)
   expect(abs(accessory.contentTintColor!.alphaComponent-hover)<0.001,"Hover native More glyph uses recovered GrayA12")
   let color=DownloadAccessoryColors.background(pressed:true,appearance:accessory.effectiveAppearance)
   expect(abs(color.alphaComponent-press)<0.001,"Pressed accessory background retains recovered GrayA7")
   accessory.isEnabled=false
   expect(!accessory.isEnabled && accessory.accessibilityLabel()=="More download actions","Native disabled and accessible label survive presentation updates")
   accessory.isEnabled=true
  }
  accessoryRow.mouseExited(with:leave)
  layoutWindow.contentView=nil
  NotificationCenter.default.post(name:NSScrollView.willStartLiveScrollNotification,object:originalScroll)
  accessoryRow.isSelected=true
  expect(!accessory.isHidden,"Detached row has removed its old scroll observation")
  accessoryRow.isSelected=false;layoutWindow.contentView=layoutView
  expect(accessory.isHidden,"Reattachment does not retain stale hover presentation")
  expect(!rowBackdrop.highlighted,"Original row reattachment also clears stale background highlight")
  let regularRail=LibraryView(store:store,kind:.downloads,profileID:profile)
  regularRail.frame=NSRect(x:0,y:0,width:416,height:832)
  regularRail.layout()
  let regularButtons=all(regularRail).compactMap{$0 as? NSButton}
  let categoryNames=["Media","Downloads","Easels & Notes","Spaces","Archived Tabs"]
  let categories=all(regularRail).compactMap{$0 as? LibraryRailTile}
  expect(categories.map(\.title)==categoryNames,"Regular rail lists the Library pages without Boosts or History")
  expect(categories.allSatisfy{$0.frame.size==NSSize(width:97,height:80) && $0.frame.minX==8 && $0.showsLabel},"Tall rail uses 97 × 80 tiles")
  expect(zip(categories,categories.dropFirst()).allSatisfy{$1.frame.minY-$0.frame.minY==100},"Tiles sit in 100-point slots")
  expect(abs(categories[0].frame.minY+categories[4].frame.maxY-(48+832-56))<0.01,"Tiles are centred between the rail padding and Back")
  expect(categories.first{$0.title=="Downloads"}!.state == .on,"The shown page's tile is selected")
  expect(regularButtons.first{$0.title=="Back"}!.imagePosition == .imageOnly,"Regular Back keeps its accessible title and shows its arrow")
  let railWindow=NSWindow(contentRect:regularRail.frame,styleMask:.borderless,backing:.buffered,defer:false)
  railWindow.isReleasedWhenClosed=false;railWindow.contentView=regularRail;regularRail.layoutSubtreeIfNeeded()
  railWindow.setFrameOrigin(NSPoint(x:-20000,y:-20000))
  regularRail.appearance=NSAppearance(named:.aqua)
  func labelBands(_ tile:NSView)->Int {
   guard let rep=tile.bitmapImageRepForCachingDisplay(in:tile.bounds) else { return -1 }
   tile.cacheDisplay(in:tile.bounds,to:rep)
   let scale=CGFloat(rep.pixelsWide)/tile.bounds.width
   let x=Int(tile.bounds.midX*scale)
   let minimumGap=Int(4*scale)
   var bands=0, gap=minimumGap*3
   for y in Int(47*scale)..<Int(74*scale) {
    var ink=false
    if let color=rep.colorAt(x:x,y:y)?.usingColorSpace(.sRGB) {
     ink=color.alphaComponent>0.2 && color.redComponent<0.5 && color.greenComponent<0.5 && color.blueComponent<0.5
    }
    if ink { if gap>=minimumGap { bands += 1 }; gap=0 } else { gap += 1 }
   }
   return bands
  }
  let easelsBands=labelBands(categories.first{$0.title=="Easels & Notes"}!)
  expect(easelsBands==2,"Easels & Notes wraps onto two centered lines at 11pt (\(easelsBands))")
  let archivedBands=labelBands(categories.first{$0.title=="Archived Tabs"}!)
  expect(archivedBands==1,"Shorter rail labels stay one line (\(archivedBands))")
  expect(regularRail.subviews.contains{$0.frame==NSRect(x:0,y:0,width:145,height:regularRail.bounds.height) && $0.hitTest(NSPoint(x:8,y:8))==nil},"The rail sits on a non-interactive depth layer")
  expect(LibraryRailAnimation.named(.archive) != nil && LibraryRailAnimation.named(.easels) != nil,"Rail compositions load from the bundle's Library resources")
  let selectedTile=categories.first{$0.title=="Downloads"}!
  expect(categories.allSatisfy{$0.accessibilityRole() == .radioButton} && selectedTile.isAccessibilitySelected() && !categories[0].isAccessibilitySelected(),"Rail tiles announce as radio buttons with the shown page selected")
  selectedTile.performClick(nil)
  expect(selectedTile.state == .on && selectedTile.isAccessibilitySelected() && regularRail.kind == .downloads,"Clicking the selected tile keeps it selected")
  let otherTile=categories.first{$0.title=="Media"}!
  otherTile.state = .off
  otherTile.cell?.setNextState()
  expect(otherTile.state == .off,"A tile never toggles its own selection")
  let downloadsTile=categories.first{$0.title=="Downloads"}!
  let railBadge=downloadsTile.progress!
  expect(categories.allSatisfy{($0.progress != nil)==($0 === downloadsTile)} && railBadge.isHidden,"Only the Downloads tile carries a progress badge, hidden while nothing downloads")
  func firstInk(_ tile:NSView,_ rows:Range<CGFloat>)->CGFloat? {
   tile.layoutSubtreeIfNeeded()
   guard let rep=tile.bitmapImageRepForCachingDisplay(in:tile.bounds) else { return nil }
   tile.cacheDisplay(in:tile.bounds,to:rep)
   let scale=CGFloat(rep.pixelsHigh)/tile.bounds.height
   for row in Int(rows.lowerBound*scale)..<Int(rows.upperBound*scale) {
    for x in Int((tile.bounds.midX-30)*scale)..<Int((tile.bounds.midX+30)*scale) {
     if let color=rep.colorAt(x:x,y:row)?.usingColorSpace(.sRGB), color.alphaComponent>0.2,
        color.redComponent<0.5 && color.greenComponent<0.5 && color.blueComponent<0.5 { return CGFloat(row)/scale }
    }
   }
   return nil
  }
  let idleLabel=firstInk(downloadsTile,46..<76)
  expect(idleLabel != nil && firstInk(downloadsTile,10..<44) != nil,"The idle Downloads tile draws its icon over the label")
  var inFlight=BrowserDownload(id:profile.uuidString+":rail",name:"Rail.dmg",path:"/nonexistent/Rail.dmg",receivedBytes:40,totalBytes:100,status:.downloading)
  inFlight.profileID=profile;inFlight.nativeID="rail";inFlight.nativeIdentity="rail-1";inFlight.startedAt=Date()
  var privateFlight=inFlight;privateFlight.privateContextID="private-rail"
  regularRail.updateDownloadActivity([privateFlight],profiles:[profile],privateWindow:false,enabled:true)
  expect(railBadge.isHidden,"A normal window's rail ignores private downloads, as the sidebar entry does")
  regularRail.updateDownloadActivity([inFlight],profiles:[profile],privateWindow:false,enabled:false)
  expect(railBadge.isHidden,"The rail badges only while the window can")
  regularRail.updateDownloadActivity([inFlight],profiles:[profile],privateWindow:false,enabled:true)
  regularRail.layoutSubtreeIfNeeded()
  expect(!railBadge.isHidden && railBadge.activity?.progress==0.4 && railBadge.activity?.identity==DownloadLibraryIdentity(inFlight),
         "The newest in-flight download's progress badge shows on the Downloads tile")
  let badgeFrame=downloadsTile.convert(railBadge.bounds,from:railBadge)
  expect(badgeFrame.size==NSSize(width:LibraryRailTile.progressSize,height:LibraryRailTile.progressSize) && abs(badgeFrame.midX-downloadsTile.bounds.midX)<0.01,
         "The badge keeps its own 24-point frame, centred in the icon slot")
  let downloadingLabel=firstInk(downloadsTile,46..<76)
  expect(idleLabel != nil && downloadingLabel != nil && abs(idleLabel!-downloadingLabel!-2)<=0.5,
         "The label rises 2 points as the 24-point badge replaces the 28-point icon (\(String(describing:idleLabel)) → \(String(describing:downloadingLabel)))")
  expect(downloadsTile.accessibilityRole() == .radioButton && downloadsTile.accessibilityLabel()=="Downloads" && downloadsTile.isAccessibilitySelected()
         && !railBadge.isAccessibilityElement(),"The badge leaves the tile's radio-button accessibility unchanged")
  let badgeHit=downloadsTile.hitTest(downloadsTile.superview!.convert(NSPoint(x:railBadge.bounds.midX,y:railBadge.bounds.midY),from:railBadge))
  expect(badgeHit != nil && (badgeHit === downloadsTile || badgeHit!.isDescendant(of:downloadsTile)) && !badgeHit!.isDescendant(of:railBadge),
         "Pointer input over the badge still reaches the tile")
  var progressedFlight=inFlight;progressedFlight.receivedBytes=70
  regularRail.layoutSubtreeIfNeeded()
  regularRail.updateDownloadActivity([progressedFlight],profiles:[profile],privateWindow:false,enabled:true)
  expect(railBadge.activity?.progress==0.7 && !railBadge.isHidden && !downloadsTile.needsLayout,
         "A progress tick updates only the ring; the tile relayouts only when the badge appears or retires")
  regularRail.show(.archive)
  expect(downloadsTile.state == .off && !railBadge.isHidden,"The badge stays on the unselected Downloads tile while another page shows")
  regularRail.show(.downloads)
  var pendingFlight=inFlight;pendingFlight.id=profile.uuidString+":pending";pendingFlight.nativeID="pending";pendingFlight.nativeIdentity="pending-1"
  pendingFlight.status = .pending;pendingFlight.receivedBytes=0;pendingFlight.startedAt=Date().addingTimeInterval(60)
  var pausedFlight=pendingFlight;pausedFlight.id=profile.uuidString+":paused";pausedFlight.nativeID="paused";pausedFlight.nativeIdentity="paused-1"
  pausedFlight.status = .paused;pausedFlight.receivedBytes=30
  regularRail.updateDownloadActivity([progressedFlight,pendingFlight,pausedFlight],profiles:[profile],privateWindow:false,enabled:true)
  expect(railBadge.activity?.identity==DownloadLibraryIdentity(progressedFlight) && railBadge.activity?.progress==0.7,
         "Newer not-started and paused downloads are not in flight, so the ring stays on the in-progress one")
  regularRail.updateDownloadActivity([pendingFlight,pausedFlight],profiles:[profile],privateWindow:false,enabled:true)
  expect(railBadge.isHidden,"With only not-started and paused downloads the icon shows")
  regularRail.updateDownloadActivity([progressedFlight],profiles:[profile],privateWindow:false,enabled:true)
  var fullFlight=inFlight;fullFlight.receivedBytes=100
  regularRail.updateDownloadActivity([fullFlight],profiles:[profile],privateWindow:false,enabled:true)
  expect(!railBadge.isHidden && railBadge.activity?.completed==true,"Progress reaching 1 while still in flight plays the checkmark")
  var finishedFlight=inFlight;finishedFlight.status = .completed;finishedFlight.receivedBytes=100
  regularRail.updateDownloadActivity([finishedFlight],profiles:[profile],privateWindow:false,enabled:true)
  expect(railBadge.isHidden && firstInk(downloadsTile,46..<76)==idleLabel && firstInk(downloadsTile,10..<44) != nil,
         "Once nothing is in flight the icon returns at once and the label settles back")
  let lights=all(regularRail).compactMap{$0 as? WindowStandardButtons}.first!
  expect(lights.isHidden,"Library lights stay hidden until the window lists them")
  regularRail.showsWindowButtons=true
  expect(!lights.isHidden,"Library lists the dimmed traffic-light group")
  regularRail.appearance=NSAppearance(named:.aqua)
  lights.needsDisplay=true;lights.displayIfNeeded()
  expect(abs(lights.alphaValue-0.1)<0.02,"Unhovered Library lights are dimmed in Aqua")
  let systemLights=[NSButton(),NSButton(),NSButton()]
  let showsInLibrary=WindowFullscreenPhase.apply(nil,sidebarless:false,system:systemLights)
  expect(showsInLibrary && systemLights.allSatisfy(\.isHidden),"A Library window hides the system lights and keeps the in-chrome group")
  let popupLights=[NSButton(),NSButton(),NSButton()]
  let showsInPopup=WindowFullscreenPhase.apply(nil,sidebarless:true,system:popupLights)
  expect(showsInPopup && popupLights.allSatisfy{!$0.isHidden},"A popup keeps the system lights and has no Library group")
  let expandedLights=[NSButton(),NSButton(),NSButton()]
  expandedLights.forEach{$0.isHidden=true}
  let showsExpanded=WindowFullscreenPhase.apply(.expanded,sidebarless:false,system:expandedLights)
  expect(!showsExpanded && expandedLights.allSatisfy{!$0.isHidden},"Expanded full screen shows the system lights and hides the in-chrome group")
  expect(WindowFullscreenPhase.showsSidebarButtons(.exiting),"Exiting full screen lists the in-chrome lights again")
  railWindow.contentView=nil;railWindow.close()
  regularRail.frame.size.height=400;regularRail.layout()
  let backFrame=regularButtons.first{$0.title=="Back"}!.frame
  expect(categories.last!.frame.maxY<=backFrame.minY && categories.allSatisfy{!$0.showsLabel},"Short rail compresses its slots above Back and drops labels")
  expect(LibraryView.subtitle(urls:["https://www.iana.org/domains/reserved"],spaceName:nil)=="iana.org/domains/reserved" &&
         LibraryView.subtitle(urls:["https://example.com/"],spaceName:nil)=="example.com" &&
         LibraryView.subtitle(urls:["parc://note/A"],spaceName:nil)=="parc://note/A" &&
         LibraryView.subtitle(urls:["https://user:secret@www.example.com/path"],spaceName:nil)=="example.com/path" &&
         LibraryView.subtitle(urls:["ftp://user@files.example.com/a"],spaceName:nil)=="ftp://files.example.com/a" &&
         LibraryView.subtitle(urls:["https://a.example","https://b.example"],spaceName:"Work")=="2 tabs · Work","Archive subtitles read as tab count · Space")
  let archiveHeadingNow=Date(timeIntervalSince1970:1_900_000_000)
  expect(LibraryView.heading(for:archiveHeadingNow,relativeTo:archiveHeadingNow)=="Today" &&
         LibraryView.heading(for:archiveHeadingNow.addingTimeInterval(-86_400),relativeTo:archiveHeadingNow)=="Yesterday" &&
         LibraryView.heading(for:archiveHeadingNow.addingTimeInterval(-3*86_400),relativeTo:archiveHeadingNow).contains("3"),"Archive sections use relative day names")
  let privateDirectory=directory.appendingPathComponent("never-created-private",isDirectory:true)
  let privateStore=BrowserStore(privateParentProfileID:profile,engineProfilePath:path,
   directory:privateDirectory,settings:store.state.settings)
  let privateID=privateStore.activeSpace.profileID
  var privateRecord:[String:Any] = ["id":"private-original","profilePath":path,"offTheRecord":true,
   "name":"Private fixture.pdf","path":"/not-opened/private.pdf","status":"completed","available":true,
   "itemIdentity":"private-lease-1","canOpen":true,"canCopyFile":true,"canRemove":true,"startedAt":1000]
  store.recordDownload(privateRecord)
  expect(!store.state.downloads.contains{$0.nativeID=="private-original"},"Regular catalog rejects OTR publication")
  store.recordPrivateDownload(privateRecord)
  expect(!store.state.downloads.contains{$0.nativeID=="private-original"},"Private endpoint cannot populate a regular store")
  privateStore.recordPrivateDownload(privateRecord)
  expect(privateStore.state.downloads.count==1 && privateStore.state.downloads[0].profileID==privateID,"Original private manager data is namespaced to memory-only window profile")
  var foreign=privateRecord;foreign["profilePath"]=path+"-other";foreign["id"]="foreign"
  privateStore.recordPrivateDownload(foreign)
  expect(privateStore.state.downloads.count==1,"Private publication refuses a different original parent path")
  foreign=privateRecord;foreign["offTheRecord"]=false;foreign["id"]="regular"
  privateStore.recordPrivateDownload(foreign)
  expect(privateStore.state.downloads.count==1,"Private endpoint refuses normal-manager data")
  let capturesFingerprintRoot=directory.appendingPathComponent("captures-fingerprint",isDirectory:true)
  let capturesFingerprintStore=try BrowserStore(directory:capturesFingerprintRoot)
  let capturesFingerprintProfile=capturesFingerprintStore.activeSpace.profileID
  let capturesFingerprintCatalog=CaptureLibraryStore.shared(
   directory:capturesFingerprintStore.capturesDirectory(for:capturesFingerprintProfile),
   profileID:capturesFingerprintProfile)
  for _ in 0..<50 where capturesFingerprintCatalog.isLoading {
   RunLoop.main.run(mode:.default,before:Date(timeIntervalSinceNow:0.02))
  }
  let capturesFingerprintMedia=ExternalMediaLibrary(
   directory:capturesFingerprintStore.capturesDirectory(for:capturesFingerprintProfile),
   preferencesAreEphemeral:true,systemFolders:{[]})
  let capturesFingerprintView=CaptureLibraryView(
   store:capturesFingerprintCatalog,profileOwner:capturesFingerprintStore,
   media:capturesFingerprintMedia,ownerValid:{true})
  capturesFingerprintView.frame=NSRect(x:0,y:0,width:400,height:600)
  let capturesFingerprintWindow=NSWindow(contentRect:capturesFingerprintView.frame,styleMask:.titled,backing:.buffered,defer:false)
  capturesFingerprintWindow.isReleasedWhenClosed=false
  capturesFingerprintWindow.contentView=capturesFingerprintView
  capturesFingerprintView.layoutSubtreeIfNeeded()
  func capturesFingerprintCollection()->CaptureCollectionView {
   all(capturesFingerprintView).compactMap{$0 as? CaptureCollectionView}.first!
  }
  func capturesFingerprintCount()->Int { capturesFingerprintCollection().numberOfItems(inSection:0) }
  expect(!all(capturesFingerprintView).compactMap{$0 as? NSTextField}.contains{$0.stringValue.contains("On this Mac") || $0.stringValue.contains("original folders")},
         "Media has no Parc-invented count footer or folder note")
  func mediaRightClick(_ view:NSView)->NSEvent {
   NSEvent.mouseEvent(with:.rightMouseDown,location:view.convert(NSPoint(x:view.bounds.midX,y:view.bounds.midY),to:nil),modifierFlags:[],
    timestamp:0,windowNumber:capturesFingerprintWindow.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
  }
  func isFolderMenu(_ titles:[String]?)->Bool { titles?.contains("Add Media Folder…")==true && titles?.contains("Refresh")==true }
  let emptyMediaGrid=capturesFingerprintCollection()
  expect(isFolderMenu(emptyMediaGrid.menu(for:mediaRightClick(emptyMediaGrid))?.items.map(\.title)),"Right-clicking empty grid space opens the folder menu")
  let mediaEmptyMessage=all(capturesFingerprintView).compactMap{$0 as? NSTextField}.first{!$0.isHidden && $0.stringValue.hasPrefix("Saved captures")}!
  expect(isFolderMenu(mediaEmptyMessage.menu(for:mediaRightClick(mediaEmptyMessage))?.items.map(\.title)),
         "Right-clicking the empty-state message opens the same folder menu")
  var keyboardMenuRequest:Bool?
  let mediaKeyboardMenu=emptyMediaGrid.onKeyboardMenu
  emptyMediaGrid.onKeyboardMenu={foldersOnly in keyboardMenuRequest=foldersOnly; return true}
  func mediaKey(_ code:UInt16,_ flags:NSEvent.ModifierFlags) {
   keyboardMenuRequest=nil
   emptyMediaGrid.keyDown(with:NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,
    windowNumber:capturesFingerprintWindow.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:code)!)
  }
  mediaKey(109,.shift)
  expect(keyboardMenuRequest==false,"Shift-F10 asks for the keyboard menu")
  mediaKey(109,[.shift,.option])
  expect(keyboardMenuRequest==true,"Option-Shift-F10 asks for the folder menu")
  mediaKey(36,.control)
  expect(keyboardMenuRequest==false,"Control-Return asks for the keyboard menu")
  keyboardMenuRequest=nil
  expect(emptyMediaGrid.accessibilityPerformShowMenu() && keyboardMenuRequest==false,"Accessibility Show Menu asks for the keyboard menu")
  emptyMediaGrid.onKeyboardMenu=mediaKeyboardMenu
  expect(isFolderMenu(capturesFingerprintView.keyboardMenu(foldersOnly:false)?.menu.items.map(\.title)),
         "With nothing selected the keyboard menu is the folder menu")
  func waitCaptures(_ work:@escaping @MainActor () async throws -> Void) throws {
   var done=false;var failure:Error?
   Task { @MainActor in
    do { try await work(); done=true }
    catch { failure=error; done=true }
   }
   for _ in 0..<200 where !done {
    RunLoop.main.run(mode:.default,before:Date(timeIntervalSinceNow:0.02))
   }
   expect(done,"Captures fingerprint async work settled")
   if let failure { throw failure }
  }
  expect(capturesFingerprintCount()==0,"Empty Captures fingerprint starts with no items")
  try waitCaptures { await capturesFingerprintCatalog.reload() }
  drainMain()
  expect(capturesFingerprintCount()==0,"Identical empty Captures re-publish remains a fingerprint no-op")
  let capturesPNG:Data={
   let rgba=Data([255,0,0,255,0,255,0,255,0,0,255,255,255,255,255,255])
   let image=CGImage(width:2,height:2,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:8,
    space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),
    provider:CGDataProvider(data:rgba as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
   let output=NSMutableData()
   let encoder=CGImageDestinationCreateWithData(output,UTType.png.identifier as CFString,1,nil)!
   CGImageDestinationAddImage(encoder,image,nil);precondition(CGImageDestinationFinalize(encoder))
   return output as Data
  }()
  var capturesFingerprintSaved:SavedCapture!
  try waitCaptures {
   capturesFingerprintSaved=try await capturesFingerprintCatalog.save(CaptureLibraryInput(
    id:UUID(),expectedRevision:nil,capturedAt:Date(timeIntervalSince1970:1_920_000_000),
    profileID:capturesFingerprintProfile,spaceID:capturesFingerprintStore.activeSpaceID,
    spaceName:"Captures fingerprint",title:"Captures fingerprint item",
    sourceURL:"https://captures-fingerprint.example.invalid",kind:.region,pngData:capturesPNG))
  }
  drainMain()
  expect(capturesFingerprintCount()==1,"Capture membership still populates the collection")
  capturesFingerprintCollection().selectionIndexPaths=[IndexPath(item:0,section:0)]
  let selectedMediaMenu=capturesFingerprintView.keyboardMenu(foldersOnly:false)?.menu.items.map(\.title)
  expect(selectedMediaMenu?.contains("Preview")==true && !isFolderMenu(selectedMediaMenu),"Shift-F10 opens the selected item's menu")
  expect(isFolderMenu(capturesFingerprintView.keyboardMenu(foldersOnly:true)?.menu.items.map(\.title)),
         "Option-Shift-F10 reaches the folder menu even with a selection")
  capturesFingerprintCollection().selectionIndexPaths=[]
  try waitCaptures { await capturesFingerprintCatalog.reload() }
  drainMain()
  expect(capturesFingerprintCollection().numberOfItems(inSection:0)==1,"Identical Captures re-publish keeps collection membership")
  let capturesSearch=all(capturesFingerprintView).compactMap{$0 as? NSTextField}.first{$0.placeholderString=="Search Media…" || $0.accessibilityLabel()=="Search Media"}!
  capturesSearch.stringValue="no-match-filter"
  capturesFingerprintView.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:capturesSearch))
  drainMain()
  expect(capturesFingerprintCount()==0,"Search filter force-reloads past the Captures fingerprint")
  capturesSearch.stringValue=""
  capturesFingerprintView.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:capturesSearch))
  drainMain()
  expect(capturesFingerprintCount()==1,"Clearing Captures search force-reloads membership")
  capturesSearch.stringValue="no-match-filter"
  capturesFingerprintView.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:capturesSearch))
  drainMain()
  capturesSearch.stringValue=""
  capturesFingerprintView.searchFieldDidEndSearching(capturesSearch as! NSSearchField)
  drainMain()
  expect(capturesFingerprintCount()==1,"The search field's clear button restores the full grid")
  capturesFingerprintView.searchFieldDidEndSearching(capturesSearch as! NSSearchField)
  drainMain()
  expect(capturesFingerprintCount()==1,"Ending a search that is already applied leaves the grid alone")
  expect(capturesFingerprintCatalog.contains(capturesFingerprintSaved),"Fingerprint fixture capture remains durable")
  let statusRoot=directory.appendingPathComponent("media-status",isDirectory:true)
  let statusFolder=statusRoot.appendingPathComponent("Pictures",isDirectory:true)
  let statusMissing=statusRoot.appendingPathComponent("Missing",isDirectory:true)
  try FileManager.default.createDirectory(at:statusFolder,withIntermediateDirectories:true)
  let statusFile=statusFolder.appendingPathComponent("fixture.png")
  try capturesPNG.write(to:statusFile)
  try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:2_200_000_000)],ofItemAtPath:statusFile.path)
  let statusMedia=ExternalMediaLibrary(directory:statusRoot.appendingPathComponent("Preferences",isDirectory:true),
   preferencesAreEphemeral:true,systemFolders:{[statusFolder,statusMissing]})
  let statusView=CaptureLibraryView(store:capturesFingerprintCatalog,profileOwner:capturesFingerprintStore,media:statusMedia,regularHeader:true,ownerValid:{true})
  statusView.frame=NSRect(x:0,y:0,width:400,height:600)
  let statusWindow=NSWindow(contentRect:statusView.frame,styleMask:.titled,backing:.buffered,defer:false)
  statusWindow.isReleasedWhenClosed=false;statusWindow.contentView=statusView
  let statusGrid=all(statusView).compactMap{$0 as? NSCollectionView}.first!
  for _ in 0..<200 where statusMedia.isLoading || statusMedia.folders.count<2 || statusGrid.numberOfItems(inSection:0)<2 {
   RunLoop.main.run(mode:.default,before:Date(timeIntervalSinceNow:0.02))
  }
  statusView.layoutSubtreeIfNeeded()
  let folderNotice="1 folder needs access. Right-click empty space to fix."
  func mediaStatus()->String? {
   all(statusView).compactMap{$0 as? NSTextField}.first{!$0.isHidden && $0.font?.pointSize==10.5}?.stringValue
  }
  let statusScroll=statusGrid.enclosingScrollView!
  expect(mediaStatus()==folderNotice && statusScroll.frame.height==statusView.bounds.height-statusScroll.frame.minY-28,
         "An unavailable folder shows the bottom status line and shortens the grid")
  statusGrid.selectionIndexPaths=[IndexPath(item:0,section:0)]
  try FileManager.default.removeItem(at:statusFile)
  statusGrid.keyDown(with:NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:statusWindow.windowNumber,
   context:nil,characters:"\u{7f}",charactersIgnoringModifiers:"\u{7f}",isARepeat:false,keyCode:51)!)
  for _ in 0..<200 where mediaStatus()==folderNotice || statusMedia.isLoading || statusGrid.numberOfItems(inSection:0) != 1 {
   RunLoop.main.run(mode:.default,before:Date(timeIntervalSinceNow:0.02))
  }
  drainMain()
  let failure=mediaStatus()
  expect(failure != nil && failure != folderNotice && !statusMedia.isLoading && statusGrid.numberOfItems(inSection:0)==1,
         "A failed file action keeps its error after the follow-up refresh")
  statusView.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification))
  drainMain()
  expect(mediaStatus()==folderNotice,"The next user action clears the file-action error")
  statusView.invalidate();statusWindow.contentView=nil;statusWindow.close()
  let toggleRoot=directory.appendingPathComponent("media-toggle-failure",isDirectory:true)
  let toggleFolder=toggleRoot.appendingPathComponent("Pictures",isDirectory:true)
  try FileManager.default.createDirectory(at:toggleFolder,withIntermediateDirectories:true)
  try capturesPNG.write(to:toggleFolder.appendingPathComponent("fixture.png"))
  let togglePreferences=toggleRoot.appendingPathComponent("Preferences",isDirectory:true)
  try FileManager.default.createDirectory(at:togglePreferences,withIntermediateDirectories:true)
  let toggleMedia=ExternalMediaLibrary(directory:togglePreferences,systemFolders:{[toggleFolder]})
  let toggleView=CaptureLibraryView(store:capturesFingerprintCatalog,profileOwner:capturesFingerprintStore,media:toggleMedia,regularHeader:true,ownerValid:{true})
  toggleView.frame=NSRect(x:0,y:0,width:400,height:600)
  let toggleWindow=NSWindow(contentRect:toggleView.frame,styleMask:.titled,backing:.buffered,defer:false)
  toggleWindow.isReleasedWhenClosed=false;toggleWindow.contentView=toggleView
  let toggleGrid=all(toggleView).compactMap{$0 as? NSCollectionView}.first!
  for _ in 0..<200 where toggleMedia.isLoading || toggleGrid.numberOfItems(inSection:0)<capturesFingerprintCatalog.items.count+1 {
   RunLoop.main.run(mode:.default,before:Date(timeIntervalSinceNow:0.02))
  }
  let toggleInitialCount=toggleGrid.numberOfItems(inSection:0)
  try FileManager.default.createDirectory(at:togglePreferences.appendingPathComponent("MediaFolders.json",isDirectory:true),withIntermediateDirectories:false)
  let toggleFolderMenu=toggleView.keyboardMenu(foldersOnly:true)!.menu
  let stopShowing=toggleFolderMenu.items.first!.submenu!.items.first{$0.title=="Stop Showing This Folder"}!
  (stopShowing.representedObject as! MenuAction).invoke()
  func toggleStatus()->String? { all(toggleView).compactMap{$0 as? NSTextField}.first{!$0.isHidden && $0.font?.pointSize==10.5}?.stringValue }
  for _ in 0..<200 where toggleStatus()==nil || toggleMedia.isLoading || toggleGrid.numberOfItems(inSection:0) != toggleInitialCount {
   RunLoop.main.run(mode:.default,before:Date(timeIntervalSinceNow:0.02))
  }
  toggleView.layoutSubtreeIfNeeded()
  expect(toggleStatus() != nil && !toggleMedia.isLoading && toggleGrid.numberOfItems(inSection:0)==toggleInitialCount,
         "A failed folder toggle reports its error and refreshes Media after the synchronous clear")
  toggleWindow.contentView=nil;toggleWindow.close()
  let staleRoot=directory.appendingPathComponent("media-stale",isDirectory:true)
  let staleFolder=staleRoot.appendingPathComponent("Pictures",isDirectory:true)
  try FileManager.default.createDirectory(at:staleFolder,withIntermediateDirectories:true)
  let staleFile=staleFolder.appendingPathComponent("fixture.png")
  try capturesPNG.write(to:staleFile)
  try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:2_200_000_000)],ofItemAtPath:staleFile.path)
  let staleMedia=ExternalMediaLibrary(directory:staleRoot.appendingPathComponent("Preferences",isDirectory:true),
   preferencesAreEphemeral:true,systemFolders:{[staleFolder]})
  let staleView=CaptureLibraryView(store:capturesFingerprintCatalog,profileOwner:capturesFingerprintStore,media:staleMedia,regularHeader:true,ownerValid:{true})
  staleView.frame=NSRect(x:0,y:0,width:400,height:600)
  let staleWindow=NSWindow(contentRect:staleView.frame,styleMask:.titled,backing:.buffered,defer:false)
  staleWindow.isReleasedWhenClosed=false;staleWindow.contentView=staleView
  let staleGrid=all(staleView).compactMap{$0 as? NSCollectionView}.first!
  for _ in 0..<200 where staleMedia.isLoading || staleGrid.numberOfItems(inSection:0)<capturesFingerprintCatalog.items.count+1 {
   RunLoop.main.run(mode:.default,before:Date(timeIntervalSinceNow:0.02))
  }
  staleView.layoutSubtreeIfNeeded()
  func staleStatus()->String? { all(staleView).compactMap{$0 as? NSTextField}.first{!$0.isHidden && $0.font?.pointSize==10.5}?.stringValue }
  expect(staleStatus()==nil,"A single available folder starts with no status line")
  staleGrid.selectionIndexPaths=[IndexPath(item:0,section:0)]
  try FileManager.default.removeItem(at:staleFile)
  staleGrid.keyDown(with:NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:staleWindow.windowNumber,
   context:nil,characters:"\u{7f}",charactersIgnoringModifiers:"\u{7f}",isARepeat:false,keyCode:51)!)
  for _ in 0..<200 where staleStatus()==nil || staleMedia.isLoading {
   RunLoop.main.run(mode:.default,before:Date(timeIntervalSinceNow:0.02))
  }
  drainMain()
  expect(staleStatus() != nil,"Deleting the selected file produces a file-action failure")
  staleWindow.contentView=nil
  expect(staleStatus()==nil,"invalidate() clears a stale file-action failure so the next presentation starts clean")
  staleWindow.close()
  let quietRoot=directory.appendingPathComponent("media-quiet-refresh",isDirectory:true)
  let quietFolder=quietRoot.appendingPathComponent("Pictures",isDirectory:true)
  let quietLater=quietRoot.appendingPathComponent("Later",isDirectory:true)
  try FileManager.default.createDirectory(at:quietFolder,withIntermediateDirectories:true)
  try capturesPNG.write(to:quietFolder.appendingPathComponent("fixture.png"))
  let quietMedia=ExternalMediaLibrary(directory:quietRoot.appendingPathComponent("Preferences",isDirectory:true),
   preferencesAreEphemeral:true,systemFolders:{[quietFolder,quietLater]})
  let quietView=CaptureLibraryView(store:capturesFingerprintCatalog,profileOwner:capturesFingerprintStore,media:quietMedia,regularHeader:true,ownerValid:{true})
  quietView.frame=NSRect(x:0,y:0,width:400,height:600)
  let quietWindow=NSWindow(contentRect:quietView.frame,styleMask:.titled,backing:.buffered,defer:false)
  quietWindow.isReleasedWhenClosed=false;quietWindow.contentView=quietView
  let quietGrid=all(quietView).compactMap{$0 as? NSCollectionView}.first!
  let quietCaptures=capturesFingerprintCatalog.items.count
  func quietWait(_ pending:() -> Bool) {
   let deadline=Date(timeIntervalSinceNow:10)
   while pending() && Date()<deadline { RunLoop.main.run(mode:.default,before:Date(timeIntervalSinceNow:0.02)) }
   drainMain()
  }
  func quietStatus()->String? { all(quietView).compactMap{$0 as? NSTextField}.first{!$0.isHidden && $0.font?.pointSize==10.5}?.stringValue }
  quietWait { quietMedia.isLoading || quietMedia.folders.count<2 || quietGrid.numberOfItems(inSection:0)<quietCaptures+1 }
  expect(quietGrid.numberOfItems(inSection:0)==quietCaptures+1 && quietStatus()=="1 folder needs access. Right-click empty space to fix.",
         "Quiet-refresh Media starts with its capture, its file and one missing folder")
  let quietSearch=all(quietView).compactMap{$0 as? NSTextField}.first{$0.placeholderString=="Search Media…" || $0.accessibilityLabel()=="Search Media"}!
  quietSearch.stringValue="pending-unapplied-query"
  quietMedia.refresh()
  expect(quietMedia.isLoading,"An explicit Media refresh shows loading")
  quietWait { quietMedia.isLoading }
  expect(quietGrid.numberOfItems(inSection:0)==quietCaptures+1,"A loading flip with nothing new does not rebuild the Media grid")
  try FileManager.default.createDirectory(at:quietLater,withIntermediateDirectories:true)
  quietMedia.refresh()
  quietWait { quietMedia.isLoading || quietStatus() != nil }
  expect(quietStatus()==nil && quietGrid.numberOfItems(inSection:0)==quietCaptures+1,
         "A folder-access change updates the status line without rebuilding the Media grid")
  let quietStaged=quietRoot.appendingPathComponent("arrival.png");try capturesPNG.write(to:quietStaged)
  try FileManager.default.moveItem(at:quietStaged,to:quietFolder.appendingPathComponent("arrival.png"))
  quietWait { quietMedia.items.count<2 || quietGrid.numberOfItems(inSection:0) != 0 }
  expect(quietMedia.items.count==2 && quietGrid.numberOfItems(inSection:0)==0,"A new file rebuilds the Media grid with the current search")
  quietSearch.stringValue=""
  quietView.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:quietSearch))
  drainMain()
  expect(quietGrid.numberOfItems(inSection:0)==quietCaptures+2,"Clearing search shows the capture and both files")
  quietView.invalidate();quietWindow.contentView=nil;quietWindow.close()
  let liveRoot=directory.appendingPathComponent("media-incremental",isDirectory:true)
  let liveFolder=liveRoot.appendingPathComponent("Pictures",isDirectory:true)
  try FileManager.default.createDirectory(at:liveFolder,withIntermediateDirectories:true)
  for index in 0..<24 {
   let file=liveFolder.appendingPathComponent(String(format:"fixture-%02d.png",index));try capturesPNG.write(to:file)
   try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:1_700_000_000-Double(index)*60)],ofItemAtPath:file.path)
  }
  let liveStore=try BrowserStore(directory:liveRoot.appendingPathComponent("profile",isDirectory:true))
  let liveProfile=liveStore.activeSpace.profileID
  let liveCatalog=CaptureLibraryStore.shared(directory:liveStore.capturesDirectory(for:liveProfile),profileID:liveProfile)
  for _ in 0..<50 where liveCatalog.isLoading { RunLoop.main.run(mode:.default,before:Date(timeIntervalSinceNow:0.02)) }
  let liveCloud=LiveCloud()
  let liveMedia=ExternalMediaLibrary(directory:liveRoot.appendingPathComponent("Preferences",isDirectory:true),
   preferencesAreEphemeral:true,systemFolders:{[liveFolder]},cloud:liveCloud.source,screenshotPreferences:nil)
  let liveView=CaptureLibraryView(store:liveCatalog,profileOwner:liveStore,media:liveMedia,regularHeader:true,ownerValid:{true})
  liveView.frame=NSRect(x:0,y:0,width:400,height:600)
  let liveWindow=DownloadHoverWindow(contentRect:liveView.frame,styleMask:.titled,backing:.buffered,defer:false)
  liveWindow.isReleasedWhenClosed=false;liveWindow.pointer=NSPoint(x:-1000,y:-1000);liveWindow.contentView=liveView
  let liveGrid=all(liveView).compactMap{$0 as? CaptureCollectionView}.first!
  quietWait { liveMedia.isLoading || liveGrid.numberOfItems(inSection:0)<24 }
  let liveSource=CountingMediaSource(liveGrid.dataSource!)
  liveGrid.dataSource=liveSource;liveGrid.reloadData();liveView.layoutSubtreeIfNeeded()
  let liveClip=liveGrid.enclosingScrollView!.contentView
  liveGrid.scrollToItems(at:[IndexPath(item:4,section:0)],scrollPosition:.top);liveView.layoutSubtreeIfNeeded()
  func liveTitle(_ index:Int)->String? { liveGrid.item(at:IndexPath(item:index,section:0))?.view.subviews.compactMap{$0 as? NSButton}.first?.toolTip }
  func liveLit(_ index:Int)->Bool { liveGrid.item(at:IndexPath(item:index,section:0)).map{$0.view.layer!.sublayers![0].frame==$0.view.bounds} ?? false }
  liveGrid.selectionIndexPaths=[IndexPath(item:7,section:0)]
  let liveOrigin=liveClip.bounds.origin,liveSelected=liveTitle(7)
  let liveHovered=liveTitle(5)!,liveHoverTile=liveGrid.item(at:IndexPath(item:5,section:0))!.view
  liveWindow.pointer=liveHoverTile.convert(NSPoint(x:liveHoverTile.bounds.midX,y:liveHoverTile.bounds.midY),to:nil)
  (liveHoverTile as NSView).mouseEntered(with:NSEvent.enterExitEvent(with:.mouseEntered,location:liveWindow.pointer,modifierFlags:[],timestamp:0,
   windowNumber:liveWindow.windowNumber,context:nil,eventNumber:0,trackingNumber:0,userData:nil)!)
  expect(liveOrigin.y>0 && liveSelected=="fixture-07.png" && liveLit(5),"The incremental grid starts scrolled, with a selection and a hovered tile")
  func liveSettle(_ count:Int) { quietWait { liveGrid.numberOfItems(inSection:0) != count };liveView.layoutSubtreeIfNeeded();drainMain() }
  liveSource.made=0
  let liveStaged=liveRoot.appendingPathComponent("arrival.png");try capturesPNG.write(to:liveStaged)
  try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:1_700_000_060)],ofItemAtPath:liveStaged.path)
  try FileManager.default.moveItem(at:liveStaged,to:liveFolder.appendingPathComponent("arrival.png"))
  liveSettle(25)
  expect(liveGrid.numberOfItems(inSection:0)==25 && liveSource.made<=2,"A single arrival inserts one tile instead of reloading the grid (made \(liveSource.made))")
  expect(liveGrid.selectionIndexPaths==[IndexPath(item:8,section:0)] && liveTitle(8)==liveSelected,"The selection stays on its file as an arrival shifts it")
  expect(liveClip.bounds.origin==liveOrigin,"An arrival keeps the scroll position")
  expect(liveTitle(6)==liveHovered && !liveLit(6) && liveLit(5),"Hover follows the pointer, not the tile that moved away")
  liveGrid.scrollToItems(at:[IndexPath(item:0,section:0)],scrollPosition:.top);liveView.layoutSubtreeIfNeeded();drainMain()
  liveSource.made=0
  let liveEdited=liveFolder.appendingPathComponent("fixture-07.png")
  let liveHandle=try FileHandle(forWritingTo:liveEdited);_=try liveHandle.seekToEnd();try liveHandle.write(contentsOf:capturesPNG);try liveHandle.close()
  quietWait { liveTitle(0) != "fixture-07.png" }
  liveView.layoutSubtreeIfNeeded();drainMain()
  expect(liveGrid.numberOfItems(inSection:0)==25 && liveTitle(0)=="fixture-07.png" && liveSource.made<=2,
         "An in-place change moves just that tile to the top (made \(liveSource.made))")
  expect(liveGrid.selectionIndexPaths==[IndexPath(item:0,section:0)],"The selection follows the changed file")
  liveGrid.scrollToItems(at:[IndexPath(item:11,section:0)],scrollPosition:.top);liveView.layoutSubtreeIfNeeded();drainMain()
  liveSource.made=0
  try FileManager.default.moveItem(at:liveFolder.appendingPathComponent("fixture-10.png"),to:liveFolder.appendingPathComponent("fixture-10b.png"))
  quietWait { liveTitle(11) != "fixture-10b.png" }
  liveView.layoutSubtreeIfNeeded();drainMain()
  expect(liveGrid.numberOfItems(inSection:0)==25 && liveTitle(11)=="fixture-10b.png" && liveSource.made<=2,"A rename swaps one tile (made \(liveSource.made))")
  liveSource.made=0
  let liveCloudName=liveTitle(12)!,liveCloudPath=liveMedia.items.first{$0.title==liveCloudName}!.id
  liveCloud.evict(liveCloudPath)
  quietWait { liveMedia.items.first{$0.id==liveCloudPath}?.isLocal != false }
  liveView.layoutSubtreeIfNeeded();drainMain()
  expect(liveMedia.items.first{$0.id==liveCloudPath}?.isLocal==false && liveGrid.numberOfItems(inSection:0)==25 && liveTitle(12)==liveCloudName
         && liveSource.made>=1 && liveSource.made<=2,"An iCloud download-status change replaces just that tile (made \(liveSource.made))")
  liveSource.made=0
  try FileManager.default.removeItem(at:liveEdited)
  liveSettle(24)
  expect(liveGrid.numberOfItems(inSection:0)==24 && liveGrid.selectionIndexPaths.isEmpty && liveSource.made<=2,
         "Removing the selected file drops its tile and the selection (made \(liveSource.made))")
  liveSource.made=0
  let liveSearch=all(liveView).compactMap{$0 as? NSTextField}.first{$0.placeholderString=="Search Media…" || $0.accessibilityLabel()=="Search Media"}!
  liveSearch.stringValue="fixture-1"
  liveView.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:liveSearch))
  liveView.layoutSubtreeIfNeeded();drainMain()
  expect(liveGrid.numberOfItems(inSection:0)==10 && liveSource.made>=4,"A search reloads the visible grid, so the counter sees full reloads")
  liveView.invalidate();liveWindow.contentView=nil;liveWindow.close()
  let messageRoot=directory.appendingPathComponent("media-message-overlay",isDirectory:true)
  let messageStore=try BrowserStore(directory:messageRoot)
  let messageProfile=messageStore.activeSpace.profileID
  let messageCapturesDir=messageStore.capturesDirectory(for:messageProfile)
  try FileManager.default.createDirectory(at:messageCapturesDir,withIntermediateDirectories:true)
  try Data("not a catalog".utf8).write(to:messageCapturesDir.appendingPathComponent("Captures.json"))
  let messageCatalog=CaptureLibraryStore.shared(directory:messageCapturesDir,profileID:messageProfile)
  for _ in 0..<50 where messageCatalog.isLoading {
   RunLoop.main.run(mode:.default,before:Date(timeIntervalSinceNow:0.02))
  }
  expect(messageCatalog.loadError != nil && messageCatalog.items.isEmpty,"A corrupted catalog fails to load with no captures")
  let messageFolder=messageRoot.appendingPathComponent("Pictures",isDirectory:true)
  try FileManager.default.createDirectory(at:messageFolder,withIntermediateDirectories:true)
  try capturesPNG.write(to:messageFolder.appendingPathComponent("fixture.png"))
  let messageMedia=ExternalMediaLibrary(directory:messageRoot.appendingPathComponent("Preferences",isDirectory:true),
   preferencesAreEphemeral:true,systemFolders:{[messageFolder]})
  let messageView=CaptureLibraryView(store:messageCatalog,profileOwner:messageStore,media:messageMedia,regularHeader:true,ownerValid:{true})
  messageView.frame=NSRect(x:0,y:0,width:400,height:600)
  let messageWindow=NSWindow(contentRect:messageView.frame,styleMask:.titled,backing:.buffered,defer:false)
  messageWindow.isReleasedWhenClosed=false;messageWindow.contentView=messageView
  let messageGrid=all(messageView).compactMap{$0 as? NSCollectionView}.first!
  for _ in 0..<200 where messageMedia.isLoading || messageGrid.numberOfItems(inSection:0)<1 {
   RunLoop.main.run(mode:.default,before:Date(timeIntervalSinceNow:0.02))
  }
  messageView.layoutSubtreeIfNeeded()
  expect(messageGrid.numberOfItems(inSection:0)==1,"The media item still renders despite the captures catalog failing to load")
  let overlayMessage=all(messageView).compactMap{$0 as? NSTextField}.first{!$0.isHidden && $0.stringValue.contains("could not be read")}!
  func messageRightClick(_ view:NSView)->NSEvent {
   NSEvent.mouseEvent(with:.rightMouseDown,location:view.convert(NSPoint(x:view.bounds.midX,y:view.bounds.midY),to:nil),modifierFlags:[],
    timestamp:0,windowNumber:messageWindow.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
  }
  expect(overlayMessage.menu(for:messageRightClick(overlayMessage))==nil,
         "Right-clicking the load-error message does not open the folder menu while items exist behind it")
  messageWindow.contentView=nil;messageWindow.close()
  let anchorRoot=directory.appendingPathComponent("media-anchor",isDirectory:true)
  let anchorFolder=anchorRoot.appendingPathComponent("Pictures",isDirectory:true)
  try FileManager.default.createDirectory(at:anchorFolder,withIntermediateDirectories:true)
  for index in 0..<40 {
   let file=anchorFolder.appendingPathComponent("fixture-\(index).png")
   try capturesPNG.write(to:file)
   try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:2_200_000_000+Double(index))],ofItemAtPath:file.path)
  }
  let anchorMedia=ExternalMediaLibrary(directory:anchorRoot.appendingPathComponent("Preferences",isDirectory:true),
   preferencesAreEphemeral:true,systemFolders:{[anchorFolder]})
  let anchorStore=try BrowserStore(directory:anchorRoot.appendingPathComponent("profile",isDirectory:true))
  let anchorProfile=anchorStore.activeSpace.profileID
  let anchorCatalog=CaptureLibraryStore.shared(directory:anchorStore.capturesDirectory(for:anchorProfile),profileID:anchorProfile)
  for _ in 0..<50 where anchorCatalog.isLoading {
   RunLoop.main.run(mode:.default,before:Date(timeIntervalSinceNow:0.02))
  }
  let anchorView=CaptureLibraryView(store:anchorCatalog,profileOwner:anchorStore,media:anchorMedia,regularHeader:true,ownerValid:{true})
  anchorView.frame=NSRect(x:0,y:0,width:400,height:220)
  let anchorWindow=NSWindow(contentRect:anchorView.frame,styleMask:.titled,backing:.buffered,defer:false)
  anchorWindow.isReleasedWhenClosed=false;anchorWindow.contentView=anchorView
  let anchorGrid=all(anchorView).compactMap{$0 as? NSCollectionView}.first!
  for _ in 0..<200 where anchorMedia.isLoading || anchorGrid.numberOfItems(inSection:0)<40 {
   RunLoop.main.run(mode:.default,before:Date(timeIntervalSinceNow:0.02))
  }
  anchorView.layoutSubtreeIfNeeded()
  let lastAnchorIndex=anchorGrid.numberOfItems(inSection:0)-1
  anchorGrid.selectionIndexPaths=[IndexPath(item:lastAnchorIndex,section:0)]
  anchorGrid.scrollToItems(at:[IndexPath(item:0,section:0)],scrollPosition:.top)
  anchorView.layoutSubtreeIfNeeded()
  let offscreenFrame=anchorGrid.frameForItem(at:lastAnchorIndex)
  let visibleBeforeMenu=anchorGrid.visibleRect
  expect(!visibleBeforeMenu.intersects(offscreenFrame),"The selected last item starts out scrolled out of view")
  let anchorRequest=anchorView.keyboardMenu(foldersOnly:false)
  expect(anchorRequest != nil,"The keyboard menu exists for a selected item")
  if let anchorRequest {
   let visibleAfterMenu=anchorGrid.visibleRect
   expect(anchorRequest.point==NSPoint(x:visibleAfterMenu.minX+10,y:visibleAfterMenu.minY+10),
          "An off-screen selected item's keyboard menu uses the visible area's top-left fallback")
  }
  anchorWindow.contentView=nil;anchorWindow.close()
  func tilePNG(_ width:Int,_ height:Int)->Data {
   let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),
    bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
   context.setFillColor(CGColor(red:0.2,green:0.4,blue:0.8,alpha:1));context.fill(CGRect(x:0,y:0,width:width,height:height))
   let output=NSMutableData()
   let encoder=CGImageDestinationCreateWithData(output,UTType.png.identifier as CFString,1,nil)!
   CGImageDestinationAddImage(encoder,context.makeImage()!,nil);precondition(CGImageDestinationFinalize(encoder))
   return output as Data
  }
  let tileRoot=directory.appendingPathComponent("media-tiles",isDirectory:true)
  let tileFolder=tileRoot.appendingPathComponent("Pictures",isDirectory:true)
  try FileManager.default.createDirectory(at:tileFolder,withIntermediateDirectories:true)
  for (name,data,age) in [("wide.png",tilePNG(240,120),0.0),("tall.png",tilePNG(100,200),120),("clip.mov",Data(),180)] {
   let file=tileFolder.appendingPathComponent(name);try data.write(to:file)
   try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:2_300_000_000-age)],ofItemAtPath:file.path)
  }
  let tileStore=try BrowserStore(directory:tileRoot.appendingPathComponent("profile",isDirectory:true))
  let tileProfile=tileStore.activeSpace.profileID
  let tileCatalog=CaptureLibraryStore.shared(directory:tileStore.capturesDirectory(for:tileProfile),profileID:tileProfile)
  for _ in 0..<50 where tileCatalog.isLoading { RunLoop.main.run(mode:.default,before:Date(timeIntervalSinceNow:0.02)) }
  try waitCaptures {
   _=try await tileCatalog.save(CaptureLibraryInput(id:UUID(),expectedRevision:nil,capturedAt:Date(timeIntervalSince1970:2_300_000_000-60),
    profileID:tileProfile,spaceID:tileStore.activeSpaceID,spaceName:"Tiles",title:"Tile capture",
    sourceURL:"https://media-tiles.example.invalid",kind:.region,pngData:tilePNG(160,100)))
  }
  let tileMedia=ExternalMediaLibrary(directory:tileRoot.appendingPathComponent("Preferences",isDirectory:true),
   preferencesAreEphemeral:true,systemFolders:{[tileFolder]})
  let tileView=CaptureLibraryView(store:tileCatalog,profileOwner:tileStore,media:tileMedia,regularHeader:true,ownerValid:{true})
  tileView.frame=NSRect(x:0,y:0,width:304,height:600)
  let tileWindow=DownloadHoverWindow(contentRect:tileView.frame,styleMask:.titled,backing:.buffered,defer:false)
  tileWindow.isReleasedWhenClosed=false;tileWindow.pointer=NSPoint(x:-1000,y:-1000);tileWindow.contentView=tileView
  let tileGrid=all(tileView).compactMap{$0 as? CaptureCollectionView}.first!
  func tile(_ index:Int)->NSView { tileGrid.item(at:IndexPath(item:index,section:0))!.view }
  func parts(_ index:Int)->(plate:CALayer,placeholder:CALayer,paper:CALayer,border:CAShapeLayer,artwork:CALayer,play:CALayer) {
   let layers=tile(index).layer!.sublayers!
   return (layers[0],layers[1],layers[2],layers[3] as! CAShapeLayer,layers[4],layers[5])
  }
  func tilesReady()->Bool {
   guard tileGrid.numberOfItems(inSection:0)==4 else { return false }
   return [0,1,2].allSatisfy{index in tileGrid.item(at:IndexPath(item:index,section:0)) != nil && !parts(index).artwork.isHidden}
  }
  for _ in 0..<500 where !tilesReady() { RunLoop.main.run(mode:.default,before:Date(timeIntervalSinceNow:0.02));tileView.layoutSubtreeIfNeeded() }
  expect(tilesReady(),"Media tiles load the wide file, the capture and the tall file thumbnails")
  let tileBounds=tile(0).bounds,center=NSPoint(x:tileBounds.midX,y:tileBounds.midY)
  expect(tileBounds.size==NSSize(width:137,height:137),"Parc's two flexible columns give 137-point cells in a 304-point Media page")
  let side:CGFloat=117
  func near(_ a:NSRect,_ b:NSRect)->Bool { abs(a.minX-b.minX)<0.01 && abs(a.minY-b.minY)<0.01 && abs(a.width-b.width)<0.01 && abs(a.height-b.height)<0.01 }
  func fitted(_ aspect:CGFloat,lit:Bool)->(paper:NSRect,artwork:NSRect) {
   let room=side*(lit ? 1:0.95)-8
   let size=aspect>=1 ? NSSize(width:room,height:room/aspect):NSSize(width:room*aspect,height:room)
   let artwork=NSRect(x:center.x-size.width/2,y:center.y-size.height/2,width:size.width,height:size.height)
   return (artwork.insetBy(dx:-4,dy:-4),artwork)
  }
  var primaryTileAlpha:CGFloat=0
  tile(0).effectiveAppearance.performAsCurrentDrawingAppearance {primaryTileAlpha=NSColor.labelColor.alphaComponent}
  let reduceTileMotion=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  func expectTile(_ index:Int,aspect:CGFloat,lit:Bool,_ label:String) {
   let p=parts(index)
   expect(near(p.plate.frame,tileBounds.insetBy(dx:lit ? 0:4,dy:lit ? 0:4)) && p.plate.cornerRadius==12 && p.plate.cornerCurve == .continuous,
          label+": plate fills the cell when lit and sits 4 points inside at rest, continuous radius 12")
   expect(abs((p.plate.backgroundColor?.alpha ?? 0)-primaryTileAlpha*(lit ? 0.15:0.05))<0.001,label+": plate is primary at 15% lit and 5% at rest")
   let geometry=fitted(aspect,lit:lit)
   expect(near(p.artwork.frame,geometry.artwork),label+": thumbnail fits its aspect inside a 4-point border within the 117-point frame at \(lit ? 100:95)%")
   if index==1 {
    expect(p.paper.isHidden && !p.border.isHidden,label+": a capture draws a dashed outline, not paper")
    expect(near(p.border.path!.boundingBox,geometry.paper.insetBy(dx:1,dy:1)) && p.border.lineDashPhase==(lit ? 5:0),
           label+": the outline strokes inside the 4-point border and shifts its dash phase by one dash when lit")
   } else {
    let down:CGFloat=p.paper.contentsAreFlipped() ? 1:-1
    expect(!p.paper.isHidden && p.border.isHidden && near(p.paper.frame,geometry.paper),label+": a file thumbnail sits on paper hugging its fitted image")
    expect(p.paper.shadowOpacity==(lit ? 0.2:0.1) && p.paper.shadowRadius==(lit ? 5:1) && p.paper.shadowOffset==CGSize(width:0,height:down*(lit ? 3:1)),
           label+": paper shadow is black 0.1, radius 1, 1 point down at rest and 0.2, radius 5, 3 points down when lit")
   }
  }
  expectTile(0,aspect:2,lit:false,"Resting wide image")
  expectTile(1,aspect:1.6,lit:false,"Resting capture")
  expectTile(2,aspect:0.5,lit:false,"Resting tall image")
  let paperLayer=parts(0).paper
  expect(paperLayer.cornerRadius==2 && paperLayer.cornerCurve == .continuous && paperLayer.backgroundColor==NSColor.white.cgColor && paperLayer.shadowColor==NSColor.black.cgColor,
         "Paper is white with continuous radius 2 and a black shadow")
  let outline=parts(1).border
  expect(outline.lineWidth==2 && outline.lineCap == .round && outline.lineDashPattern==[5] && outline.fillColor==nil &&
         outline.strokeColor==NSColor.white.withAlphaComponent(0.5).cgColor,"Capture outline is white 50%, 2 points, round-capped 5-point dashes")
  expect(parts(0).play.isHidden && parts(1).play.isHidden && parts(2).play.isHidden && !parts(3).play.isHidden,"Only the video tile carries the play badge")
  let badge=parts(3).play
  expect(badge.contents != nil && abs(badge.frame.midX-center.x)<0.01 && abs(badge.frame.midY-center.y)<0.01 && badge.shadowOpacity==0,
         "The play badge is centered and carries its shadow in its own image, without an offscreen layer shadow")
  let videoParts=parts(3)
  expect(videoParts.artwork.isHidden && videoParts.paper.isHidden && !videoParts.placeholder.isHidden,"An unreadable video shows the blank placeholder")
  expect(near(videoParts.placeholder.frame,NSRect(x:center.x-side/2,y:center.y-side/2,width:side,height:side)) && videoParts.placeholder.cornerRadius==8 &&
         abs((videoParts.placeholder.backgroundColor?.alpha ?? 0)-primaryTileAlpha*0.05)<0.001,"Placeholder fills the thumbnail frame, continuous radius 8, primary 5%")
  func pointer(_ type:NSEvent.EventType,_ index:Int,_ point:NSPoint)->NSEvent {
   let location=tile(index).convert(point,to:nil)
   if type == .mouseMoved {
    return NSEvent.mouseEvent(with:.mouseMoved,location:location,modifierFlags:[],timestamp:0,windowNumber:tileWindow.windowNumber,context:nil,eventNumber:0,clickCount:0,pressure:0)!
   }
   return NSEvent.enterExitEvent(with:type,location:location,modifierFlags:[],timestamp:0,windowNumber:tileWindow.windowNumber,context:nil,eventNumber:0,trackingNumber:0,userData:nil)!
  }
  func hoverIn(_ index:Int,at point:NSPoint?=nil) { tile(index).mouseEntered(with:pointer(.mouseEntered,index,point ?? center)) }
  func hoverMove(_ index:Int,to point:NSPoint) { tile(index).mouseMoved(with:pointer(.mouseMoved,index,point)) }
  func hoverOut(_ index:Int) { tile(index).mouseExited(with:pointer(.mouseExited,index,.zero)) }
  hoverIn(0)
  expectTile(0,aspect:2,lit:true,"Hovered wide image")
  let plateSpring=parts(0).plate.animation(forKey:"bounds") as? CASpringAnimation
  if reduceTileMotion {
   expect(parts(0).plate.animationKeys()==nil && parts(0).paper.animationKeys()==nil && parts(0).artwork.animationKeys()==nil,"Reduce Motion snaps the pop without animation")
  } else {
   expect(plateSpring != nil && plateSpring!.mass==1 && abs(plateSpring!.stiffness-pow(2 * .pi/0.18,2))<0.001 && abs(plateSpring!.damping-4 * .pi*0.8/0.18)<0.001 &&
          plateSpring!.duration==plateSpring!.settlingDuration,"Hover uses spring(response 0.18, damping 0.8)")
   expect((plateSpring!.fromValue as? NSValue)?.rectValue.size==tileBounds.insetBy(dx:4,dy:4).size && (plateSpring!.toValue as? NSValue)?.rectValue.size==tileBounds.size,
          "The plate spring grows from the resting inset to the cell edge")
   let springKeys=Set((parts(0).paper.animationKeys() ?? [])+(parts(0).artwork.animationKeys() ?? []))
   expect(springKeys.isSuperset(of:["bounds","shadowPath","shadowOpacity","shadowRadius","shadowOffset"]) && parts(0).plate.animation(forKey:"backgroundColor") != nil,
          "Plate fill, paper, shadow and thumbnail all ride the same spring")
   expect(parts(0).border.animationKeys()==nil,"The hidden capture outline of a file tile gets no spring")
  }
  hoverOut(0)
  expectTile(0,aspect:2,lit:false,"Unhovered wide image")
  if !reduceTileMotion {
   let back=parts(0).plate.animation(forKey:"bounds") as? CASpringAnimation
   expect((back?.toValue as? NSValue)?.rectValue.size==tileBounds.insetBy(dx:4,dy:4).size,"Leaving springs the plate back to its resting inset")
  }
  hoverIn(1)
  expectTile(1,aspect:1.6,lit:true,"Hovered capture")
  expect(reduceTileMotion || parts(1).paper.animationKeys()==nil,"The hidden paper of a capture gets no spring")
  hoverOut(1)
  let ring=NSPoint(x:2,y:center.y),corner=NSPoint(x:2,y:2)
  hoverIn(0,at:ring)
  expectTile(0,aspect:2,lit:false,"Entering through the cell's outer ring")
  hoverMove(0,to:center)
  expectTile(0,aspect:2,lit:true,"Moving onto the resting plate")
  hoverMove(0,to:ring)
  expectTile(0,aspect:2,lit:true,"The lit plate reaches the cell edge, so its ring keeps the hover")
  hoverMove(0,to:corner)
  expectTile(0,aspect:2,lit:false,"The cell corner outside the lit plate's rounding ends the hover")
  hoverOut(0)
  expect(tile(0).hitTest(tile(0).convert(ring,to:tileGrid))==nil && tile(0).hitTest(tile(0).convert(center,to:tileGrid)) != nil,
         "Only the resting plate takes clicks")
  let ringClick=NSEvent.mouseEvent(with:.leftMouseDown,location:tile(0).convert(ring,to:nil),modifierFlags:[],timestamp:0,
   windowNumber:tileWindow.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
  let ringMenu=NSEvent.mouseEvent(with:.rightMouseDown,location:tile(0).convert(ring,to:nil),modifierFlags:[],timestamp:0,
   windowNumber:tileWindow.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
  expect(isFolderMenu(tileGrid.menu(for:ringMenu)?.items.map(\.title)),"Right-clicking a cell's ring opens the grid's folder menu")
  tileGrid.mouseDown(with:ringClick)
  expect(tileGrid.selectionIndexPaths.isEmpty && tileWindow.childWindows?.isEmpty != false,"Clicking a cell's ring neither selects nor opens it")
  let tileScroll=tileGrid.enclosingScrollView!
  let tileSearch=all(tileView).compactMap{$0 as? DownloadSearchField}.first!
  hoverIn(2)
  NotificationCenter.default.post(name:NSScrollView.willStartLiveScrollNotification,object:tileScroll)
  expectTile(2,aspect:0.5,lit:true,"Scroll start keeps a current hover")
  hoverOut(2)
  expectTile(2,aspect:0.5,lit:false,"Leaving during a live scroll clears the hover")
  hoverIn(0)
  expectTile(0,aspect:2,lit:false,"A pointer crossing during a live scroll")
  let pooledTiles=Set(tileGrid.subviews.map(ObjectIdentifier.init))
  let lateFile=tileFolder.appendingPathComponent("late.png");try tilePNG(120,120).write(to:lateFile)
  try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:2_300_000_000-240)],ofItemAtPath:lateFile.path)
  for _ in 0..<500 where tileGrid.numberOfItems(inSection:0) != 5 || tileGrid.item(at:IndexPath(item:4,section:0)) == nil {
   RunLoop.main.run(mode:.default,before:Date(timeIntervalSinceNow:0.02));tileView.layoutSubtreeIfNeeded()
  }
  expect(tileGrid.numberOfItems(inSection:0)==5 && !pooledTiles.contains(ObjectIdentifier(tile(4))),"The late file is laid out on a brand-new tile during the scroll")
  hoverIn(4)
  expect(near(parts(4).plate.frame,tileBounds.insetBy(dx:4,dy:4)),"A tile created during a live scroll takes the page's scroll state and refuses hover")
  hoverOut(4)
  try FileManager.default.removeItem(at:lateFile)
  for _ in 0..<500 where !tilesReady() { RunLoop.main.run(mode:.default,before:Date(timeIntervalSinceNow:0.02));tileView.layoutSubtreeIfNeeded() }
  expect(tilesReady(),"Removing the late file returns the grid to its four items")
  hoverIn(0)
  expectTile(0,aspect:2,lit:false,"A reused tile during a live scroll keeps refusing hover")
  tileWindow.pointer=tile(0).convert(center,to:nil)
  NotificationCenter.default.post(name:NSScrollView.didEndLiveScrollNotification,object:NSScrollView())
  expectTile(0,aspect:2,lit:false,"Another scroll view ending")
  NotificationCenter.default.post(name:NSScrollView.didEndLiveScrollNotification,object:tileScroll)
  expectTile(0,aspect:2,lit:true,"Scroll end under the pointer")
  tileWindow.key=false
  NotificationCenter.default.post(name:NSWindow.didResignKeyNotification,object:tileWindow)
  expectTile(0,aspect:2,lit:false,"Window losing key")
  tileWindow.key=true;tileWindow.pointer=NSPoint(x:-1000,y:-1000)
  NotificationCenter.default.post(name:NSWindow.didBecomeKeyNotification,object:tileWindow)
  tileGrid.selectionIndexPaths=[IndexPath(item:2,section:0)]
  expectTile(2,aspect:0.5,lit:true,"Selected tall image")
  expect(parts(2).plate.borderWidth==(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1:0),"Selection keeps a focus border only for Increase Contrast")
  tileGrid.selectionIndexPaths=[]
  expectTile(2,aspect:0.5,lit:false,"Deselected tall image")
  tileGrid.selectionIndexPaths=[IndexPath(item:2,section:0)]
  tileWindow.pointer=tile(0).convert(center,to:nil);hoverIn(0)
  expectTile(0,aspect:2,lit:true,"Hovered wide image before its file changes")
  for (name,width,height,age) in [("wide.png",300,100,0.0),("tall.png",100,300,120.0)] {
   let file=tileFolder.appendingPathComponent(name);try tilePNG(width,height).write(to:file)
   try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:2_300_000_000-age)],ofItemAtPath:file.path)
  }
  func arrived()->Bool {
   guard tileGrid.numberOfItems(inSection:0)==4, !parts(0).artwork.isHidden, !parts(2).artwork.isHidden else { return false }
   let wide=parts(0).artwork.bounds,tall=parts(2).artwork.bounds
   return abs(wide.width/wide.height-3)<0.01 && abs(tall.width/tall.height-1.0/3)<0.01
  }
  for _ in 0..<500 where !arrived() { RunLoop.main.run(mode:.default,before:Date(timeIntervalSinceNow:0.02));tileView.layoutSubtreeIfNeeded() }
  expect(arrived(),"The replaced files' new thumbnails arrive")
  expect(tileGrid.selectionIndexPaths==[IndexPath(item:2,section:0)] && tileGrid.item(at:IndexPath(item:2,section:0))?.isSelected==true,
         "A thumbnail arrival keeps the keyboard selection")
  expectTile(2,aspect:1.0/3,lit:true,"The selected tile after its thumbnail arrives")
  expectTile(0,aspect:3,lit:true,"The hovered tile after its thumbnail arrives")
  hoverOut(0);tileWindow.pointer=NSPoint(x:-1000,y:-1000)
  tileGrid.selectionIndexPaths=[IndexPath(item:0,section:0)]
  tileGrid.onActivate?()
  for _ in 0..<250 where tileWindow.childWindows?.count != 1 { RunLoop.main.run(mode:.default,before:Date(timeIntervalSinceNow:0.02)) }
  let tilePreview=tileWindow.childWindows?.first?.windowController as? DownloadLibraryPreview
  let previewSource=tilePreview?.sourceRect?()
  expect(previewSource != nil && near(previewSource!,tile(0).convert(fitted(3,lit:true).artwork,to:nil)),
         "The preview opens from the selected tile's drawn thumbnail, not the cell or paper")
  tileView.invalidate()
  expect(tileWindow.childWindows?.isEmpty != false,"Retiring Media closes the tile-opened preview")
  for dark in [false,true] {
   tileView.appearance=NSAppearance(named:dark ? .darkAqua:.aqua);tileView.palette=ThemeChromePalette(theme:SpaceTheme(),isDark:dark)
   expect(tileSearch.placeholderString=="Search Media…" && tileSearch.placeholderAttributedString?.string=="Search Media…",
          "A theme change keeps the Media search placeholder")
  }
  NotificationCenter.default.post(name:NSScrollView.willStartLiveScrollNotification,object:tileScroll)
  tileWindow.contentView=nil;tileWindow.contentView=tileView
  for _ in 0..<500 where !tilesReady() { RunLoop.main.run(mode:.default,before:Date(timeIntervalSinceNow:0.02));tileView.layoutSubtreeIfNeeded() }
  expect(tilesReady(),"Media reloads its tiles when it returns to the window")
  hoverIn(0)
  expect(near(parts(0).plate.frame,tileBounds),"Media leaving its window mid-scroll does not leave its tiles refusing hover")
  hoverOut(0)
  tileWindow.contentView=nil;tileWindow.close()
  capturesFingerprintWindow.contentView=nil;capturesFingerprintWindow.close()
  var privateMediaValid=true
  let privateMediaSource=ExternalMediaLibrary(directory:store.capturesDirectory(for:profile),preferencesAreEphemeral:true,systemFolders:{[]})
  let mediaContext=LibraryView.PrivateMediaContext(store:store,profileID:profile,media:privateMediaSource,isValid:{privateMediaValid})
  let mediaRail=LibraryView(store:privateStore,kind:.downloads,profileID:privateID,downloadStore:store,privateMediaContext:mediaContext)
  expect(!all(mediaRail).contains{$0 is CaptureLibraryView},"Private Downloads does not eagerly initialize Media")
  mediaRail.show(.captures)
  expect(mediaRail.kind == .captures && all(mediaRail).contains{$0 is CaptureLibraryView},"Private Media creates the explicit parent catalog only on selection")
  let privateMedia=all(mediaRail).compactMap{$0 as? CaptureLibraryView}.first!
  expect(!all(privateMedia).compactMap{$0 as? NSButton}.contains{$0.title=="Folders…"},"Media has no header folder button")
  expect(all(privateMedia).compactMap{$0 as? NSCollectionView}.first?.accessibilityCustomActions()?.contains{$0.name=="Manage Media Folders"}==true,
         "Private Media exposes the window-owned folder preferences")
  let mediaButtons=all(mediaRail).compactMap{$0 as? NSButton}
  expect(mediaButtons.first{$0.title=="Media"}?.isHidden==false && mediaButtons.first{$0.title=="Downloads"}?.isHidden==false,
         "Private Media and Downloads share the visible Library rail")
  expect(mediaButtons.filter{["Easels & Notes","Archived Tabs","Spaces"].contains($0.title)}.allSatisfy(\.isHidden),
         "Unimplemented private documents and excluded categories stay hidden")
  expect(!FileManager.default.fileExists(atPath:privateDirectory.path),"Private Media does not create a private profile directory")
  privateMediaValid=false
  _=privateStore.open("https://private-media-invalid.example.invalid")
  drainMain()
  expect(privateMedia.isHidden && all(mediaRail).compactMap{$0 as? DownloadLibraryView}.contains{!$0.isHidden},
         "Invalid private Media context falls through to Downloads on store publish")
  mediaRail.show(.downloads);mediaRail.show(.captures)
  expect(mediaRail.kind == .downloads,"Retired parent context cannot reopen Media")
  let privateRail=LibraryView(store:privateStore,kind:.documents,profileID:privateID)
  let privateWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:512,height:590),styleMask:[.titled],backing:.buffered,defer:false)
  privateWindow.contentView=privateRail
  privateRail.palette=ThemeChromePalette(theme:SpaceTheme(),isDark:true)
  privateRail.layoutSubtreeIfNeeded()
  expect(privateRail.kind == .downloads,"Private Library normalizes initial entry to Downloads only")
  expect(privateRail.accessibilityLabel()=="Downloads","Private rail names the shared Downloads presentation accessibly")
  expect(!all(privateRail).contains{$0 is CaptureLibraryView || $0 is DocumentsLibraryView},"Private rail never instantiates persistent media or document catalogs")
  for kind:LibraryView.Kind in [.archive,.captures,.documents] {
   privateRail.show(kind)
   expect(privateRail.kind == .downloads,"Private rail refuses unrelated durable category")
  }
  let privateButtons=all(privateRail).compactMap{$0 as? NSButton}
  expect(privateButtons.first{$0.title=="Downloads"}?.isHidden==false,"Original Downloads entry remains visible in private rail")
  expect(privateButtons.filter{["Media","Easels & Notes","Archived Tabs","Spaces"].contains($0.title)}.allSatisfy(\.isHidden),"Unowned categories remain hidden")
  let privateView=all(privateRail).compactMap{$0 as? DownloadLibraryView}.first!
  let privateTable=all(privateRail).compactMap{$0 as? DownloadLibraryTable}.first!
  privateTable.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
  var privateActions:[DownloadLibraryIdentity]=[]
  privateRail.onDownloadAction={item,_ in privateActions.append(DownloadLibraryIdentity(item));return true}
  let privateOpen=privateTable.makeMenu!()!.items.first{$0.title=="Open"}!
  _=NSApp.sendAction(privateOpen.action!,to:privateOpen.target,from:privateOpen)
  expect(privateActions.count==1 && privateActions[0].profile==privateID,"Actual private Library action preserves original memory profile and item")
  privateRail.downloadFileURL={_ in privateDirectory.appendingPathComponent("private.pdf")}
  let privateDrag=privateView.tableView(privateTable,pasteboardWriterForRow:1) as! NSPasteboardItem
  privateStore.clearPrivateDownloads();privateRail.setDownloadsLoading(count:0,message:nil)
  _=NSApp.sendAction(privateOpen.action!,to:privateOpen.target,from:privateOpen)
  expect(privateActions.count==1,"Context destruction expires retained private action")
  expect(privateDrag.string(forType:.fileURL)==nil,"Context destruction expires undelivered private file provider")
  expect(privateTable.selectedRowIndexes.isEmpty,"Context destruction clears private native selection")
  privateRecord["itemIdentity"]="private-lease-2";privateStore.recordPrivateDownload(privateRecord)
  privateRail.setDownloadsLoading(count:0,message:nil)
  privateTable.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
  let remove=privateTable.makeMenu!()!.items.first{$0.title=="Hide from Parc"}!
  _=NSApp.sendAction(remove.action!,to:remove.target,from:remove)
  expect(privateWindow.attachedSheet == nil && privateActions.count==2 && privateActions.last?.guid=="private-original","Private Hide dispatches directly through its original manager")
  privateWindow.contentView=nil
  expect(privateWindow.attachedSheet==nil,"Private rail retirement introduces no confirmation owner")
  privateStore.clearPrivateDownloads();try privateStore.save()
  expect(!FileManager.default.fileExists(atPath:privateDirectory.path),"Private rows, Library layout/palette and save create no persistent directories")
  let regularCount=store.state.downloads.count;store.clearPrivateDownloads()
  expect(store.state.downloads.count==regularCount,"Private teardown cannot clear ordinary catalog")
  expect(!store.state.downloads.contains{$0.nativeID=="private-original"},"Private view and teardown never leak rows into regular catalog")
  let mergedDirectory=directory.appendingPathComponent("merged",isDirectory:true)
  let merged=try BrowserStore(directory:mergedDirectory)
  let mergedProfile=merged.activeSpace.profileID
  let mergedPath=merged.independentEngineProfilePath(for:mergedProfile)
  var sharedRecord:[String:Any] = ["id":"same-guid","profilePath":mergedPath,"offTheRecord":false,
   "name":"Ordinary fixture.pdf","path":"/not-opened/ordinary.pdf","status":"completed","available":true,
   "itemIdentity":"same-incarnation","canOpen":true,"canCopyFile":true,"canRemove":true,"startedAt":1000]
  merged.recordDownload(sharedRecord)
  sharedRecord["offTheRecord"]=true;sharedRecord["name"]="Alpha private fixture.pdf"
  sharedRecord["path"]="/not-opened/secret-alpha.pdf";sharedRecord["sourceURL"]="https://example.invalid/private-secret"
  merged.recordTransientDownload(sharedRecord,contextID:"alpha")
  sharedRecord["name"]="Beta private fixture.pdf"
  merged.recordTransientDownload(sharedRecord,contextID:"beta")
  expect(merged.downloadItems.count==3 && merged.state.downloads.count==1,"Actual shared projection merges normal and both original OTR contexts without durable insertion")
  expect(Set(merged.downloadItems.map(\.id)).count==3,"Same manager GUID in regular and two private contexts has three original row identities")
  expect(Set(merged.downloadItems.map(DownloadLibraryIdentity.init)).count==3,"Selection leases distinguish context even with the same GUID and incarnation")
  expect(merged.transientDownloads.allSatisfy{$0.profileID==mergedProfile},"Private filtering uses actual parent Profile identity")
  let alpha=merged.transientDownloads.first{$0.privateContextID=="alpha"}!
  expect(DownloadLibrarySelection.eligible(alpha,.openSource,spaces:[]),"Live private source URL is not gated on an unrelated regular Space")
  var ordinarySource=merged.state.downloads[0];ordinarySource.sourceURL=alpha.sourceURL
  expect(!DownloadLibrarySelection.eligible(ordinarySource,.openSource,spaces:[]),"Ordinary source URL still requires its actual regular Space")
  do { _=try JSONEncoder().encode(alpha);expect(false,"Private record cannot be serialized") }
  catch { expect(true,"Explicit serialization refuses private record") }
  try merged.save()
  let reopened=try BrowserStore(directory:mergedDirectory)
  expect(reopened.downloadItems.count==1 && reopened.transientDownloads.isEmpty,"Reopened real store contains only ordinary manager history")
  let persisted=try JSONEncoder().encode(merged.state)
  let persistedText=String(decoding:persisted,as:UTF8.self)
  expect(!persistedText.contains("private-secret") && !persistedText.contains("secret-alpha") && !persistedText.contains("Alpha private"),"Durable BrowserState contains no private URL/path/title")
  var refused=sharedRecord;refused["offTheRecord"]=false
  merged.recordTransientDownload(refused,contextID:"not-private")
  refused=sharedRecord;refused["profilePath"]=mergedPath+"-other"
  merged.recordTransientDownload(refused,contextID:"wrong-profile")
  merged.recordTransientDownload(sharedRecord,contextID:"")
  privateStore.recordTransientDownload(sharedRecord,contextID:"wrong-store")
  expect(merged.transientDownloads.count==2 && privateStore.transientDownloads.isEmpty,"Shared transient endpoint rejects regular, unknown Profile, empty context and per-window private stores")
  let mergedPrivateDirectory=directory.appendingPathComponent("never-created-merged-private",isDirectory:true)
  let mergedPrivate=BrowserStore(privateParentProfileID:mergedProfile,engineProfilePath:mergedPath,
    directory:mergedPrivateDirectory,settings:merged.state.settings)
  let sharedPrivateRail=LibraryView(store:mergedPrivate,kind:.downloads,profileID:mergedPrivate.activeSpace.profileID,downloadStore:merged)
  let sharedPrivateWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:512,height:590),styleMask:[.titled],backing:.buffered,defer:false)
  sharedPrivateWindow.contentView=sharedPrivateRail
  let sharedRegular=DownloadLibraryView(store:merged,ownerValid:{true})
  let sharedRegularWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:512,height:590),styleMask:[.titled],backing:.buffered,defer:false)
  sharedRegularWindow.contentView=sharedRegular
  let sharedPrivateView=all(sharedPrivateRail).compactMap{$0 as? DownloadLibraryView}.first!
  let sharedViews=[sharedRegular,sharedPrivateView]
  var mergedActions:[DownloadLibraryIdentity]=[]
  sharedRegular.onAction={item,_ in mergedActions.append(DownloadLibraryIdentity(item));return true}
  sharedPrivateRail.onDownloadAction={item,_ in mergedActions.append(DownloadLibraryIdentity(item));return true}
  var heldMenus:[NSMenuItem]=[]
  var heldDrags:[NSPasteboardItem]=[]
  for sharedView in sharedViews {
   let sharedTable=all(sharedView).compactMap{$0 as? DownloadLibraryTable}.first!
   expect(sharedView.numberOfRows(in:sharedTable)==4,"Both physical-window presentations contain normal and private rows under one date")
   let sharedSearch=all(sharedView).compactMap{$0 as? NSTextField}.first{$0.accessibilityLabel()=="Search Downloads"}!
   sharedSearch.stringValue="Alpha private"
   sharedView.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification))
   sharedTable.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
   let held=sharedTable.makeMenu!()!.items.first{$0.title=="Open"}!
   heldMenus.append(held);invoke(held)
   sharedView.fileURL={_ in directory.appendingPathComponent("not-opened-alpha.pdf")}
   heldDrags.append(sharedView.tableView(sharedTable,pasteboardWriterForRow:1) as! NSPasteboardItem)
   let remove=sharedTable.makeMenu!()!.items.first{$0.title=="Hide from Parc"}!
   invoke(remove)
   expect(sharedView.window?.attachedSheet == nil,"Each original presentation dispatches directly without a fabricated confirmation")
  }
  expect(mergedActions.count==4 && mergedActions.allSatisfy{$0==DownloadLibraryIdentity(alpha)},"Both actual views dispatch the same original private context/item lease")
  merged.retireTransientDownloads(contextID:"alpha")
  for sharedView in sharedViews {
   sharedView.setLoading(count:0,message:nil)
   let sharedTable=all(sharedView).compactMap{$0 as? DownloadLibraryTable}.first!
   expect(sharedTable.selectedRowIndexes.isEmpty && sharedView.window?.attachedSheet==nil,"Native context retirement clears the original selection without altering unrelated sheets")
  }
  for held in heldMenus {invoke(held)}
  expect(mergedActions.count==4,"Retained menu callbacks cannot act after original context retirement")
  expect(heldDrags.allSatisfy{$0.string(forType:.fileURL)==nil},"Retired private context cannot publish lazy outgoing file offers")
  expect(merged.downloadItems.count==2 && merged.state.downloads.count==1,"One private teardown preserves other live OTR and ordinary records")
  merged.reconcileTransientDownloads(contextID:"beta",nativeIDs:[])
  expect(merged.transientDownloads.isEmpty && merged.state.downloads.count==1,"Authoritative private reconciliation only removes that manager's transient records")
  sharedRecord["removed"]=false;merged.recordTransientDownload(sharedRecord,contextID:"gamma")
  sharedRecord["removed"]=true;merged.recordTransientDownload(sharedRecord,contextID:"gamma")
  expect(merged.transientDownloads.isEmpty,"Actual manager removal withdraws original private row")
  sharedPrivateWindow.contentView=nil;sharedRegularWindow.contentView=nil
  try mergedPrivate.save()
  expect(!FileManager.default.fileExists(atPath:mergedPrivateDirectory.path),"Merged private Downloads does not create persistent catalogs or window state")
  var emptyOwnerValid=true
  SystemOverrides.reduceMotion=false
  let emptyMotion=DownloadEmptyContentView(ownerValid:{emptyOwnerValid})
  emptyMotion.frame=NSRect(x:0,y:0,width:300,height:148)
  emptyMotion.show(.empty)
  expect(emptyMotion.layer?.animationKeys()?.isEmpty != false,"Detached empty content cannot start an entrance")
  let emptyParent=LayoutView(frame:NSRect(x:0,y:0,width:400,height:300))
  emptyParent.isHidden=true;emptyParent.addSubview(emptyMotion)
  let emptyWindow=NSWindow(contentRect:emptyParent.frame,styleMask:[.titled],backing:.buffered,defer:false)
  emptyWindow.isReleasedWhenClosed=false;emptyWindow.contentView=emptyParent
  expect(emptyMotion.layer?.animationKeys()?.isEmpty != false,"Hidden ancestor defers the actual attached empty-content entrance")
  emptyParent.isHidden=false
  let entrance=emptyMotion.layer?.animation(forKey:"empty.translation") as? CASpringAnimation
  let opacity=emptyMotion.layer?.animation(forKey:"empty.opacity") as? CABasicAnimation
  expect(entrance != nil && opacity != nil,"Unhiding the original subtree starts its two distinct native transactions")
  expect(entrance?.fromValue as? Int == 16 && entrance?.toValue as? Int == 0,"Whole empty content enters from the recovered sixteen-point offset")
  expect(abs((entrance?.stiffness ?? 0)-pow(2 * .pi / 0.35,2)) < 0.0001 && abs((entrance?.damping ?? 0)-4 * .pi * 0.6 / 0.35) < 0.0001,"Native spring carries the original response and damping")
  expect(opacity?.fromValue as? Int == 0 && opacity?.toValue as? Int == 1 && opacity?.duration==0.125,"Empty content independently fades to its final opacity")
  expect(emptyMotion.layer?.opacity==1 && CATransform3DIsIdentity(emptyMotion.layer!.transform),"Animation model values already hold the complete final presentation")
  let unrelated=CABasicAnimation(keyPath:"shadowOpacity");unrelated.duration=10
  emptyMotion.layer?.add(unrelated,forKey:"unrelated")
  emptyMotion.settle();emptyMotion.show(.empty)
  expect(emptyMotion.layer?.animation(forKey:"empty.translation")==nil && emptyMotion.layer?.animation(forKey:"unrelated") != nil,"Metadata refresh neither replays the entrance nor cancels unrelated layer ownership")
  emptyMotion.show(.status)
  expect(!emptyMotion.isHidden && emptyMotion.layer?.animation(forKey:"empty.opacity")==nil,"Loading and failure remain visible without borrowing the empty-state animation")
  emptyMotion.show(.empty)
  expect(emptyMotion.layer?.animation(forKey:"empty.translation") != nil,"Resolving status to actual empty content creates its own appearance")
  emptyMotion.setFrameSize(NSSize(width:320,height:148))
  expect(emptyMotion.layer?.animation(forKey:"empty.translation")==nil && emptyMotion.layer?.opacity==1,"Geometry change settles the current entrance without replay or transparent content")
  emptyMotion.show(.hidden);emptyMotion.show(.empty)
  SystemOverrides.reduceMotion=true
  NSWorkspace.shared.notificationCenter.post(name:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil)
  expect(emptyMotion.layer?.animation(forKey:"empty.translation")==nil && emptyMotion.layer?.animation(forKey:"empty.opacity")==nil,"Accessibility policy change immediately settles both original transactions")
  emptyMotion.show(.hidden);emptyMotion.show(.empty)
  expect(emptyMotion.layer?.animation(forKey:"empty.translation")==nil && !emptyMotion.isHidden,"Reduce Motion admits the real empty content without spatial motion")
  SystemOverrides.reduceMotion=false;emptyMotion.show(.hidden);emptyMotion.show(.empty)
  expect(emptyMotion.layer?.animation(forKey:"empty.translation") != nil,"A later distinct eligible appearance can animate again")
  emptyMotion.removeFromSuperview()
  expect(emptyMotion.layer?.animation(forKey:"empty.translation")==nil && emptyMotion.window==nil,"Detachment retires only that original empty-content animation")
  emptyOwnerValid=false;emptyParent.addSubview(emptyMotion)
  expect(emptyMotion.layer?.animation(forKey:"empty.translation")==nil,"A retired Library owner cannot restart empty-content presentation")
  emptyOwnerValid=true;emptyMotion.show(.status);emptyMotion.show(.empty)
  emptyWindow.close();emptyMotion.show(.status);emptyMotion.show(.empty)
  expect(emptyMotion.layer?.animation(forKey:"empty.translation")==nil,"Closed original window cannot resurrect an empty-content entrance")
  emptyWindow.contentView=nil
  let emptyStore=try BrowserStore(directory:directory.appendingPathComponent("empty-presentation",isDirectory:true))
  let emptyView=DownloadLibraryView(store:emptyStore,ownerValid:{true})
  let emptyViewWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:600),styleMask:[.titled],backing:.buffered,defer:false)
  emptyViewWindow.contentView=emptyView;emptyView.layoutSubtreeIfNeeded()
  let actualEmpty=all(emptyView).compactMap{$0 as? DownloadEmptyContentView}.first!
  expect(actualEmpty.mode == .empty && actualEmpty.subviews.count==2,"Real Library keeps its original icon and label in one empty-state animation owner")
  let emptySearch=all(emptyView).compactMap{$0 as? NSTextField}.first{$0.accessibilityLabel()=="Search Downloads"}!
  emptyViewWindow.makeFirstResponder(emptySearch)
  let emptyResponder=emptyViewWindow.firstResponder
  emptyView.setLoading(count:1,message:nil)
  expect(actualEmpty.mode == .status && actualEmpty.layer?.animation(forKey:"empty.translation")==nil,"Actual manager loading never animates as a successful empty state")
  emptyView.setLoading(count:0,message:"Could not load downloads")
  expect(actualEmpty.mode == .status,"Actual load failure remains a nonanimated status owner")
  emptyView.setLoading(count:0,message:nil)
  expect(actualEmpty.mode == .empty && actualEmpty.layer?.animation(forKey:"empty.translation") != nil,"Actual loaded-empty publication runs the recovered whole-content entrance")
  expect(emptyViewWindow.firstResponder === emptyResponder,"Empty-state changes never take Search or page input focus")
  emptyView.invalidate()
  expect(actualEmpty.layer?.animation(forKey:"empty.translation")==nil,"Library invalidation settles its actual empty subtree")
  emptyViewWindow.contentView=nil
  SystemOverrides.reduceMotion=nil
  let activationDirectory=directory.appendingPathComponent("activation",isDirectory:true)
  try FileManager.default.createDirectory(at:activationDirectory,withIntermediateDirectories:true)
  let textURL=activationDirectory.appendingPathComponent("original.txt")
  try Data("Temporary component file".utf8).write(to:textURL)
  let imageURL=activationDirectory.appendingPathComponent("original.png")
  let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:2,pixelsHigh:2,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
  try bitmap.representation(using:.png,properties:[:])!.write(to:imageURL)
  let movieURL=activationDirectory.appendingPathComponent("original.mov")
  let pdfURL=activationDirectory.appendingPathComponent("original.pdf")
  try Data().write(to:movieURL);try Data().write(to:pdfURL)
  expect(DownloadFileActivation.inspect(imageURL) == .preview,"Readable image resource admits original single-click preview")
  expect(DownloadFileActivation.inspect(movieURL) == .preview && DownloadFileActivation.inspect(pdfURL) == .preview,"Original movie/PDF type conformance shares media preview")
  expect(DownloadFileActivation.inspect(textURL) == .open,"Text uses the original completed-file Open branch, not broad Quick Look support")
  expect(DownloadFileActivation.inspect(activationDirectory) == .open,"Directory is excluded from original media preview policy")
  expect(DownloadFileActivation.inspect(activationDirectory.appendingPathComponent("missing.png")) == .unavailable,"Missing previewable media cannot silently fall through to file Open")
  expect(DownloadFileActivation.inspect(URL(string:"https://example.invalid/file.png")!) == .unavailable,"A source URL never becomes a local file activation")
  let pointerStore=try BrowserStore(directory:directory.appendingPathComponent("pointer-store",isDirectory:true))
  let pointerPath=pointerStore.independentEngineProfilePath(for:pointerStore.state.profiles[0].id)
  func publishPointer(_ id:String="first",identity:String="original",status:String="completed",canOpen:Bool=true,canToggle:Bool=false,name:String?=nil) {
   pointerStore.recordDownload(["id":id,"profilePath":pointerPath,"name":name ?? id,"status":status,"available":true,"itemIdentity":identity,"canOpen":canOpen,"canRemove":true,"canCopyFile":status=="completed","canToggleOpen":canToggle,"startedAt":1000])
  }
  publishPointer();publishPointer("second",identity:"second")
  var pointerOwner=true,pointerURL:URL?=textURL,pointerActions:[String]=[]
  SystemOverrides.reduceMotion=true
  let pointerView=DownloadLibraryView(store:pointerStore,ownerValid:{pointerOwner})
  pointerView.frame=NSRect(x:0,y:0,width:400,height:600)
  let pointerWindow=NSWindow(contentRect:pointerView.frame,styleMask:.titled,backing:.buffered,defer:false)
  pointerWindow.contentView=pointerView;pointerView.layoutSubtreeIfNeeded()
  let pointerTable=all(pointerView).compactMap{$0 as? DownloadLibraryTable}.first!
  pointerView.fileURL={_ in pointerURL}
  pointerView.onAction={item,action in pointerActions.append(item.nativeID!+":"+String(describing:action));return true}
  func settlePointer(until complete:(()->Bool)?=nil) {let until=Date().addingTimeInterval(complete == nil ? 0.15 : 2);while Date()<until {if complete?()==true {return};_=RunLoop.main.run(mode:.default,before:Date().addingTimeInterval(0.01))}}
  func clickPointer(_ row:Int=1) {let commit=pointerTable.prepareClick?(row);pointerTable.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false);pointerWindow.makeFirstResponder(pointerTable);commit?()}
  expect(pointerTable.prepareClick?(0)==nil,"Date heading has no original click lease")
  expect(pointerTable.action==#selector(DownloadLibraryTable.activateOriginalClick) && pointerTable.target === pointerTable,"Actual view registers its native single-click owner")
  clickPointer();settlePointer(until:{pointerActions.count==1})
  expect(pointerActions==["first:open"],"Actual completed non-media click reaches exact original Open callback once")
  pointerURL=imageURL;clickPointer();settlePointer(until:{pointerWindow.childWindows?.count==1})
  expect(pointerWindow.childWindows?.count==1 && pointerActions.count==1,"Actual readable media click presents owned preview without dispatching Open")
  pointerView.invalidate()
  expect(pointerWindow.childWindows?.isEmpty != false,"Original view retirement removes the click-owned preview")
  pointerURL=activationDirectory.appendingPathComponent("missing.png");clickPointer();settlePointer()
  expect(pointerActions.count==1 && pointerWindow.childWindows?.isEmpty != false,"Missing media refuses both preview and file output")
  expect(all(pointerView).compactMap{$0 as? NSTextField}.contains{$0.stringValue=="This file is no longer available to preview."},"Missing media publishes honest original-item failure")
  pointerURL=textURL;publishPointer(status:"downloading",canToggle:true);pointerView.setLoading(count:0,message:nil)
  clickPointer();expect(pointerActions.last=="first:toggleOpen" && pointerActions.count==2,"Unfinished original delegates Open When Finished to real manager action")
  publishPointer(status:"downloading",canToggle:false);pointerView.setLoading(count:0,message:nil)
  clickPointer();expect(pointerActions.count==2,"Restricted unfinished original never manufactures a toggle")
  publishPointer();pointerView.setLoading(count:0,message:nil)
  let staleClick=pointerTable.prepareClick?(1);publishPointer(identity:"replacement");pointerView.setLoading(count:0,message:nil)
  pointerTable.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false);staleClick?();settlePointer()
  expect(pointerActions.count==2,"Replacement manager incarnation cannot inherit a pretracking original click")
  publishPointer();pointerView.setLoading(count:0,message:nil)
  clickPointer();pointerTable.selectRowIndexes(IndexSet(integer:2),byExtendingSelection:false);settlePointer()
  expect(pointerActions.count==2,"Selection intervention retires asynchronous metadata delivery")
  clickPointer();pointerURL=imageURL;settlePointer()
  expect(pointerActions.count==2 && pointerWindow.childWindows?.isEmpty != false,"A changed current file path cannot retarget pending original metadata")
  pointerURL=textURL;clickPointer();pointerView.invalidate();settlePointer()
  expect(pointerActions.count==2,"Category/context retirement cancels pending click output")
  clickPointer();pointerOwner=false;settlePointer();pointerOwner=true
  expect(pointerActions.count==2,"Retired original owner suppresses pending file output")
  clickPointer();pointerView.setOperation(pointerStore.state.downloads.first!,message:"Busy");settlePointer()
  expect(pointerActions.count==2,"Accepted item operation cancels pending click output")
  pointerView.setOperation(pointerStore.state.downloads.first!,message:nil)
  clickPointer();_=pointerTable.makeMenu?();settlePointer()
  expect(pointerActions.count==2,"Opening the original context menu retires pending single-click publication")
  clickPointer();pointerWindow.makeFirstResponder(all(pointerView).compactMap{$0 as? NSTextField}.first{$0.accessibilityLabel()=="Search Downloads"}!);settlePointer()
  expect(pointerActions.count==2,"Intervening native Search focus cannot be stolen by late metadata completion")
  pointerWindow.makeFirstResponder(pointerTable)
  clickPointer();publishPointer(name:"Renamed while inspecting");pointerView.setLoading(count:0,message:nil);settlePointer(until:{pointerActions.count==3})
  expect(pointerActions.count==3 && pointerActions.last=="first:open","Same original identity survives harmless name/progress refresh")
  publishPointer(canOpen:false);pointerView.setLoading(count:0,message:nil);clickPointer();settlePointer()
  expect(pointerActions.count==3,"Final original capability still refuses completed file Open")
  pointerView.invalidate();pointerWindow.contentView=nil
  SystemOverrides.reduceMotion=nil
  if Bundle.main.object(forInfoDictionaryKey:"ParcEmptyComponent") as? Bool == true {
   for owned in NSApp.windows { owned.orderOut(nil) }
   SystemOverrides.reduceMotion=false
   let sample=DownloadLibraryView(store:emptyStore,ownerValid:{true})
   sample.appearance=NSAppearance(named:.aqua);sample.palette=ThemeChromePalette(theme:SpaceTheme(),isDark:false)
   let sampleWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:600),styleMask:[.titled,.closable],backing:.buffered,defer:false)
   sampleWindow.isReleasedWhenClosed=false;sampleWindow.contentView=sample
   sampleWindow.title="Downloads Empty Component — synthetic store"
   sampleWindow.appearance=NSAppearance(named:.aqua)
   sample.wantsLayer=true
   sample.effectiveAppearance.performAsCurrentDrawingAppearance {sample.layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor}
   sample.setLoading(count:1,message:nil);sample.layoutSubtreeIfNeeded()
   let closeToken=NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:sampleWindow,queue:.main) {_ in MainActor.assumeIsolated {NSApp.terminate(nil)}}
   defer {NotificationCenter.default.removeObserver(closeToken)}
   NSApp.setActivationPolicy(.regular);sampleWindow.center();sampleWindow.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
   DispatchQueue.main.asyncAfter(deadline:.now()+1) {sample.setLoading(count:0,message:nil)}
   DispatchQueue.main.asyncAfter(deadline:.now()+45) {sample.invalidate();sampleWindow.close();NSApp.terminate(nil)}
   NSApp.run()
  }
  if Bundle.main.object(forInfoDictionaryKey:"ParcFilterComponent") as? Bool == true {
   for owned in NSApp.windows { owned.orderOut(nil) }
   let sampleRoot=LayoutView(frame:NSRect(x:0,y:0,width:640,height:590))
   let sampleWindow=NSWindow(contentRect:sampleRoot.frame,styleMask:[.titled,.closable],backing:.buffered,defer:false)
   sampleWindow.isReleasedWhenClosed=false;sampleWindow.contentView=sampleRoot
   sampleWindow.title="Downloads Component — synthetic records"
   sampleWindow.appearance=NSAppearance(named:.aqua);sampleRoot.appearance=NSAppearance(named:.aqua)
   SystemOverrides.reduceMotion=true
   for index in 0..<2 {
    let sample=DownloadLibraryView(store:filterStore,ownerValid:{true})
    sample.frame=NSRect(x:CGFloat(index)*320,y:0,width:304,height:590)
    sample.appearance=NSAppearance(named:.aqua);sample.palette=ThemeChromePalette(theme:SpaceTheme(),isDark:false)
    sampleRoot.addSubview(sample);sample.layoutSubtreeIfNeeded()
    sample.layoutSubtreeIfNeeded()

   }
   sampleRoot.wantsLayer=true
   sampleRoot.effectiveAppearance.performAsCurrentDrawingAppearance {sampleRoot.layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor}
   let closeToken=NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:sampleWindow,queue:.main) {_ in MainActor.assumeIsolated {NSApp.terminate(nil)}}
   defer {NotificationCenter.default.removeObserver(closeToken)}
   NSApp.setActivationPolicy(.regular);sampleWindow.center();sampleWindow.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
   DispatchQueue.main.asyncAfter(deadline:.now()+60) {sampleWindow.orderOut(nil);NSApp.terminate(nil)}
   NSApp.run()
  }
  if Bundle.main.object(forInfoDictionaryKey:"ParcMergedDownloadsComponent") as? Bool == true {
   sharedRecord["removed"]=false;sharedRecord["name"]="Private fixture.pdf"
   merged.recordTransientDownload(sharedRecord,contextID:"visible-private")
   let visibleMerged=LibraryView(store:mergedPrivate,kind:.downloads,profileID:mergedPrivate.activeSpace.profileID,downloadStore:merged)
   visibleMerged.frame=NSRect(x:0,y:0,width:512,height:590)
   visibleMerged.appearance=NSAppearance(named:.darkAqua)
   visibleMerged.palette=ThemeChromePalette(theme:SpaceTheme(),isDark:true)
   sharedPrivateWindow.contentView=visibleMerged;sharedPrivateWindow.setContentSize(visibleMerged.frame.size)
   sharedPrivateWindow.appearance=NSAppearance(named:.darkAqua)
   sharedPrivateWindow.title="Merged Downloads Component — synthetic records"
   NSApp.setActivationPolicy(.regular)
   sharedPrivateWindow.center();sharedPrivateWindow.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
   DispatchQueue.main.asyncAfter(deadline:.now()+60) { sharedPrivateWindow.orderOut(nil);NSApp.terminate(nil) }
   NSApp.run()
  }
  if ProcessInfo.processInfo.environment["PARC_PRIVATE_COMPONENT_PREVIEW"] == "1" {
   privateStore.recordPrivateDownload(privateRecord)
   let visiblePrivate=LibraryView(store:privateStore,kind:.downloads,profileID:privateID)
   visiblePrivate.frame=NSRect(x:0,y:0,width:512,height:590)
   visiblePrivate.appearance=NSAppearance(named:.darkAqua)
   visiblePrivate.palette=ThemeChromePalette(theme:SpaceTheme(),isDark:true)
   privateWindow.contentView=visiblePrivate;privateWindow.setContentSize(visiblePrivate.frame.size)
   privateWindow.appearance=NSAppearance(named:.darkAqua)
   privateWindow.title="Private Downloads Component — synthetic metadata"
   NSApp.setActivationPolicy(.regular)
   privateWindow.center();privateWindow.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
   DispatchQueue.main.asyncAfter(deadline:.now()+60) { privateWindow.orderOut(nil);NSApp.terminate(nil) }
   NSApp.run()
  }
  if Bundle.main.object(forInfoDictionaryKey:"ParcPreviewComponent") as? Bool == true {
   let fixture=directory.appendingPathComponent("Preview fixture.txt")
   try "Downloads preview\n\nDisposable native component. No personal file or browser action.\n\nThe original window owns this Quick Look view.".write(to:fixture,atomically:true,encoding:.utf8)
   layoutWindow.setContentSize(NSSize(width:1000,height:700));layoutWindow.center()
   layoutWindow.title="Downloads Preview Component — synthetic fixture"
   layoutWindow.appearance=NSAppearance(named:.darkAqua)
   SystemOverrides.reduceMotion=false
   let visible=DownloadLibraryPreview()
   visible.sourceImage=NSImage(systemSymbolName:"doc.text",accessibilityDescription:nil)
   visible.sourceRect={NSRect(x:24,y:80,width:32,height:32)}
   visible.onMenu={let menu=NSMenu();let item=NSMenuItem(title:"Fixture action (disabled)",action:nil,keyEquivalent:"");item.isEnabled=false;menu.addItem(item);return menu}
   visible.update(url:fixture,title:"Preview fixture.txt",ordinal:1,count:3,canOpen:false,canMovePrevious:false,canMoveNext:true)
   NSApp.setActivationPolicy(.regular);layoutWindow.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
   visible.present(on:layoutWindow)
   DispatchQueue.main.asyncAfter(deadline:.now()+45) {visible.close();layoutWindow.orderOut(nil);NSApp.terminate(nil)}
   NSApp.run()
  }
  if ProcessInfo.processInfo.environment["PARC_COMPONENT_PREVIEW"] == "1" || Bundle.main.object(forInfoDictionaryKey:"ParcComponentPreview") as? Bool == true {
   layoutView.frame.size=NSSize(width:400,height:590)
   layoutView.appearance=NSAppearance(named:.darkAqua)
   layoutView.palette=ThemeChromePalette(theme:SpaceTheme(),isDark:true)
   layoutWindow.appearance=NSAppearance(named:.darkAqua)
   layoutWindow.title="Downloads Component — synthetic fixtures"
   NSApp.setActivationPolicy(.regular)
   layoutWindow.center();layoutWindow.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
   DispatchQueue.main.asyncAfter(deadline:.now()+45) { layoutWindow.orderOut(nil); NSApp.terminate(nil) }
   NSApp.run()
  }
  print("Download Library view: \(count) assertions passed")
 }
}

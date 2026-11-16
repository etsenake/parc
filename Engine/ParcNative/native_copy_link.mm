#import "native_appkit_page.h"
#import "window_security_reservation.h"
#include "native_page_retirement.h"
#include "parc/native/native_internal_urls.h"
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversion_utils.h"
#include "base/strings/utf_string_conversions.h"
#include "base/timer/timer.h"
#include "chrome/browser/enterprise/data_protection/data_protection_clipboard_utils.h"
#include "components/shared_highlighting/core/common/disabled_sites.h"
#include "components/shared_highlighting/core/common/fragment_directives_utils.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/clipboard_types.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "services/service_manager/public/cpp/interface_provider.h"
#include "third_party/blink/public/mojom/link_to_text/link_to_text.mojom.h"
#include "ui/base/clipboard/clipboard_format_type.h"
#include "ui/base/clipboard/scoped_clipboard_writer.h"
#include "ui/base/data_transfer_policy/data_transfer_endpoint.h"

namespace parc { class SharedQuoteObserver; struct SharedQuoteState; }
@interface PCNativeSharedQuoteSelection ()
- (instancetype)initWithState:(std::shared_ptr<parc::SharedQuoteState>)state;
@end
@interface PCNativeSharedQuoteObservation ()
- (instancetype)initWithContents:(content::WebContents*)contents
    changed:(void (^)(PCNativeSharedQuoteSelection*, BOOL))changed;
@end

namespace parc {
namespace {
using shared_highlighting::LinkGenerationError;
using shared_highlighting::LinkGenerationReadyStatus;

class CopyCommandWindow {
 public:
  CopyCommandWindow(PCNativePage* page, PCNativeBrowserWindow* binding, NSWindow* command)
      : page_(page), binding_(binding), owner_(binding.window), command_(command) {}
  bool Current(PCNativePage* page) const {
    PCNativeBrowserWindow* binding = binding_;
    NSWindow* owner = owner_;
    NSWindow* command = command_;
    if (!page || page != page_ || !binding || !owner || !command || command == owner ||
        binding.window != owner || page.nativeView.window != owner ||
        !owner.visible || owner.miniaturized || owner.attachedSheet ||
        !command.visible || !command.keyWindow || command.miniaturized || command.attachedSheet ||
        !NSApp.active || PCNativeWindowHasSecurityReservation(owner) ||
        PCNativeWindowHasSecurityReservation(command) ||
        [PCNativeBrowserApplication windowForNativeWindow:command] ||
        [PCNativeBrowserApplication ownerForPage:page] != binding) return false;
    id<PCNativeBrowserWindowClient> client = binding.client;
    return client && [client selectedNativePage] == page && binding.client == client &&
        binding.window == owner && page.nativeView.window == owner &&
        [PCNativeBrowserApplication ownerForPage:page] == binding;
  }
  NSWindow* window() const { return command_; }
 private:
  PCNativePage* __weak page_;
  PCNativeBrowserWindow* __weak binding_;
  NSWindow* __weak owner_;
  NSWindow* __weak command_;
};

bool CanCopy(content::WebContents* contents, PCNativeLinkCopyFormat format,
             const CopyCommandWindow* command = nullptr) {
  PCNativePage* page = contents ? ExistingNativePage(contents) : nil;
  NSWindow* window = page.nativeView.window;
  auto* frame = contents ? contents->GetPrimaryMainFrame() : nullptr;
  if (!page || page.closed || IsNativePageRetiring(page) || !window ||
      !window.visible || !NSApp.active || window.attachedSheet ||
      (command ? (format != PCNativeLinkCopyFormatPlain || !command->Current(page)) : !window.keyWindow) ||
      PCNativeWindowHasSecurityReservation(window) || page.nativeView.hiddenOrHasHiddenAncestor ||
      contents->IsBeingDestroyed() || contents->IsCrashed() ||
      contents->GetVisibility() != content::Visibility::VISIBLE || !frame ||
      !frame->IsRenderFrameLive() || !contents->GetLastCommittedURL().is_valid()) return false;
  if (format != PCNativeLinkCopyFormatQuote) return true;
  return contents->GetFocusedFrame() == frame && frame->GetView() &&
      !frame->GetView()->GetSelectedText().empty() &&
      shared_highlighting::ShouldOfferLinkToText(contents->GetLastCommittedURL());
}

std::u16string MarkdownLabel(const std::u16string& title) {
  std::u32string text;
  for (size_t i = 0; i < title.size(); ++i) {
    base_icu::UChar32 c;
    if (!base::ReadUnicodeCharacter(title, &i, &c)) c = 0xFFFD;
    text += c == '\r' || c == '\n' ? U' ' : static_cast<char32_t>(c);
  }
  auto space = [](char32_t c) { return [NSCharacterSet.whitespaceCharacterSet longCharacterIsMember:c]; };
  auto word = [](char32_t c) { return [NSCharacterSet.alphanumericCharacterSet longCharacterIsMember:c]; };
  auto entity = [&text](size_t index) {
    size_t next = index + 1;
    if (next < text.size() && text[next] == U'#') ++next;
    const size_t name = next;
    while (next < text.size() && base::IsAsciiAlphaNumeric(text[next])) ++next;
    return next > name && next < text.size() && text[next] == U';';
  };
  std::u16string label;
  for (size_t index = 0; index < text.size();) {
    const char32_t c = text[index];
    size_t end = index + 1;
    bool escaped = false;
    switch (c) {
      case U'\\': escaped = base::IsAsciiPunctuation(end < text.size() ? text[end] : U']'); break;
      case U'[': case U']': case U'<': case U'`': escaped = true; break;
      case U'&': escaped = entity(index); break;
      case U'*': case U'_': case U'~': {
        while (end < text.size() && text[end] == c) ++end;
        const char32_t before = index ? text[index - 1] : U'[', after = end < text.size() ? text[end] : U']';
        escaped = !(space(before) && space(after)) && !(c == U'_' && word(before) && word(after));
        break;
      }
    }
    for (; index < end; ++index) {
      if (escaped) label += u'\\';
      base::WriteUnicodeCharacter(static_cast<base_icu::UChar32>(text[index]), &label);
    }
  }
  return label;
}

std::u16string Markdown(const std::u16string& title, const GURL& url) {
  std::u16string label = MarkdownLabel(base::TrimWhitespace(title, base::TRIM_ALL).empty()
                                           ? base::UTF8ToUTF16(url.spec()) : title);
  std::string destination = url.spec();
  base::ReplaceSubstringsAfterOffset(&destination, 0, "(", "%28");
  base::ReplaceSubstringsAfterOffset(&destination, 0, ")", "%29");
  return u"[" + label + u"](" + base::UTF8ToUTF16(destination) + u")";
}

class CopyLink final : public content::WebContentsObserver,
                       public content::WebContentsUserData<CopyLink> {
 public:
  ~CopyLink() override { Finish(PCNativeLinkCopyResultCancelled); }
  void Start(PCNativeLinkCopyFormat format, void (^completion)(PCNativeLinkCopyResult),
             std::unique_ptr<CopyCommandWindow> command = nullptr) {
    auto alive = lifetime_.GetWeakPtr();
    Finish(PCNativeLinkCopyResultCancelled);
    if (!alive) { completion(PCNativeLinkCopyResultCancelled); return; }
    if (!CanCopy(web_contents(), format, command.get())) { completion(PCNativeLinkCopyResultUnavailable); return; }
    command_ = std::move(command);
    active_ = true;
    handler_ = [completion copy];
    format_ = format;
    window_ = ExistingNativePage(web_contents()).nativeView.window;
    document_ = web_contents()->GetPrimaryMainFrame()->GetWeakDocumentPtr();
    url_ = web_contents()->GetLastCommittedURL();
    pasteboard_change_ = NSPasteboard.generalPasteboard.changeCount;
    auto weak = callbacks_.GetWeakPtr();
    auto cancel = ^(NSNotification*) { if (weak) weak->Finish(PCNativeLinkCopyResultCancelled); };
    observers_ = [NSMutableArray array];
    for (NSNotificationName name in @[NSWindowWillCloseNotification, NSWindowDidResignKeyNotification,
          NSWindowDidMiniaturizeNotification, PCNativeWindowSecurityStateChanged]) {
      [observers_ addObject:[NSNotificationCenter.defaultCenter addObserverForName:name
          object:window_ queue:nil usingBlock:cancel]];
    }
    if (command_) {
      NSWindow* command_window = command_->window();
      for (NSNotificationName name in @[NSWindowWillCloseNotification, NSWindowDidResignKeyNotification,
            NSWindowDidMiniaturizeNotification, NSWindowWillBeginSheetNotification, PCNativeWindowSecurityStateChanged]) {
        [observers_ addObject:[NSNotificationCenter.defaultCenter addObserverForName:name
            object:command_window queue:nil usingBlock:cancel]];
      }
    }
    [observers_ addObject:[NSNotificationCenter.defaultCenter
        addObserverForName:NSApplicationDidResignActiveNotification object:NSApp queue:nil usingBlock:cancel]];
    if (format != PCNativeLinkCopyFormatQuote) {
      const GURL visible = PublicInternalURL(url_);
      Write(format == PCNativeLinkCopyFormatMarkdown ? Markdown(web_contents()->GetTitle(), visible)
                                                    : base::UTF8ToUTF16(visible.spec()));
      return;
    }
    auto* frame = document_.AsRenderFrameHostIfValid();
    selection_ = frame->GetView()->GetSelectedText();
    frame->GetRemoteInterfaces()->GetInterface(remote_.BindNewPipeAndPassReceiver());
    remote_.set_disconnect_handler(base::BindOnce(&CopyLink::Finish, weak, PCNativeLinkCopyResultUnavailable));
    timeout_.Start(FROM_HERE, base::Seconds(10),
        base::BindOnce(&CopyLink::Finish, weak, PCNativeLinkCopyResultUnavailable));
    remote_->RequestSelectorForSelection(base::BindOnce(&CopyLink::Generated, weak));
  }
 private:
  explicit CopyLink(content::WebContents* contents)
      : content::WebContentsObserver(contents), content::WebContentsUserData<CopyLink>(*contents) {}
  friend content::WebContentsUserData<CopyLink>;
  WEB_CONTENTS_USER_DATA_KEY_DECL();

  bool Current() const {
    auto* contents = web_contents();
    auto* frame = document_.AsRenderFrameHostIfValid();
    return active_ && contents && frame && frame == contents->GetPrimaryMainFrame() &&
        CanCopy(contents, format_, command_.get()) && ExistingNativePage(contents).nativeView.window == window_ &&
        contents->GetLastCommittedURL() == url_ &&
        NSPasteboard.generalPasteboard.changeCount == pasteboard_change_ &&
        (format_ != PCNativeLinkCopyFormatQuote || (frame->GetView() &&
             frame->GetView()->GetSelectedText() == selection_));
  }
  void Generated(const std::string& selector, LinkGenerationError error, LinkGenerationReadyStatus) {
    timeout_.Stop();
    remote_.reset();
    if (!Current()) { Finish(PCNativeLinkCopyResultCancelled); return; }
    if (error != LinkGenerationError::kNone || selector.empty()) {
      Finish(PCNativeLinkCopyResultUnavailable); return;
    }
    GURL result = shared_highlighting::AppendSelectors(
        shared_highlighting::RemoveFragmentSelectorDirectives(url_), {selector});
    if (!result.is_valid()) { Finish(PCNativeLinkCopyResultUnavailable); return; }
    Write(base::UTF8ToUTF16(PublicInternalURL(result).spec()));
  }
  void Write(const std::u16string& text) {
    if (!Current()) { Finish(PCNativeLinkCopyResultCancelled); return; }
    auto* frame = document_.AsRenderFrameHostIfValid();
    auto document = document_;
    ui::DataTransferEndpoint dte(url_, {.off_the_record = frame->GetBrowserContext()->IsOffTheRecord()});
    auto endpoint = content::ClipboardEndpoint::ForFrame(dte,
        base::BindRepeating([](content::WeakDocumentPtr document) -> content::BrowserContext* {
          auto* frame = document.AsRenderFrameHostIfValid();
          return frame ? frame->GetBrowserContext() : nullptr;
        }, document), *frame);
    content::ClipboardPasteData data; data.text = text;
    enterprise_data_protection::IsClipboardCopyAllowedByPolicy(endpoint,
        {.size = text.size() * sizeof(char16_t), .format_type = ui::ClipboardFormatType::PlainTextType()}, data,
        base::BindOnce(&CopyLink::PolicyResult, callbacks_.GetWeakPtr(), std::move(dte)));
  }
  void PolicyResult(ui::DataTransferEndpoint dte, const ui::ClipboardFormatType&,
                    const content::ClipboardPasteData& data, std::optional<std::u16string> replacement) {
    if (!Current()) { Finish(PCNativeLinkCopyResultCancelled); return; }
    {
      ui::ScopedClipboardWriter writer(ui::ClipboardBuffer::kCopyPaste,
          std::make_unique<ui::DataTransferEndpoint>(std::move(dte)));
      writer.WriteText(replacement ? *replacement : data.text);
    }
    Finish(replacement ? PCNativeLinkCopyResultBlocked : PCNativeLinkCopyResultCopied);
  }
  void Finish(PCNativeLinkCopyResult result) {
    callbacks_.InvalidateWeakPtrs();
    timeout_.Stop();
    if (remote_.is_bound() && remote_.is_connected()) remote_->Cancel();
    remote_.reset();
    for (id observer in observers_) [NSNotificationCenter.defaultCenter removeObserver:observer];
    observers_ = nil;
    active_ = false;
    auto handler = handler_; handler_ = nil;
    window_ = nil; command_.reset(); selection_.clear();
    if (handler) handler(result);
  }
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsInPrimaryMainFrame()) Finish(PCNativeLinkCopyResultCancelled);
  }
  void OnWebContentsLostFocus(content::RenderWidgetHost*) override { Finish(PCNativeLinkCopyResultCancelled); }
  void PrimaryPageChanged(content::Page&) override { Finish(PCNativeLinkCopyResultCancelled); }
  void WebContentsDestroyed() override { Finish(PCNativeLinkCopyResultCancelled); }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility != content::Visibility::VISIBLE) Finish(PCNativeLinkCopyResultCancelled);
  }
  void OnTextSelectionChanged(content::RenderFrameHost*, std::u16string_view) override {
    if (format_ == PCNativeLinkCopyFormatQuote) Finish(PCNativeLinkCopyResultCancelled);
  }
  bool active_ = false;
  PCNativeLinkCopyFormat format_ = PCNativeLinkCopyFormatPlain;
  std::unique_ptr<CopyCommandWindow> command_;
  NSWindow* __weak window_ = nil;
  NSMutableArray* __strong observers_ = nil;
  content::WeakDocumentPtr document_;
  GURL url_;
  std::u16string selection_;
  NSInteger pasteboard_change_ = 0;
  void (^handler_)(PCNativeLinkCopyResult) = nil;
  mojo::Remote<blink::mojom::TextFragmentReceiver> remote_;
  base::OneShotTimer timeout_;
  base::WeakPtrFactory<CopyLink> lifetime_{this};
  base::WeakPtrFactory<CopyLink> callbacks_{this};
};
WEB_CONTENTS_USER_DATA_KEY_IMPL(CopyLink);
}
struct SharedQuoteState {
  bool valid = true;
  content::WeakDocumentPtr document;
  NSWindow* __weak window = nil;
  GURL url;
  std::u16string text;
  content::WebContents* Current() const {
    auto* frame = document.AsRenderFrameHostIfValid();
    auto* contents = frame ? content::WebContents::FromRenderFrameHost(frame) : nullptr;
    return valid && contents && contents->GetPrimaryMainFrame() == frame &&
        CanCopy(contents, PCNativeLinkCopyFormatQuote) &&
        ExistingNativePage(contents).nativeView.window == window &&
        contents->GetLastCommittedURL() == url &&
        frame->GetView()->GetSelectedText() == text ? contents : nullptr;
  }
};

class SharedQuoteObserver final : public content::WebContentsObserver {
 public:
  SharedQuoteObserver(content::WebContents* contents,
      void (^changed)(PCNativeSharedQuoteSelection*, BOOL))
      : content::WebContentsObserver(contents),
        window_(ExistingNativePage(contents).nativeView.window), changed_([changed copy]) {
    auto weak = weak_.GetWeakPtr();
    observers_ = [NSMutableArray array];
    for (NSNotificationName name in @[NSWindowWillCloseNotification,
          NSWindowDidResignKeyNotification, NSWindowDidMiniaturizeNotification,
          NSWindowWillBeginSheetNotification, PCNativeWindowSecurityStateChanged]) {
      [observers_ addObject:[NSNotificationCenter.defaultCenter addObserverForName:name
          object:window_ queue:nil usingBlock:^(NSNotification*) { if (weak) weak->Clear(); }]];
    }
    [observers_ addObject:[NSNotificationCenter.defaultCenter
        addObserverForName:NSApplicationDidResignActiveNotification object:NSApp queue:nil
        usingBlock:^(NSNotification*) { if (weak) weak->Clear(); }]];
  }
  ~SharedQuoteObserver() override {
    changed_ = nil;
    Clear();
    for (id observer in observers_) [NSNotificationCenter.defaultCenter removeObserver:observer];
  }
 private:
  void Clear(bool reset = true) {
    publication_.InvalidateWeakPtrs();
    if (state_) state_->valid = false;
    state_.reset();
    auto changed = changed_;
    if (changed) changed(nil, reset);
  }
  void SelectionChanged(std::u16string text) {
    auto alive = weak_.GetWeakPtr();
    Clear(false);
    if (!alive) return;
    auto weak = publication_.GetWeakPtr();
    dispatch_async(dispatch_get_main_queue(), ^{
      if (weak) weak->Publish(text);
    });
  }
  void Publish(const std::u16string& expected) {
    auto* contents = web_contents();
    if (!CanCopy(contents, PCNativeLinkCopyFormatQuote) ||
        ExistingNativePage(contents).nativeView.window != window_) return;
    auto* frame = contents->GetPrimaryMainFrame();
    auto text = frame->GetView()->GetSelectedText();
    if (text != expected) return;
    std::u16string trimmed;
    base::TrimWhitespace(text, base::TRIM_ALL, &trimmed);
    if (trimmed.empty()) return;
    state_ = std::make_shared<SharedQuoteState>();
    state_->document = frame->GetWeakDocumentPtr();
    state_->window = window_; state_->url = contents->GetLastCommittedURL();
    state_->text = std::move(text);
    auto changed = changed_;
    if (changed) changed([[PCNativeSharedQuoteSelection alloc] initWithState:state_], false);
  }
  void OnTextSelectionChanged(content::RenderFrameHost* frame, std::u16string_view text) override {
    if (frame == web_contents()->GetPrimaryMainFrame() && !text.empty()) SelectionChanged(std::u16string(text));
    else Clear();
  }
  void DidStartNavigation(content::NavigationHandle* navigation) override {
    if (navigation->IsInPrimaryMainFrame()) Clear();
  }
  void RenderFrameDeleted(content::RenderFrameHost* frame) override {
    if (frame == web_contents()->GetPrimaryMainFrame()) Clear();
  }
  void OnWebContentsLostFocus(content::RenderWidgetHost*) override { Clear(); }
  void PrimaryPageChanged(content::Page&) override { Clear(); }
  void WebContentsDestroyed() override { Clear(); }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility != content::Visibility::VISIBLE) Clear();
  }
  NSWindow* __weak window_;
  NSMutableArray* __strong observers_;
  void (^changed_)(PCNativeSharedQuoteSelection*, BOOL);
  std::shared_ptr<SharedQuoteState> state_;
  base::WeakPtrFactory<SharedQuoteObserver> weak_{this};
  base::WeakPtrFactory<SharedQuoteObserver> publication_{this};
};
}

@implementation PCNativeSharedQuoteSelection {
  std::shared_ptr<parc::SharedQuoteState> _state;
}
- (instancetype)initWithState:(std::shared_ptr<parc::SharedQuoteState>)state {
  if ((self = [super init])) _state = std::move(state);
  return self;
}
- (BOOL)canCopy { return _state && _state->Current(); }
- (void)copyWithCompletion:(void (^)(PCNativeLinkCopyResult))completion {
  auto* contents = _state ? _state->Current() : nullptr;
  if (!contents) { completion(PCNativeLinkCopyResultCancelled); return; }
  parc::CopyLink::CreateForWebContents(contents);
  parc::CopyLink::FromWebContents(contents)->Start(PCNativeLinkCopyFormatQuote, completion);
}
@end

@implementation PCNativeSharedQuoteObservation {
  std::unique_ptr<parc::SharedQuoteObserver> _observer;
}
- (instancetype)initWithContents:(content::WebContents*)contents
    changed:(void (^)(PCNativeSharedQuoteSelection*, BOOL))changed {
  if ((self = [super init])) _observer = std::make_unique<parc::SharedQuoteObserver>(contents, changed);
  return self;
}
- (void)invalidate { _observer.reset(); }
@end

@implementation PCNativePage (CopyLink)
- (BOOL)canCopyURLFromCommandWindow:(NSWindow*)window browser:(PCNativeBrowserWindow*)browser {
  CHECK(NSThread.isMainThread);
  auto* contents = parc::ContentsForNativePage(self);
  if (!contents || self.closed || !window || !browser) return NO;
  parc::CopyCommandWindow command(self, browser, window);
  return parc::CanCopy(contents, PCNativeLinkCopyFormatPlain, &command);
}
- (PCNativeSharedQuoteObservation*)observeSharedQuoteSelection:
    (void (^)(PCNativeSharedQuoteSelection*, BOOL))changed {
  auto* contents = parc::ContentsForNativePage(self);
  if (!contents || self.closed || self.isEmbedded || parc::IsNativePageRetiring(self) ||
      !self.nativeView.window || contents->IsBeingDestroyed()) return nil;
  return [[PCNativeSharedQuoteObservation alloc] initWithContents:contents changed:changed];
}

- (void)copyURLFromCommandWindow:(NSWindow*)window browser:(PCNativeBrowserWindow*)browser
                     completion:(void (^)(PCNativeLinkCopyResult))completion {
  auto* contents = parc::ContentsForNativePage(self);
  if (!completion) return;
  if (!contents || self.closed || !window || !browser) {
    completion(PCNativeLinkCopyResultUnavailable); return;
  }
  auto command = std::make_unique<parc::CopyCommandWindow>(self, browser, window);
  if (!command->Current(self)) { completion(PCNativeLinkCopyResultUnavailable); return; }
  parc::CopyLink::CreateForWebContents(contents);
  parc::CopyLink::FromWebContents(contents)->Start(PCNativeLinkCopyFormatPlain, completion, std::move(command));
}

- (BOOL)canCopyLinkWithFormat:(PCNativeLinkCopyFormat)format {
  return parc::CanCopy(parc::ContentsForNativePage(self), format);
}
- (void)copyLinkWithFormat:(PCNativeLinkCopyFormat)format completion:(void (^)(PCNativeLinkCopyResult))completion {
  auto* contents = parc::ContentsForNativePage(self);
  if (!contents || !completion || self.closed) {
    if (completion) completion(PCNativeLinkCopyResultUnavailable);
    return;
  }
  parc::CopyLink::CreateForWebContents(contents);
  parc::CopyLink::FromWebContents(contents)->Start(format, completion);
}
@end

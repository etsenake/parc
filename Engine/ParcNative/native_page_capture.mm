// Copyright 2026 Parc contributors.
#import "native_appkit_page.h"

#include <algorithm>
#include <cmath>
#include <memory>
#include <map>
#include <optional>
#include <utility>
#include <vector>

#include "parc/native/native_internal_urls.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/json/json_writer.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/scoped_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_split.h"
#include "base/strings/strcat.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "base/task/thread_pool.h"
#include "base/timer/timer.h"
#include "chrome/browser/enterprise/data_protection/data_protection_navigation_controller.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/common/pref_names.h"
#include "chrome/common/chrome_isolated_world_ids.h"
#include "components/enterprise/buildflags/buildflags.h"
#include "components/prefs/pref_change_registrar.h"
#include "components/prefs/pref_service.h"
#include "components/viz/common/frame_sinks/copy_output_result.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/host_zoom_map.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/render_widget_host.h"
#include "content/public/browser/render_widget_host_observer.h"
#include "content/public/browser/visibility.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "native_appkit_host.h"
#include "native_page_capture.h"
#include "native_page_retirement.h"
#include "native_profile_removal.h"
#include "tab_transfer.h"
#include "third_party/blink/public/common/page/page_zoom.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "third_party/skia/include/core/SkCanvas.h"
#include "third_party/skia/include/core/SkColor.h"
#include "third_party/skia/include/core/SkRect.h"
#include "ui/base/base_window.h"
#include "ui/gfx/codec/png_codec.h"
#include "ui/gfx/geometry/point_f.h"
#include "ui/gfx/geometry/rect_conversions.h"
#include "ui/gfx/geometry/rect_f.h"
#import "window_security_reservation.h"

namespace parc {
namespace {
constexpr NSUInteger kMaxScrollContainers = 8;
bool ScrollLocatorPartValid(std::string_view text, bool tag) {
  return !text.empty() && text.size() <= (tag ? 64u : 5u) &&
      std::all_of(text.begin(), text.end(), [tag](char c) {
        return tag ? base::IsAsciiAlphaNumeric(c) || c == '-' || c == '_' || c == '.'
                   : base::IsAsciiDigit(c);
      });
}
bool ScrollAnchorValid(NSString* anchor) {
  if (!anchor) return true;
  const std::string text = base::SysNSStringToUTF8(anchor);
  if (text.empty() || text.size() > 128 || !base::IsAsciiAlpha(text[0])) return false;
  int digits = 0;
  for (char c : text) {
    if (!base::IsAsciiAlphaNumeric(c) && c != '-' && c != '_') return false;
    digits = base::IsAsciiDigit(c) ? digits + 1 : 0;
    if (digits >= 3) return false;
  }
  return true;
}
bool ScrollPathValid(NSString* path) {
  if (!path) return false;
  const std::string text = base::SysNSStringToUTF8(path);
  if (text.empty()) return true;
  if (text.size() > 2048) return false;
  const auto steps = base::SplitStringPiece(text, ">", base::KEEP_WHITESPACE, base::SPLIT_WANT_ALL);
  if (steps.size() > 128) return false;
  for (std::string_view step : steps) {
    if (step == "^") continue;
    const size_t colon = step.find(':');
    if (colon == std::string_view::npos || !ScrollLocatorPartValid(step.substr(0, colon), true) ||
        !ScrollLocatorPartValid(step.substr(colon + 1), false)) return false;
  }
  return true;
}
bool BoundedFinite(double value) { return std::isfinite(value) && std::abs(value) <= 1000000; }
}
}

@implementation PCNativeCaptureScrollContainer
@synthesize anchorID = _anchorID, path = _path, scrollOffset = _scrollOffset, frame = _frame;
- (instancetype)initWithAnchorID:(NSString*)anchorID path:(NSString*)path
    scrollOffset:(NSPoint)scrollOffset frame:(NSRect)frame {
  if (!parc::ScrollAnchorValid(anchorID) || !parc::ScrollPathValid(path) ||
      !parc::BoundedFinite(scrollOffset.x) || !parc::BoundedFinite(scrollOffset.y) ||
      !parc::BoundedFinite(frame.origin.x) || !parc::BoundedFinite(frame.origin.y) ||
      !parc::BoundedFinite(frame.size.width) || !parc::BoundedFinite(frame.size.height) ||
      frame.size.width < 0 || frame.size.height < 0) return nil;
  if ((self = [super init])) {
    _anchorID = [anchorID copy];
    _path = [path copy];
    _scrollOffset = scrollOffset;
    _frame = frame;
  }
  return self;
}
@end
@interface PCNativeCaptureLayout ()
- (instancetype)initWithViewport:(NSSize)viewport scroll:(NSPoint)scroll region:(NSRect)region
                 scrollContainers:(NSArray<PCNativeCaptureScrollContainer*>*)scrollContainers;
@end
@implementation PCNativeCaptureLayout
@synthesize viewportSize = _viewportSize, scrollOffset = _scrollOffset, region = _region;
@synthesize scrollContainers = _scrollContainers;
- (instancetype)initWithViewport:(NSSize)viewport scroll:(NSPoint)scroll region:(NSRect)region
                 scrollContainers:(NSArray<PCNativeCaptureScrollContainer*>*)scrollContainers {
  if ((self = [super init])) {
    _viewportSize = viewport;
    _scrollOffset = scroll;
    _region = region;
    _scrollContainers = [scrollContainers copy] ?: @[];
  }
  return self;
}
@end
@interface PCNativePageCaptureResult ()
- (instancetype)initWithData:(NSData*)data size:(NSSize)size error:(NSString*)error
                     layout:(PCNativeCaptureLayout*)layout;
@end
@implementation PCNativePageCaptureResult
@synthesize pngData = _pngData, image = _image, pixelSize = _pixelSize;
@synthesize errorMessage = _errorMessage;
@synthesize layout = _layout;
- (instancetype)initWithData:(NSData*)data size:(NSSize)size error:(NSString*)error
                     layout:(PCNativeCaptureLayout*)layout {
  if ((self = [super init])) {
    _pngData = [data copy];
    _image = data ? [[NSImage alloc] initWithData:data] : nil;
    _pixelSize = size;
    _errorMessage = [error copy];
    _layout = layout;
  }
  return self;
}
@end

@interface PCNativePageCaptureTarget ()
@property(nonatomic, readonly) NSPoint queryPoint;
@property(nonatomic, readonly) double pageZoom;
- (instancetype)initWithRect:(NSRect)rect point:(NSPoint)point zoom:(double)zoom;
@end
@implementation PCNativePageCaptureTarget
@synthesize viewportRect = _viewportRect, queryPoint = _queryPoint, pageZoom = _pageZoom;
- (instancetype)initWithRect:(NSRect)rect point:(NSPoint)point zoom:(double)zoom {
  if ((self = [super init])) {
    _viewportRect = rect;
    _queryPoint = point;
    _pageZoom = zoom;
  }
  return self;
}
@end

namespace parc {
namespace {
using CaptureCompletion = void (^)(PCNativePageCaptureResult*);
using TargetCompletion = void (^)(PCNativePageCaptureTarget*);
void PostTarget(TargetCompletion completion, PCNativePageCaptureTarget* target) {
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce([](TargetCompletion callback, PCNativePageCaptureTarget* value) {
        callback(value);
      }, [completion copy], target));
}

std::u16string ElementQuery(NSPoint point, double zoom) {
  std::string script = "(() => { const px = " + base::NumberToString(point.x / zoom) +
      ", py = " + base::NumberToString(point.y / zoom) + R"JS(;
    const v = window.visualViewport;
    if (!v || !Number.isFinite(v.scale) || v.scale <= 0) return null;
    const x = px / v.scale + v.offsetLeft;
    const y = py / v.scale + v.offsetTop;
    for (const el of document.elementsFromPoint(x, y)) {
      const r = el.getBoundingClientRect();
      const style = getComputedStyle(el);
      let score = (r.width + r.height) / 1000;
      if (Math.min(r.width, r.height) < 100) score -= 5;
      if (r.width >= window.innerWidth) score -= 5;
      if (r.height >= window.innerHeight) score -= 5;
      if (r.width * r.height > window.innerWidth * window.innerHeight * 0.7) score -= 5;
      if (el.tagName === 'IMG' || el.tagName === 'PICTURE' || el.tagName === 'OBJECT') score += 5;
      if (style.display === 'inline') score -= 10;
      if (!(score >= 0)) continue;
      return {x:r.left, y:r.top, width:r.width, height:r.height,
              offsetX:v.offsetLeft, offsetY:v.offsetTop, scale:v.scale};
    }
    return null;
  })())JS";
  return base::UTF8ToUTF16(script);
}
constexpr std::string_view kLocateScript = R"JS(
    const stableID = id => /^[A-Za-z][A-Za-z0-9_-]{0,127}$/.test(id) && !/[0-9]{3}/.test(id);
    const locate = el => {
      const steps = [];
      for (let node = el; node;) {
        if (node === document.documentElement) return {anchor:null, path:steps.reverse().join('>')};
        if (node.id && stableID(node.id) && node.getRootNode() === document &&
            document.getElementById(node.id) === node) return {anchor:node.id, path:steps.reverse().join('>')};
        const parent = node.parentElement, root = node.parentNode;
        const holder = parent || (root instanceof ShadowRoot && root.mode === 'open' ? root : null);
        if (!holder || !/^[A-Za-z0-9._-]{1,64}$/.test(node.localName)) return null;
        steps.push(node.localName + ':' +
            Array.prototype.filter.call(holder.children, c => c.localName === node.localName).indexOf(node));
        if (parent) { node = parent; } else { steps.push('^'); node = root.host; }
      }
      return null;
    };
    const scrolls = value => value === 'auto' || value === 'scroll' || value === 'overlay';
    const up = el => el.parentElement || (el.parentNode instanceof ShadowRoot ? el.parentNode.host : null);
    const hitAt = (x, y) => {
      let hit = document.elementFromPoint(x, y);
      while (hit && hit.shadowRoot) {
        const inner = hit.shadowRoot.elementFromPoint(x, y);
        if (!inner || inner === hit) break;
        hit = inner;
      }
      return hit;
    };)JS";
constexpr std::string_view kFindScript = R"JS(
      const find = (anchor, path) => {
        let node = anchor === null ? document.documentElement : document.getElementById(anchor);
        for (const step of path ? path.split('>') : []) {
          if (!node) return null;
          if (step === '^') { node = node.shadowRoot; continue; }
          const [tag, index] = step.split(':');
          node = Array.prototype.filter.call(node.children, c => c.localName === tag)[Number(index)];
        }
        return node instanceof Element ? node : null;
      };)JS";
constexpr std::string_view kPinScript = R"JS(
    const holds = (outer, inner) => {
      for (let n = inner, depth = 0; n && depth < 512; n = up(n), depth++) if (n === outer) return true;
      return false;
    };
    const stack = (x, y) => {
      const found = [];
      const visit = (root, depth) => {
        for (const el of root.elementsFromPoint(x, y)) {
          if (found.includes(el)) continue;
          if (depth < 3 && el.shadowRoot && el.shadowRoot !== root) visit(el.shadowRoot, depth + 1);
          if (!found.includes(el)) found.push(el);
        }
      };
      visit(document, 0);
      return found;
    };
    const pinning = (target, element, clientTop, clientBottom) => {
      const styles = new Map();
      const styleOf = el => {
        let style = styles.get(el);
        if (!style) { style = getComputedStyle(el); styles.set(el, style); }
        return style;
      };
      const stuck = el => {
        const style = styleOf(el), r = el.getBoundingClientRect();
        const top = parseFloat(style.top), bottom = parseFloat(style.bottom);
        return (Number.isFinite(top) && Math.abs(r.top - clientTop - top) < 1) ||
            (Number.isFinite(bottom) && Math.abs(clientBottom - bottom - r.bottom) < 1);
      };
      const pin = el => {
        let found = null;
        for (let n = el, depth = 0; n && depth < 64; n = up(n), depth++) {
          if (holds(n, target)) break;
          const position = styleOf(n).position;
          if ((element && !holds(target, n)) || position === 'fixed' ||
              (position === 'sticky' && stuck(n))) found = n;
        }
        return found;
      };
      return {styleOf, pin};
    };)JS";
constexpr std::string_view kHoldScript = R"JS(
    const key = '__parcFullPageCapture';
    const hold = (state, el, prop, value) => {
      try {
        state.saved.push({el, prop, value:el.style.getPropertyValue(prop),
                          priority:el.style.getPropertyPriority(prop), attr:el.hasAttribute('style')});
        el.style.setProperty(prop, value, 'important');
      } catch (e) {}
    };
    const release = state => {
      for (const s of state.saved.reverse()) {
        try {
          if (s.value) s.el.style.setProperty(s.prop, s.value, s.priority);
          else s.el.style.removeProperty(s.prop);
          if (!s.attr && s.el.getAttribute('style') === '') s.el.removeAttribute('style');
        } catch (e) {}
      }
      state.saved = [];
    };)JS";
constexpr std::string_view kAreaScript = R"JS(
    const box = target.getBoundingClientRect();
    const clientTop = element ? box.top + target.clientTop : 0;
    const clientBottom = clientTop + target.clientHeight;
    const area = element ? {left:Math.max(0, box.left + target.clientLeft), top:Math.max(0, clientTop),
        right:Math.min(innerWidth, box.left + target.clientLeft + target.clientWidth),
        bottom:Math.min(innerHeight, clientBottom)}
      : {left:0, top:0, right:target.clientWidth, bottom:clientBottom};)JS";

std::u16string GeometryQuery(gfx::PointF centre) {
  return base::UTF8ToUTF16(base::StrCat({"(() => { const px = ", base::NumberToString(centre.x()),
      ", py = ", base::NumberToString(centre.y()), R"JS(;
    const v = visualViewport;
    if (!v) return null;
    const geometry = {width:innerWidth, height:innerHeight, x:v.pageLeft, y:v.pageTop, scale:v.scale};
    if (!Number.isFinite(v.scale) || v.scale <= 0) return geometry;
    const cx = px / v.scale + v.offsetLeft, cy = py / v.scale + v.offsetTop;)JS", kLocateScript, R"JS(
    const hit = hitAt(cx, cy);
    const scroller = document.scrollingElement || document.documentElement;
    const containers = [];
    for (let el = hit; el && el !== document.documentElement && el !== scroller;) {
      const style = getComputedStyle(el);
      if (el.scrollTop || el.scrollLeft ||
          (scrolls(style.overflowY) && el.scrollHeight > el.clientHeight + 1) ||
          (scrolls(style.overflowX) && el.scrollWidth > el.clientWidth + 1)) {
        const at = locate(el);
        if (at) {
          const r = el.getBoundingClientRect();
          containers.push({anchor:at.anchor, path:at.path, x:el.scrollLeft, y:el.scrollTop,
                           left:r.left + scrollX, top:r.top + scrollY, width:r.width, height:r.height});
          if (containers.length === 8) break;
        } else if (el.scrollTop || el.scrollLeft) {
          geometry.containers = null;
          return geometry;
        }
      }
      el = up(el);
    }
    geometry.containers = containers.reverse();
    return geometry;
  })())JS"}));
}

struct FullPageTarget {
  bool element = false;
  std::optional<std::string> anchor;
  std::string path;
};

struct FullPageFrame {
  double y = 0;
  double content = 0;
  double client = 0;
  double left = 0;
  double top = 0;
  double right = 0;
  double bottom = 0;
  double top_bar = 0;
  double bottom_bar = 0;
  bool hid = false;
  bool pending = false;
};

std::string JsonText(base::Value value) {
  return base::WriteJson(value).value_or("null");
}

std::string FullPageTargetScript(const FullPageTarget& target) {
  return base::StrCat({"const element = ", target.element ? "true" : "false", ", anchor = ",
      target.anchor ? JsonText(base::Value(*target.anchor)) : "null", ", path = ",
      JsonText(base::Value(target.path)), ";"});
}

std::u16string FullPageMeasureQuery() {
  return base::UTF8ToUTF16(base::StrCat({R"JS((() => {
    const v = visualViewport;
    if (!v) return null;
    const result = {kind:'none', scale:v.scale, width:innerWidth, height:innerHeight};
    if (!(Math.abs(v.scale - 1) < 0.001)) return result;)JS", kLocateScript, kPinScript, kHoldScript, R"JS(
    if (window[key]) { release(window[key]); delete window[key]; }
    const doc = document.scrollingElement || document.documentElement;
    const clipped = value => value === 'hidden' || value === 'clip';
    const rootStyle = getComputedStyle(document.documentElement);
    const bodyStyle = document.body ? getComputedStyle(document.body) : null;
    const rootScrolls = !clipped(rootStyle.overflowY) &&
        !(rootStyle.overflowY === 'visible' && bodyStyle && clipped(bodyStyle.overflowY));
    let target = rootScrolls && doc.scrollHeight > innerHeight + 1 ? doc : null;
    if (!target) {
      const cx = innerWidth / 2, cy = innerHeight / 2, seen = new Set();
      let best = null;
      for (let i = 0; i < 5; i++) for (let j = 0; j < 5; j++) {
        for (let el = hitAt(innerWidth * (i + 0.5) / 5, innerHeight * (j + 0.5) / 5);
             el && el !== document.documentElement && el !== doc && !seen.has(el); el = up(el)) {
          seen.add(el);
          const style = getComputedStyle(el);
          if (!scrolls(style.overflowY) || el.scrollHeight <= el.clientHeight + 1 ||
              style.visibility !== 'visible') continue;
          const r = el.getBoundingClientRect();
          const covers = Math.max(0, Math.min(r.right, innerWidth) - Math.max(r.left, 0)) *
              Math.max(0, Math.min(r.bottom, innerHeight) - Math.max(r.top, 0));
          if (covers < innerWidth * innerHeight / 3) continue;
          const centre = r.left <= cx && cx < r.right && r.top <= cy && cy < r.bottom;
          if (!best || centre > best.centre || (centre === best.centre && covers > best.covers))
            best = {el, centre, covers};
        }
      }
      if (!best) return result;
      target = best.el;
    }
    const element = target !== doc;
    const at = element ? locate(target) : {anchor:null, path:''};
    if (!at) { result.kind = 'unreachable'; return result; }
    const start = target.scrollTop;
    const state = {target, saved:[], hidden:new Set(), pins:new Map(), sides:[], fixed:[], left:0, right:0};
    const walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_ELEMENT);
    for (let n = walker.nextNode(), count = 0; n && count < 20000 && state.fixed.length < 300;
         n = walker.nextNode(), count++) {
      const position = getComputedStyle(n).position;
      if ((position === 'fixed' || position === 'sticky') && !holds(n, target)) state.fixed.push(n);
    }
    hold(state, element ? target : document.documentElement, 'scrollbar-width', 'none');
    hold(state, element ? target : document.documentElement, 'scroll-snap-type', 'none');
    window[key] = state;)JS", kAreaScript, R"JS(
    if (!element) {
      const {pin} = pinning(target, false, clientTop, clientBottom);
      const span = area.right - area.left, tall = area.bottom - area.top;
      let left = area.left, right = area.right;
      for (const fraction of [0.3, 0.5, 0.7]) {
        for (const x of [area.left + 0.5, area.right - 0.5]) {
          for (const el of stack(x, area.top + tall * fraction)) {
            const p = pin(el);
            if (!p) break;
            const r = p.getBoundingClientRect();
            if (r.height < tall / 2 || r.width >= span / 2) continue;
            if (r.left <= area.left + 1) left = Math.max(left, Math.min(r.right, area.right));
            else if (r.right >= area.right - 1) right = Math.min(right, Math.max(r.left, area.left));
            else continue;
            if (!state.sides.includes(p)) state.sides.push(p);
          }
        }
      }
      if (right - left >= span / 3) { area.left = left; area.right = right; } else state.sides = [];
    }
    state.left = area.left;
    state.right = area.right;
    return Object.assign(result, {kind:element ? 'element' : 'document', anchor:at.anchor, path:at.path,
        start, left:area.left, top:area.top, right:area.right, bottom:area.bottom,
        content:target.scrollHeight, client:target.clientHeight});
  })())JS"}));
}

std::u16string FullPageFrameQuery(const FullPageTarget& target, std::optional<double> offset,
                                  bool hide) {
  return base::UTF8ToUTF16(base::StrCat({"(() => { ", FullPageTargetScript(target),
      " const offset = ", offset ? base::NumberToString(*offset) : "null",
      ", hide = ", hide ? "true" : "false", ";", kLocateScript, kFindScript, kPinScript, kHoldScript, R"JS(
    const state = window[key];
    const doc = document.scrollingElement || document.documentElement;
    const target = element ? find(anchor, path) : doc;
    if (!state || !target || target !== state.target) return null;
    if (offset !== null) target.scrollTo({top:offset, behavior:'instant'});)JS", kAreaScript, R"JS(
    if (!element) { area.left = state.left; area.right = state.right; }
    const span = area.right - area.left, tall = area.bottom - area.top;
    if (!(span > 1 && tall > 1)) return null;
    const {styleOf, pin} = pinning(target, element, clientTop, clientBottom);
    const bars = new Set();
    const reach = (y, down) => {
      let edge = null;
      for (let i = 1; i < 8; i++) {
        for (const el of stack(area.left + span * i / 8, y)) {
          const p = pin(el);
          if (!p) break;
          if (state.hidden.has(p) || state.sides.includes(p) || styleOf(p).visibility !== 'visible') continue;
          const r = p.getBoundingClientRect();
          if (r.height >= tall / 3 || Math.min(r.right, area.right) - Math.max(r.left, area.left) < span / 3) continue;
          bars.add(p);
          edge = down ? Math.max(edge ?? y, r.bottom) : Math.min(edge ?? y, r.top);
        }
      }
      return edge;
    };
    let top = area.top, bottom = area.bottom;
    for (let i = 0; i < 3 && top < area.top + tall / 3; i++) {
      const edge = reach(top + 0.5, true);
      if (edge === null || edge <= top + 0.5) break;
      top = Math.min(edge, area.top + tall / 3);
    }
    for (let i = 0; i < 3 && bottom > area.bottom - tall / 3; i++) {
      const edge = reach(bottom - 0.5, false);
      if (edge === null || edge >= bottom - 0.5) break;
      bottom = Math.max(edge, area.bottom - tall / 3);
    }
    const now = target.scrollTop;
    const points = [];
    for (let i = 0; i < 10; i++) for (let j = 0; j < 10; j++)
      points.push([area.left + span * (i + 0.5) / 10, top + (bottom - top) * (j + 0.5) / 10]);
    const aim = el => {
      if (!el.isConnected) return;
      const r = el.getBoundingClientRect();
      const l = Math.max(r.left, area.left), t = Math.max(r.top, top);
      const rr = Math.min(r.right, area.right), b = Math.min(r.bottom, bottom);
      if (rr - l >= 1 && b - t >= 1) points.push([(l + rr) / 2, (t + b) / 2]);
    };
    state.fixed.forEach(aim);
    for (let n = target; element && n && n !== document.documentElement; n = up(n)) {
      const parent = up(n);
      if (parent) for (const sibling of parent.children) if (sibling !== n) aim(sibling);
    }
    let hid = 0;
    for (const [x, y] of bottom - top > 1 ? points.slice(0, 400) : []) {
      for (const el of stack(x, y)) {
        const p = pin(el);
        if (!p) break;
        if (bars.has(p) || state.hidden.has(p) || state.sides.includes(p)) continue;
        const r = p.getBoundingClientRect(), seen = state.pins.get(p);
        if (r.width * r.height >= span * tall * 0.6) continue;
        if (!seen) state.pins.set(p, {top:r.top, left:r.left, at:now});
        const sure = styleOf(p).position === 'sticky' || (element && !holds(target, p)) ||
            (seen !== undefined && Math.abs(now - seen.at) > 2 && Math.abs(r.top - seen.top) < 1 &&
             Math.abs(r.left - seen.left) < 1);
        if (hide && sure) { hold(state, p, 'visibility', 'hidden'); state.hidden.add(p); hid++; }
      }
    }
    let pending = 0;
    for (let i = 0; i < document.images.length && i < 4000 && !pending; i++) {
      const img = document.images[i];
      if (img.complete) continue;
      const r = img.getBoundingClientRect();
      if (r.width > 0 && r.height > 0 && r.bottom > area.top && r.top < area.bottom &&
          r.right > area.left && r.left < area.right) pending++;
    }
    return {y:now, content:target.scrollHeight, client:target.clientHeight, left:area.left, top:area.top,
            right:area.right, bottom:area.bottom, topBar:top - area.top, bottomBar:area.bottom - bottom,
            hid, pending};
  })())JS"}));
}

std::u16string FullPageRestoreQuery(const FullPageTarget& target, std::optional<double> start) {
  return base::UTF8ToUTF16(base::StrCat({"(() => { ", FullPageTargetScript(target),
      " const start = ", start ? base::NumberToString(*start) : "null", ";", kFindScript, kHoldScript, R"JS(
    const state = window[key];
    delete window[key];
    if (state) release(state);
    const doc = document.scrollingElement || document.documentElement;
    const target = state && state.target && state.target.isConnected ? state.target :
        element ? find(anchor, path) : doc;
    if (target && start !== null) target.scrollTo({top:start, behavior:'instant'});
    return true;
  })())JS"}));
}

std::optional<FullPageFrame> FullPageFrameFrom(const base::Value& value) {
  const auto* dict = value.GetIfDict();
  if (!dict) return std::nullopt;
  FullPageFrame frame;
  const std::pair<const char*, double*> fields[] = {
      {"y", &frame.y}, {"content", &frame.content}, {"client", &frame.client},
      {"left", &frame.left}, {"top", &frame.top}, {"right", &frame.right},
      {"bottom", &frame.bottom}, {"topBar", &frame.top_bar}, {"bottomBar", &frame.bottom_bar}};
  for (const auto& [name, field] : fields) {
    const auto number = dict->FindDouble(name);
    if (!number || !BoundedFinite(*number)) return std::nullopt;
    *field = *number;
  }
  const auto hid = dict->FindDouble("hid"), pending = dict->FindDouble("pending");
  if (!hid || !pending || frame.content < 0 || frame.client < 0 || frame.top_bar < 0 ||
      frame.bottom_bar < 0 || frame.right < frame.left || frame.bottom < frame.top) return std::nullopt;
  frame.hid = *hid > 0;
  frame.pending = *pending > 0;
  return frame;
}

bool SameFullPageFrame(const FullPageFrame& a, const FullPageFrame& b, bool content) {
  return std::abs(a.y - b.y) < 0.5 && (!content || std::abs(a.content - b.content) < 0.5) &&
      std::abs(a.top_bar - b.top_bar) < 0.5 && std::abs(a.bottom_bar - b.bottom_bar) < 0.5;
}

std::optional<NSArray<PCNativeCaptureScrollContainer*>*> ScrollContainersFrom(
    const base::DictValue& dict) {
  const base::ListValue* list = dict.FindList("containers");
  if (!list || list->size() > kMaxScrollContainers) return std::nullopt;
  NSMutableArray<PCNativeCaptureScrollContainer*>* containers = [NSMutableArray array];
  for (const base::Value& value : *list) {
    const auto* entry = value.GetIfDict();
    if (!entry) return std::nullopt;
    const base::Value* anchor = entry->Find("anchor");
    const std::string* path = entry->FindString("path");
    auto x = entry->FindDouble("x"), y = entry->FindDouble("y");
    auto left = entry->FindDouble("left"), top = entry->FindDouble("top");
    auto width = entry->FindDouble("width"), height = entry->FindDouble("height");
    if (!anchor || !(anchor->is_none() || anchor->is_string()) || !path ||
        !x || !y || !left || !top || !width || !height) return std::nullopt;
    auto container = [[PCNativeCaptureScrollContainer alloc]
        initWithAnchorID:anchor->is_string() ? base::SysUTF8ToNSString(anchor->GetString()) : nil
        path:base::SysUTF8ToNSString(*path) scrollOffset:NSMakePoint(*x, *y)
        frame:NSMakeRect(*left, *top, *width, *height)];
    if (!container) return std::nullopt;
    [containers addObject:container];
  }
  return containers;
}
struct EncodedCapture {
  std::vector<uint8_t> png;
  gfx::Size pixels;
};
EncodedCapture EncodeBitmap(SkBitmap bitmap) {
  if (bitmap.drawsNothing()) return {};
  auto png = gfx::PNGCodec::EncodeBGRASkBitmap(bitmap, false);
  return png ? EncodedCapture{std::move(*png), gfx::Size(bitmap.width(), bitmap.height())}
             : EncodedCapture{};
}
void PostFailure(CaptureCompletion completion, NSString* error) {
  auto result = [[PCNativePageCaptureResult alloc]
      initWithData:nil size:NSZeroSize error:error layout:nil];
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce([](CaptureCompletion callback, PCNativePageCaptureResult* value) {
        callback(value);
      }, [completion copy], result));
}

bool PageShownInWindow(PCNativeBrowserWindow* binding, PCNativePage* page) {
  return [[binding.client visibleNativePages] containsObject:page];
}

bool CaptureEligible(PCNativePage* page, content::WebContents* contents,
                     NSWindow* window, bool require_key) {
  if (!page || page.closed || !contents || contents->IsBeingDestroyed() ||
      !window || page.nativeView.window != window ||
      !PageCaptureWindowAdmits({.app_active = static_cast<bool>(NSApp.active),
                                .visible = static_cast<bool>(window.visible),
                                .miniaturized = static_cast<bool>(window.miniaturized),
                                .key = static_cast<bool>(window.keyWindow),
                                .attached_sheet = window.attachedSheet != nil,
                                .security_reservation =
                                    PCNativeWindowHasSecurityReservation(window)},
                               require_key) ||
      page.nativeView.hiddenOrHasHiddenAncestor || contents->IsCrashed() ||
      contents->GetVisibility() != content::Visibility::VISIBLE ||
      !contents->GetPrimaryMainFrame() ||
      !contents->GetPrimaryMainFrame()->IsRenderFrameLive() ||
      !contents->GetRenderWidgetHostView() || IsNativePageRetiring(page) ||
      IsLiveTabTransferTarget(contents)) return false;
  auto* profile = Profile::FromBrowserContext(contents->GetBrowserContext());
  if (!profile || profile->ShutdownStarted() ||
      IsNativeProfileRemovalBlocked(profile->GetPath()) ||
      profile->GetPrefs()->GetBoolean(prefs::kDisableScreenshots)) return false;
#if BUILDFLAG(ENTERPRISE_SCREENSHOT_PROTECTION)
  auto* controller = enterprise_data_protection::DataProtectionNavigationController::
      FromWebContents(contents);
  if (controller && !controller->screenshot_allowed()) return false;
#endif
  auto* browser = GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents);
  if (!browser || browser->IsDeleteScheduled() || !AppKitBrowserAcceptsNewPages(*browser) ||
      !browser->GetWindow() ||
      browser->GetWindow()->GetNativeWindow().GetNativeNSWindow() != window) return false;
  auto* binding = AppKitBindingForBrowser(browser);
  return binding && PageShownInWindow(binding, page);
}
class PageCapture;
auto& ActiveCaptures() {
  static base::NoDestructor<std::map<content::WebContents*, PageCapture*>> captures;
  return *captures;
}

class PageCapture final : public content::WebContentsObserver,
                          public ProfileObserver,
                          public content::RenderWidgetHostObserver,
                          public std::enable_shared_from_this<PageCapture> {
 public:
  PageCapture(PCNativePage* page, content::WebContents& contents, NSWindow* window,
              PageCapturePurpose purpose, void (^invalidated)())
      : content::WebContentsObserver(&contents), purpose_(purpose), page_(page), window_(window),
        document_(contents.GetPrimaryMainFrame()->GetWeakDocumentPtr()),
        profile_(Profile::FromBrowserContext(contents.GetBrowserContext())->GetWeakPtr()),
        invalidated_([invalidated copy]),
        runner_(base::SequencedTaskRunner::GetCurrentDefault()) {
    auto* browser = GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(&contents);
    if (browser) browser_ = browser->GetWeakPtr();
    host_size_ = page.nativeView.bounds.size;
    auto* view = contents.GetRenderWidgetHostView();
    if (view) {
      viewport_ = view->GetViewBounds().size();
      NSView* renderer = view->GetNativeView().GetNativeNSView();
      if (renderer) viewport_frame_ = [page.nativeView convertRect:renderer.bounds fromView:renderer];
    }
  }
  ~PageCapture() override { Invalidate(false); }

  bool Start() {
    if (!CanCapture() || viewport_.IsEmpty()) return false;
    profile_observer_.Observe(profile_.get());
    widget_observer_.Observe(web_contents()->GetPrimaryMainFrame()->GetRenderWidgetHost());
    pref_observer_.Init(profile_->GetPrefs());
    pref_observer_.Add(prefs::kDisableScreenshots,
        base::BindRepeating(&PageCapture::PolicyChanged, weak_factory_.GetWeakPtr()));
#if BUILDFLAG(ENTERPRISE_SCREENSHOT_PROTECTION)
    if (auto* controller = enterprise_data_protection::DataProtectionNavigationController::
            FromWebContents(web_contents())) {
      policy_subscription_ = controller->RegisterScreenshotAllowedUpdatedCallback(
          base::BindRepeating([](base::WeakPtr<PageCapture> weak, bool) {
            if (weak) weak->PolicyChanged();
          }, weak_factory_.GetWeakPtr()));
    }
#endif
    auto weak = weak_factory_.GetWeakPtr();
    for (NSNotificationName name in @[NSWindowWillCloseNotification,
        NSWindowDidMiniaturizeNotification, PCNativeWindowSecurityStateChanged]) {
      [observers_ addObject:[NSNotificationCenter.defaultCenter
          addObserverForName:name object:window_ queue:nil usingBlock:^(NSNotification* note) {
            if (weak && (![note.name isEqualToString:PCNativeWindowSecurityStateChanged] ||
                PCNativeWindowHasSecurityReservation(weak->window_)))
              weak->Invalidate(true);
          }]];
    }
    return true;
  }

  NSColor* ThemeColor() const {
    if (!Valid()) return nil;
    const auto color = web_contents()->GetThemeColor();
    if (!color) return nil;
    return [NSColor colorWithSRGBRed:SkColorGetR(*color) / 255.0
                             green:SkColorGetG(*color) / 255.0
                              blue:SkColorGetB(*color) / 255.0
                             alpha:SkColorGetA(*color) / 255.0];
  }

  bool Valid() const {
    auto* contents = web_contents();
    PCNativePage* page = page_;
    if (!valid_ || !contents || contents->IsBeingDestroyed() || !page || page.closed ||
        !window_ || page.nativeView.window != window_ || !profile_ ||
        profile_->ShutdownStarted() || IsNativeProfileRemovalBlocked(profile_->GetPath()) ||
        contents->GetBrowserContext() != profile_.get() || IsNativePageRetiring(page) ||
        IsLiveTabTransferTarget(contents) || !browser_ || browser_->IsDeleteScheduled() ||
        !AppKitBrowserAcceptsNewPages(*browser_) ||
        GlobalBrowserCollection::GetInstance()->FindBrowserWithTab(contents) != browser_.get() ||
        !browser_->GetWindow() ||
        browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() != window_ ||
        ContentsForNativePage(page) != contents ||
        document_.AsRenderFrameHostIfValid() != contents->GetPrimaryMainFrame()) return false;
    auto* binding = AppKitBindingForBrowser(browser_.get());
    return binding && PageShownInWindow(binding, page) &&
        GeometryMatches() && PolicyAllowsCapture();
  }
  bool Capturing() const { return completion_ || element_completion_; }
  NSSize ViewportSize() const { return NSMakeSize(viewport_.width(), viewport_.height()); }
  NSRect ViewportFrame() const { return viewport_frame_; }

  void Invalidate(bool notify) {
    auto keep_alive = weak_from_this().lock();
    if (!valid_) return;
    valid_ = false;
    if (element_completion_) {
      auto completion = element_completion_;
      element_completion_ = nil;
      PostFailure(completion, @"The source page is no longer available for this capture.");
    }
    ClearTarget();
    RestoreFullPage();
    full_page_.reset();
    ReleaseOperation();
    timer_.Stop();
    weak_factory_.InvalidateWeakPtrs();
    pref_observer_.RemoveAll();
    profile_observer_.Reset();
    widget_observer_.Reset();
    policy_subscription_ = {};
    for (id observer in observers_)
      [NSNotificationCenter.defaultCenter removeObserver:observer];
    [observers_ removeAllObjects];
    if (completion_) {
      auto completion = completion_;
      completion_ = nil;
      PostFailure(completion, @"The source page is no longer available for this capture.");
    }
    auto callback = invalidated_;
    invalidated_ = nil;
    if (notify && callback) {
      runner_->PostTask(FROM_HERE, base::BindOnce([](void (^block)()) { block(); }, callback));
    }
  }

  void TargetElement(NSPoint point, TargetCompletion completion) {
    if (!completion) return;
    if (Capturing() || PageCaptureViewportOnly(purpose_)) { PostTarget(completion, nil); return; }
    if (ActiveCaptures().contains(web_contents()) || !CanCapture() ||
        !std::isfinite(point.x) || !std::isfinite(point.y) ||
        point.x < 0 || point.y < 0 || point.x >= viewport_.width() ||
        point.y >= viewport_.height()) {
      ClearTarget();
      PostTarget(completion, nil);
      if (!Valid()) Invalidate(true);
      return;
    }
    QueueTarget(point, completion);
  }

  void CaptureElement(PCNativePageCaptureTarget* target, CaptureCompletion completion) {
    if (!completion) return;
    if (!target || target != offered_target_ || Capturing() || PageCaptureViewportOnly(purpose_) ||
        !CanCapture()) {
      PostFailure(completion, @"This element selection is no longer available.");
      return;
    }
    offered_target_ = nil;
    element_completion_ = [completion copy];
    auto weak = weak_factory_.GetWeakPtr();
    QueueTarget(target.queryPoint, ^(PCNativePageCaptureTarget* current) {
      if (weak) weak->ElementRevalidated(target, current);
    });
  }

  void Capture(NSRect region, bool full_page, CaptureCompletion completion) {
    auto keep_alive = weak_from_this().lock();
    if (!completion) return;
    if (Capturing() || ActiveCaptures().contains(web_contents())) {
      PostFailure(completion, @"A capture is already in progress.");
      return;
    }
    if (PageCaptureViewportOnly(purpose_) &&
        (full_page || !NSEqualRects(region, NSMakeRect(0, 0, viewport_.width(),
                                                       viewport_.height())))) {
      PostFailure(completion, @"This capture copies only the visible page.");
      return;
    }
    if (!CanCapture()) {
      PostFailure(completion, @"This page cannot be captured in its current state.");
      if (!Valid()) Invalidate(true);
      return;
    }
    ClearTarget();
    gfx::Rect area;
    if (!full_page) {
      if (!std::isfinite(region.origin.x) || !std::isfinite(region.origin.y) ||
          !std::isfinite(region.size.width) || !std::isfinite(region.size.height) ||
          region.origin.x < 0 || region.origin.y < 0 || region.size.width <= 0 ||
          region.size.height <= 0 || NSMaxX(region) > viewport_.width() ||
          NSMaxY(region) > viewport_.height()) {
        PostFailure(completion, @"The selected region is outside the original viewport.");
        return;
      }
      area = gfx::ToEnclosingRect(gfx::RectF(region.origin.x, region.origin.y,
                                            region.size.width, region.size.height));
    }
    ActiveCaptures()[web_contents()] = this;
    completion_ = [completion copy];
    const uint64_t request = ++request_;
    timer_.Start(FROM_HERE, base::Seconds(30), base::BindOnce(
        &PageCapture::Timeout, weak_factory_.GetWeakPtr(), request));
    if (full_page) {
      StartFullPage(request);
      return;
    }
    capture_area_ = area;
    capture_geometry_ = base::Value();
    capture_layout_ = nil;
    ReadGeometry(request, false, SkBitmap());
  }

 private:
  void ReadGeometry(uint64_t request, bool after_copy, SkBitmap bitmap) {
    if (!completion_ || request != request_ || !Valid()) return;
    const double zoom = blink::ZoomLevelToZoomFactor(content::HostZoomMap::GetZoomLevel(web_contents()));
    const gfx::PointF centre = std::isfinite(zoom) && zoom > 0 ?
        gfx::PointF(capture_area_.CenterPoint().x() / zoom, capture_area_.CenterPoint().y() / zoom) :
        gfx::PointF();
    document_.AsRenderFrameHostIfValid()->ExecuteJavaScriptInIsolatedWorld(
        GeometryQuery(centre), base::BindOnce(&PageCapture::GeometryRead, weak_factory_.GetWeakPtr(),
          request, after_copy, std::move(bitmap)), ISOLATED_WORLD_ID_CHROME_INTERNAL);
  }
  void GeometryRead(uint64_t request, bool after_copy, SkBitmap bitmap, base::Value value) {
    if (!completion_ || request != request_) return;
    if (!Valid()) { Invalidate(true); return; }
    const double zoom = blink::ZoomLevelToZoomFactor(content::HostZoomMap::GetZoomLevel(web_contents()));
    if (after_copy) {
      if (value == capture_geometry_ && zoom == capture_zoom_) {
        const auto* dict = value.GetIfDict();
        auto w = dict ? dict->FindDouble("width") : std::nullopt;
        auto h = dict ? dict->FindDouble("height") : std::nullopt;
        auto x = dict ? dict->FindDouble("x") : std::nullopt;
        auto y = dict ? dict->FindDouble("y") : std::nullopt;
        auto scale = dict ? dict->FindDouble("scale") : std::nullopt;
        if (w && h && x && y && scale && std::isfinite(*w) && std::isfinite(*h) &&
            std::isfinite(*x) && std::isfinite(*y) && std::isfinite(*scale) &&
            *w > 0 && *h > 0 && *w <= 16384 && *h <= 16384 &&
            std::abs(*x) <= 1000000 && std::abs(*y) <= 1000000 && *scale > 0 &&
            std::isfinite(zoom) && zoom > 0) {
          const double factor = zoom * *scale;
          auto containers = ScrollContainersFrom(*dict);
          if (containers) {
            capture_layout_ = [[PCNativeCaptureLayout alloc]
                initWithViewport:NSMakeSize(*w, *h) scroll:NSMakePoint(*x, *y)
                region:NSMakeRect(capture_area_.x() / factor, capture_area_.y() / factor,
                    capture_area_.width() / factor, capture_area_.height() / factor)
                scrollContainers:*containers];
          }
        }
      }
      EncodeSurface(request, std::move(bitmap));
      return;
    }
    capture_geometry_ = std::move(value);
    capture_zoom_ = zoom;
    auto weak = weak_factory_.GetWeakPtr();
    web_contents()->GetRenderWidgetHostView()->CopyFromSurface(
        capture_area_, gfx::Size(), base::Seconds(10),
        base::BindOnce([](scoped_refptr<base::SequencedTaskRunner> runner,
                         base::WeakPtr<PageCapture> weak, uint64_t request,
                         const content::CopyFromSurfaceResult& result) {
          runner->PostTask(FROM_HERE, base::BindOnce(&PageCapture::SurfaceCopied,
              weak, request, result.has_value() ? result->bitmap : SkBitmap()));
        }, runner_, weak, request));
  }

  void ClearTarget() {
    ++target_generation_;
    ++target_query_;
    target_inflight_ = false;
    target_timer_.Stop();
    offered_target_ = nil;
    if (target_completion_) {
      auto callback = target_completion_;
      target_completion_ = nil;
      PostTarget(callback, nil);
    }
  }
  void QueueTarget(NSPoint point, TargetCompletion completion) {
    ++target_generation_;
    offered_target_ = nil;
    if (target_completion_) PostTarget(target_completion_, nil);
    target_completion_ = [completion copy];
    target_point_ = point;
    if (!target_inflight_) StartTarget();
  }
  void StartTarget() {
    if (!target_completion_) return;
    if (!CanCapture() || completion_ || ActiveCaptures().contains(web_contents())) {
      ClearTarget();
      return;
    }
    const double zoom = blink::ZoomLevelToZoomFactor(
        content::HostZoomMap::GetZoomLevel(web_contents()));
    if (!std::isfinite(zoom) || zoom <= 0) { ClearTarget(); return; }
    const uint64_t generation = target_generation_;
    const uint64_t query = ++target_query_;
    NSPoint point = target_point_;
    target_inflight_ = true;
    target_timer_.Start(FROM_HERE, base::Seconds(2), base::BindOnce(
        &PageCapture::TargetResult, weak_factory_.GetWeakPtr(), query, generation,
        point, zoom, base::Value()));
    document_.AsRenderFrameHostIfValid()->ExecuteJavaScriptInIsolatedWorld(
        ElementQuery(point, zoom), base::BindOnce(
            [](scoped_refptr<base::SequencedTaskRunner> runner,
               base::WeakPtr<PageCapture> weak, uint64_t query, uint64_t generation,
               NSPoint point, double zoom, base::Value value) {
              runner->PostTask(FROM_HERE, base::BindOnce(&PageCapture::TargetResult,
                  weak, query, generation, point, zoom, std::move(value)));
            }, runner_, weak_factory_.GetWeakPtr(), query, generation, point, zoom),
        ISOLATED_WORLD_ID_CHROME_INTERNAL);
  }
  void TargetResult(uint64_t query, uint64_t generation, NSPoint point,
                    double zoom, base::Value value) {
    auto keep_alive = weak_from_this().lock();
    if (!target_inflight_ || query != target_query_) return;
    target_inflight_ = false;
    target_timer_.Stop();
    if (generation != target_generation_) { StartTarget(); return; }
    auto completion = target_completion_;
    target_completion_ = nil;
    if (!completion) return;
    PCNativePageCaptureTarget* target = nil;
    if (CanCapture() && !completion_ &&
        zoom == blink::ZoomLevelToZoomFactor(content::HostZoomMap::GetZoomLevel(web_contents()))) {
      const auto* dict = value.GetIfDict();
      auto x = dict ? dict->FindDouble("x") : std::nullopt;
      auto y = dict ? dict->FindDouble("y") : std::nullopt;
      auto w = dict ? dict->FindDouble("width") : std::nullopt;
      auto h = dict ? dict->FindDouble("height") : std::nullopt;
      auto ox = dict ? dict->FindDouble("offsetX") : std::nullopt;
      auto oy = dict ? dict->FindDouble("offsetY") : std::nullopt;
      auto scale = dict ? dict->FindDouble("scale") : std::nullopt;
      if (x && y && w && h && ox && oy && scale &&
          std::isfinite(*x) && std::isfinite(*y) && std::isfinite(*w) &&
          std::isfinite(*h) && std::isfinite(*ox) && std::isfinite(*oy) &&
          std::isfinite(*scale) && *w > 0 && *h > 0 && *scale > 0) {
        const double factor = *scale * zoom;
        NSRect rect = NSMakeRect((*x - *ox) * factor, (*y - *oy) * factor,
                                 *w * factor, *h * factor);
        if (std::isfinite(rect.origin.x) && std::isfinite(rect.origin.y) &&
            std::isfinite(rect.size.width) && std::isfinite(rect.size.height)) {
          rect = NSIntersectionRect(rect, NSMakeRect(0, 0, viewport_.width(), viewport_.height()));
          if (!NSIsEmptyRect(rect)) target = [[PCNativePageCaptureTarget alloc]
              initWithRect:rect point:point zoom:zoom];
        }
      }
    }
    offered_target_ = target;
    runner_->PostTask(FROM_HERE, base::BindOnce(
        [](base::WeakPtr<PageCapture> weak, uint64_t generation,
           TargetCompletion callback, PCNativePageCaptureTarget* target) {
          callback(weak && weak->target_generation_ == generation && weak->CanCapture()
                       ? target : nil);
        }, weak_factory_.GetWeakPtr(), generation, completion, target));
  }
  void ElementRevalidated(PCNativePageCaptureTarget* expected,
                          PCNativePageCaptureTarget* current) {
    auto keep_alive = weak_from_this().lock();
    if (!element_completion_) return;
    auto completion = element_completion_;
    element_completion_ = nil;
    offered_target_ = nil;
    if (!current || !NSEqualRects(expected.viewportRect, current.viewportRect) ||
        expected.pageZoom != current.pageZoom) {
      PostFailure(completion, @"The element moved. Select it again before capturing.");
      return;
    }
    NSRect area = NSIntersectionRect(NSInsetRect(current.viewportRect, -2, -2),
        NSMakeRect(0, 0, viewport_.width(), viewport_.height()));
    Capture(area, false, completion);
  }
  bool GeometryMatches() const {
    if (!page_ || !NSEqualSizes(page_.nativeView.bounds.size, host_size_)) return false;
    auto* view = web_contents() ? web_contents()->GetRenderWidgetHostView() : nullptr;
    NSView* renderer = view ? view->GetNativeView().GetNativeNSView() : nil;
    return renderer && view->GetViewBounds().size() == viewport_ &&
        NSEqualRects([page_.nativeView convertRect:renderer.bounds fromView:renderer],
                     viewport_frame_);
  }
  void CheckGeometry() { if (!GeometryMatches()) Invalidate(true); }
  bool PolicyAllowsCapture() const {
    if (!profile_ || !web_contents() ||
        profile_->GetPrefs()->GetBoolean(prefs::kDisableScreenshots)) return false;
#if BUILDFLAG(ENTERPRISE_SCREENSHOT_PROTECTION)
    auto* controller = enterprise_data_protection::DataProtectionNavigationController::
        FromWebContents(web_contents());
    if (controller && !controller->screenshot_allowed()) return false;
#endif
    return true;
  }
  bool CanCapture() const {
    return Valid() &&
        CaptureEligible(page_, web_contents(), window_, PageCaptureNeedsKeyWindow(purpose_)) &&
        web_contents()->GetRenderWidgetHostView()->GetViewBounds().size() == viewport_;
  }
  void ReleaseOperation() {
    auto it = ActiveCaptures().find(web_contents());
    if (it != ActiveCaptures().end() && it->second == this) ActiveCaptures().erase(it);
  }
  void PolicyChanged() { if (!PolicyAllowsCapture()) Invalidate(true); }
  void SurfaceCopied(uint64_t request, SkBitmap bitmap) {
    if (!completion_ || request != request_) return;
    if (!Valid()) { Invalidate(true); return; }
    ReadGeometry(request, true, std::move(bitmap));
  }
  void EncodeSurface(uint64_t request, SkBitmap bitmap) {
    base::ThreadPool::PostTaskAndReplyWithResult(FROM_HERE,
        {base::TaskPriority::USER_VISIBLE}, base::BindOnce(&EncodeBitmap, std::move(bitmap)),
        base::BindOnce(&PageCapture::Deliver, weak_factory_.GetWeakPtr(), request));
  }
  enum class FramePhase { kScrolled, kSettled, kChecked };
  struct FullPage {
    FullPageTarget target;
    bool scrolls = false;
    bool applied = false;
    bool first = true;
    bool may_retry = true;
    std::optional<double> start;
    double zoom = 1;
    float device_scale = 1;
    double left = 0;
    double top = 0;
    double right = 0;
    double bottom = 0;
    double content = 0;
    double client = 0;
    double css_width = 0;
    int covered = 0;
    int frames = 0;
    int settles = 0;
    int checks = 0;
    std::optional<FullPageFrame> read;
    base::TimeTicks started;
    base::TimeTicks frame_started;
    PageCaptureGeometry geometry;
    SkBitmap canvas;
  };
  void StartFullPage(uint64_t request) {
    capture_layout_ = nil;
    auto* view = web_contents()->GetRenderWidgetHostView();
    const double zoom = blink::ZoomLevelToZoomFactor(content::HostZoomMap::GetZoomLevel(web_contents()));
    const float device_scale = view ? view->GetDeviceScaleFactor() : 0;
    if (!std::isfinite(zoom) || zoom <= 0 || !std::isfinite(device_scale) || device_scale <= 0) {
      Fail(request, @"The renderer could not capture the full page.");
      return;
    }
    full_page_ = std::make_unique<FullPage>();
    full_page_->zoom = zoom;
    full_page_->device_scale = device_scale;
    full_page_->started = base::TimeTicks::Now();
    document_.AsRenderFrameHostIfValid()->ExecuteJavaScriptInIsolatedWorld(FullPageMeasureQuery(),
        base::BindOnce(&PageCapture::FullPageMeasured, weak_factory_.GetWeakPtr(), request),
        ISOLATED_WORLD_ID_CHROME_INTERNAL);
  }
  bool FullPageCurrent(uint64_t request) {
    if (!completion_ || request != request_ || !full_page_) return false;
    if (!Valid()) { Invalidate(true); return false; }
    return true;
  }
  void FullPageMeasured(uint64_t request, base::Value value) {
    if (!FullPageCurrent(request)) return;
    FullPage& page = *full_page_;
    const auto* dict = value.GetIfDict();
    const auto scale = dict ? dict->FindDouble("scale") : std::nullopt;
    const std::string* kind = dict ? dict->FindString("kind") : nullptr;
    if (kind && (*kind == "document" || *kind == "element")) page.applied = true;
    if (!scale || !kind || !std::isfinite(*scale)) {
      Fail(request, @"The page changed while it was being captured. Try again.");
      return;
    }
    if (std::abs(*scale - 1) >= 0.001) {
      Fail(request, @"Pinch back out to capture the full page.");
      return;
    }
    if (!page.applied) { CopyFullPageFrame(request); return; }
    const base::Value* anchor = dict->Find("anchor");
    const std::string* path = dict->FindString("path");
    const auto start = dict->FindDouble("start"), left = dict->FindDouble("left");
    const auto top = dict->FindDouble("top"), right = dict->FindDouble("right");
    const auto bottom = dict->FindDouble("bottom"), content = dict->FindDouble("content");
    const auto client = dict->FindDouble("client"), width = dict->FindDouble("width");
    if (!anchor || !(anchor->is_none() || anchor->is_string()) || !path || !start || !left || !top ||
        !right || !bottom || !content || !client || !width ||
        !ScrollAnchorValid(anchor->is_string() ? base::SysUTF8ToNSString(anchor->GetString()) : nil) ||
        !ScrollPathValid(base::SysUTF8ToNSString(*path)) || !BoundedFinite(*start) ||
        !BoundedFinite(*left) || !BoundedFinite(*top) || !BoundedFinite(*right) ||
        !BoundedFinite(*bottom) || !BoundedFinite(*content) || !BoundedFinite(*client) ||
        !BoundedFinite(*width) || *right <= *left || *bottom <= *top || *content < 0 ||
        *client <= 0 || *width <= 0) {
      Fail(request, @"The page changed while it was being captured. Try again.");
      return;
    }
    page.target.element = *kind == "element";
    if (anchor->is_string()) page.target.anchor = anchor->GetString();
    page.target.path = *path;
    page.start = *start;
    page.left = *left;
    page.top = *top;
    page.right = *right;
    page.bottom = *bottom;
    page.content = *content;
    page.client = *client;
    page.css_width = *width;
    page.scrolls = true;
    RequestFullPageFrame(request, 0);
  }
  void RequestFullPageFrame(uint64_t request, double offset) {
    FullPage& page = *full_page_;
    if (++page.frames > kPageCaptureMaxFrames) {
      FinishFullPage(request, PageCaptureFills(PageCaptureBandsFor(page.geometry), page.covered));
      return;
    }
    page.settles = 0;
    page.checks = 0;
    page.read.reset();
    page.frame_started = base::TimeTicks::Now();
    RunFrameQuery(request, offset, FramePhase::kScrolled, SkBitmap());
  }
  void RunFrameQuery(uint64_t request, std::optional<double> offset, FramePhase phase,
                     SkBitmap bitmap) {
    const bool hide = !full_page_->first && phase != FramePhase::kChecked;
    document_.AsRenderFrameHostIfValid()->ExecuteJavaScriptInIsolatedWorld(
        FullPageFrameQuery(full_page_->target, offset, hide),
        base::BindOnce(&PageCapture::FullPageFrameRead, weak_factory_.GetWeakPtr(), request, phase,
                       std::move(bitmap)),
        ISOLATED_WORLD_ID_CHROME_INTERNAL);
  }
  void FullPageFrameRead(uint64_t request, FramePhase phase, SkBitmap bitmap, base::Value value) {
    if (!FullPageCurrent(request)) return;
    FullPage& page = *full_page_;
    const auto frame = FullPageFrameFrom(value);
    if (!frame || (page.target.element &&
        (std::abs(frame->left - page.left) > 1 || std::abs(frame->top - page.top) > 1 ||
         std::abs(frame->right - page.right) > 1 || std::abs(frame->bottom - page.bottom) > 1))) {
      Fail(request, @"The page changed while it was being captured. Try again.");
      return;
    }
    switch (phase) {
      case FramePhase::kScrolled:
        page.read = frame;
        AwaitFullPageFrames(request, 2);
        return;
      case FramePhase::kSettled: {
        const bool moving = !page.read || !SameFullPageFrame(*page.read, *frame, true) ||
            frame->hid || frame->pending;
        page.read = frame;
        if (moving && page.settles < 40 &&
            base::TimeTicks::Now() - page.frame_started < base::Milliseconds(600)) {
          ++page.settles;
          AwaitFullPageFrames(request, 1);
          return;
        }
        CopyFullPageFrame(request);
        return;
      }
      case FramePhase::kChecked:
        if (page.read && SameFullPageFrame(*page.read, *frame, false)) {
          AcceptFullPageFrame(request, std::move(bitmap));
          return;
        }
        if (++page.checks > 2) {
          Fail(request, @"The page kept moving while it was being captured. Try again.");
          return;
        }
        page.read = frame;
        AwaitFullPageFrames(request, 1);
        return;
    }
  }
  void AwaitFullPageFrames(uint64_t request, int count) {
    document_.AsRenderFrameHostIfValid()->InsertVisualStateCallback(base::BindOnce(
        &PageCapture::FullPageFrameShown, weak_factory_.GetWeakPtr(), request, count - 1));
  }
  void FullPageFrameShown(uint64_t request, int remaining, bool shown) {
    if (!FullPageCurrent(request)) return;
    if (!shown) { Invalidate(true); return; }
    if (remaining > 0) { AwaitFullPageFrames(request, remaining); return; }
    RunFrameQuery(request, std::nullopt, FramePhase::kSettled, SkBitmap());
  }
  void CopyFullPageFrame(uint64_t request) {
    web_contents()->GetRenderWidgetHostView()->CopyFromSurface(
        gfx::Rect(viewport_), gfx::Size(), base::Seconds(10),
        base::BindOnce([](scoped_refptr<base::SequencedTaskRunner> runner,
                         base::WeakPtr<PageCapture> weak, uint64_t request,
                         const content::CopyFromSurfaceResult& result) {
          runner->PostTask(FROM_HERE, base::BindOnce(&PageCapture::FullPageFrameCopied,
              weak, request, result.has_value() ? result->bitmap : SkBitmap()));
        }, runner_, weak_factory_.GetWeakPtr(), request));
  }
  void FullPageFrameCopied(uint64_t request, SkBitmap bitmap) {
    if (!FullPageCurrent(request)) return;
    FullPage& page = *full_page_;
    auto* view = web_contents()->GetRenderWidgetHostView();
    const double zoom = blink::ZoomLevelToZoomFactor(content::HostZoomMap::GetZoomLevel(web_contents()));
    if (bitmap.drawsNothing() || bitmap.colorType() != kN32_SkColorType || zoom != page.zoom ||
        !view || view->GetDeviceScaleFactor() != page.device_scale ||
        (!page.canvas.drawsNothing() && (bitmap.width() != page.geometry.frame_width ||
                                         bitmap.height() != page.geometry.frame_height))) {
      Fail(request, @"The renderer could not capture the full page.");
      return;
    }
    if (!page.scrolls) { AcceptFullPageFrame(request, std::move(bitmap)); return; }
    RunFrameQuery(request, std::nullopt, FramePhase::kChecked, std::move(bitmap));
  }
  NSString* StartFullPageCanvas(const SkBitmap& frame) {
    FullPage& page = *full_page_;
    PageCaptureGeometry& geometry = page.geometry;
    geometry.frame_width = frame.width();
    geometry.frame_height = frame.height();
    geometry.scale = page.zoom * page.device_scale;
    if (page.scrolls) {
      if (std::abs(page.css_width * geometry.scale - frame.width()) > 2 * geometry.scale + 2)
        return @"The renderer could not capture the full page.";
      geometry.area_left = page.left;
      geometry.area_top = page.top;
      geometry.area_right = page.right;
      geometry.area_bottom = page.bottom;
      geometry.content_height = page.content;
      geometry.client_height = page.client;
    }
    const PageCaptureBands bands = PageCaptureBandsFor(geometry);
    if (bands.output_height <= 0 ||
        !page.canvas.tryAllocPixels(frame.info().makeWH(bands.width, bands.output_height))) {
      page.canvas.reset();
      return @"This page is too big to capture in one piece.";
    }
    page.canvas.eraseColor(SK_ColorTRANSPARENT);
    return nil;
  }
  void AcceptFullPageFrame(uint64_t request, SkBitmap bitmap) {
    FullPage& page = *full_page_;
    if (page.canvas.drawsNothing()) {
      if (NSString* error = StartFullPageCanvas(bitmap)) {
        Fail(request, error);
        return;
      }
    }
    if (page.read) {
      page.geometry.top_bar = page.read->top_bar;
      page.geometry.bottom_bar = page.read->bottom_bar;
      page.geometry.content_height = std::min(page.content, page.read->content);
    }
    const PageCaptureStep step = PageCaptureTakeFrame(page.geometry, page.covered,
        page.read ? page.read->y : 0, page.first, page.may_retry);
    if (step.retry_offset) {
      page.may_retry = false;
      RequestFullPageFrame(request, *step.retry_offset);
      return;
    }
    SkCanvas canvas(page.canvas);
    for (const PageCaptureSlice& slice : step.slices) {
      SkBitmap rows;
      if (bitmap.extractSubset(&rows, SkIRect::MakeXYWH(slice.left, slice.source_y, slice.width,
                                                        slice.height)))
        canvas.writePixels(rows, slice.left, slice.dest_y);
    }
    page.covered = step.covered;
    page.first = false;
    page.may_retry = true;
    if (step.next_offset && base::TimeTicks::Now() - page.started < base::Seconds(18)) {
      RequestFullPageFrame(request, *step.next_offset);
      return;
    }
    FinishFullPage(request, step.next_offset ?
        PageCaptureFills(PageCaptureBandsFor(page.geometry), page.covered) : step.fills);
  }
  void FillFullPageGaps(const std::vector<PageCaptureSlice>& fills) {
    SkBitmap& canvas = full_page_->canvas;
    const int probe = std::max(8, PageCapturePixels(8, full_page_->geometry.scale));
    for (const PageCaptureSlice& fill : fills) {
      if (fill.width <= 0 || fill.height <= 0 || fill.left < 0 || fill.source_y < probe ||
          fill.left + fill.width > canvas.width() || fill.source_y >= canvas.height() ||
          fill.dest_y < 0 || fill.dest_y + fill.height > canvas.height()) continue;
      const uint32_t* source = canvas.getAddr32(fill.left, fill.source_y);
      bool uniform = true;
      for (int y = fill.source_y - probe; uniform && y < fill.source_y; ++y) {
        const uint32_t* row = canvas.getAddr32(fill.left, y);
        uniform = std::equal(row, row + fill.width, source);
      }
      if (!uniform) continue;
      for (int y = fill.dest_y; y < fill.dest_y + fill.height; ++y)
        std::copy_n(source, fill.width, canvas.getAddr32(fill.left, y));
    }
  }
  void FinishFullPage(uint64_t request, const std::vector<PageCaptureSlice>& fills) {
    RestoreFullPage();
    FullPage& page = *full_page_;
    SkBitmap output;
    if (page.canvas.drawsNothing() || page.covered <= 0 ||
        !page.canvas.extractSubset(&output, SkIRect::MakeWH(page.canvas.width(),
            std::min(page.covered, page.canvas.height())))) {
      Fail(request, @"The renderer could not capture the full page.");
      return;
    }
    FillFullPageGaps(fills);
    full_page_.reset();
    EncodeSurface(request, std::move(output));
  }
  void RestoreFullPage() {
    if (!full_page_ || !full_page_->applied) return;
    full_page_->applied = false;
    auto* frame = document_.AsRenderFrameHostIfValid();
    auto* contents = web_contents();
    if (!frame || !contents || contents->IsBeingDestroyed() || !frame->IsRenderFrameLive() ||
        frame != contents->GetPrimaryMainFrame()) return;
    frame->ExecuteJavaScriptInIsolatedWorld(
        FullPageRestoreQuery(full_page_->target, full_page_->start), base::NullCallback(),
        ISOLATED_WORLD_ID_CHROME_INTERNAL);
  }
  void Deliver(uint64_t request, EncodedCapture encoded) {
    if (!completion_ || request != request_) return;
    if (!Valid()) { Invalidate(true); return; }
    timer_.Stop();
    ReleaseOperation();
    auto completion = completion_;
    completion_ = nil;
    NSData* data = encoded.png.empty() ? nil :
        [NSData dataWithBytes:encoded.png.data() length:encoded.png.size()];
    auto result = [[PCNativePageCaptureResult alloc] initWithData:data
        size:NSMakeSize(encoded.pixels.width(), encoded.pixels.height())
        error:data ? nil : @"The renderer returned no usable capture pixels."
        layout:data ? capture_layout_ : nil];
    completion(result);
  }
  void Fail(uint64_t request, NSString* error) {
    auto keep_alive = weak_from_this().lock();
    if (!completion_ || request != request_) return;
    RestoreFullPage();
    full_page_.reset();
    timer_.Stop();
    ReleaseOperation();
    auto completion = completion_;
    completion_ = nil;
    PostFailure(completion, error);
  }
  void Timeout(uint64_t request) {
    Fail(request, @"The page capture did not finish in time.");
  }
  void DidStartNavigation(content::NavigationHandle* handle) override {
    if (handle->IsInPrimaryMainFrame() && !handle->IsSameDocument()) Invalidate(true);
  }
  void PrimaryPageChanged(content::Page&) override { Invalidate(true); }
  void WebContentsDestroyed() override { Invalidate(true); }
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus) override { Invalidate(true); }
  void OnVisibilityChanged(content::Visibility visibility) override {
    if (visibility == content::Visibility::HIDDEN) Invalidate(true);
  }
  void OnProfileWillBeDestroyed(Profile*) override { Invalidate(true); }
  void PrimaryMainFrameWasResized(bool) override { CheckGeometry(); }
  void RenderWidgetHostDidUpdateVisualProperties(content::RenderWidgetHost*) override {
    CheckGeometry();
  }
  void RenderWidgetHostDestroyed(content::RenderWidgetHost*) override {
    Invalidate(true);
  }

  const PageCapturePurpose purpose_;
  PCNativePage* __weak page_;
  NSWindow* __weak window_;
  content::WeakDocumentPtr document_;
  base::WeakPtr<Profile> profile_;
  base::WeakPtr<BrowserWindowInterface> browser_;
  gfx::Size viewport_;
  gfx::Rect capture_area_;
  base::Value capture_geometry_;
  double capture_zoom_ = 1;
  PCNativeCaptureLayout* __strong capture_layout_ = nil;
  NSRect viewport_frame_ = NSZeroRect;
  NSSize host_size_ = NSZeroSize;
  bool valid_ = true;
  uint64_t request_ = 0;
  CaptureCompletion completion_ = nil;
  CaptureCompletion element_completion_ = nil;
  TargetCompletion target_completion_ = nil;
  PCNativePageCaptureTarget* __strong offered_target_ = nil;
  NSPoint target_point_ = NSZeroPoint;
  uint64_t target_generation_ = 0;
  uint64_t target_query_ = 0;
  bool target_inflight_ = false;
  void (^invalidated_)() = nil;
  NSMutableArray* __strong observers_ = [[NSMutableArray alloc] init];
  scoped_refptr<base::SequencedTaskRunner> runner_;
  std::unique_ptr<FullPage> full_page_;
  base::OneShotTimer timer_;
  base::OneShotTimer target_timer_;
  PrefChangeRegistrar pref_observer_;
  base::ScopedObservation<Profile, ProfileObserver> profile_observer_{this};
  base::CallbackListSubscription policy_subscription_;
  base::ScopedObservation<content::RenderWidgetHost, content::RenderWidgetHostObserver>
      widget_observer_{this};
  base::WeakPtrFactory<PageCapture> weak_factory_{this};
};
}
}

@interface PCNativePageCapture () {
 @public
  std::shared_ptr<parc::PageCapture> state;
}
- (instancetype)initWithPage:(PCNativePage*)page
                   contents:(content::WebContents&)contents window:(NSWindow*)window
                    purpose:(parc::PageCapturePurpose)purpose;
@end
@implementation PCNativePageCapture
@synthesize sourceURL = _sourceURL, pageTitle = _pageTitle, invalidated = _invalidated;
- (instancetype)initWithPage:(PCNativePage*)page
                   contents:(content::WebContents&)contents window:(NSWindow*)window
                    purpose:(parc::PageCapturePurpose)purpose {
  if ((self = [super init])) {
    _sourceURL = base::SysUTF8ToNSString(parc::PublicInternalURL(contents.GetLastCommittedURL()).spec());
    _pageTitle = base::SysUTF16ToNSString(contents.GetTitle());
    __weak PCNativePageCapture* weakSelf = self;
    state = std::make_shared<parc::PageCapture>(page, contents, window, purpose, ^{
      PCNativePageCapture* owner = weakSelf;
      if (owner.invalidated) owner.invalidated();
    });
    if (!state->Start()) return nil;
  }
  return self;
}
- (void)dealloc { if (state) state->Invalidate(false); }
- (BOOL)isValid { return state && state->Valid(); }
- (NSColor*)pageThemeColor { return state ? state->ThemeColor() : nil; }
- (BOOL)isCapturing { return state && state->Capturing(); }
- (NSSize)viewportSize { return state ? state->ViewportSize() : NSZeroSize; }
- (NSRect)viewportFrame { return state ? state->ViewportFrame() : NSZeroRect; }
- (void)invalidate { if (state) state->Invalidate(true); }
- (void)targetElementAtPoint:(NSPoint)point completion:(parc::TargetCompletion)completion {
  if (state) state->TargetElement(point, completion);
}
- (void)captureElement:(PCNativePageCaptureTarget*)target
           completion:(parc::CaptureCompletion)completion {
  if (state) state->CaptureElement(target, completion);
}
- (void)captureRegion:(NSRect)region completion:(parc::CaptureCompletion)completion {
  if (state) state->Capture(region, false, completion);
}
- (void)captureViewportWithCompletion:(parc::CaptureCompletion)completion {
  [self captureRegion:NSMakeRect(0, 0, self.viewportSize.width, self.viewportSize.height)
           completion:completion];
}
- (void)captureFullPageWithCompletion:(parc::CaptureCompletion)completion {
  if (state) state->Capture(NSZeroRect, true, completion);
}
@end

namespace parc {
namespace {
PCNativePageCapture* BeginPageCapture(PCNativePage* page, NSWindow* window,
                                      PageCapturePurpose purpose) {
  auto* contents = ContentsForNativePage(page);
  if (!contents || contents->IsBeingDestroyed() || !contents->GetPrimaryMainFrame() ||
      page.closed || page.nativeView.window != window) return nil;
  return [[PCNativePageCapture alloc] initWithPage:page contents:*contents window:window
                                           purpose:purpose];
}
}
}

@implementation PCNativePage (Capture)
- (BOOL)canCaptureInWindow:(NSWindow*)window {
  return parc::CaptureEligible(self, parc::ContentsForNativePage(self), window, false);
}
- (PCNativePageCapture*)beginCaptureInWindow:(NSWindow*)window {
  return parc::BeginPageCapture(self, window, parc::PageCapturePurpose::kPerson);
}
- (PCNativePageCapture*)beginPlaceholderCaptureInWindow:(NSWindow*)window {
  return parc::BeginPageCapture(self, window, parc::PageCapturePurpose::kPlaceholder);
}
@end

namespace parc {
class LiveCapturePosition final : public std::enable_shared_from_this<LiveCapturePosition> {
 public:
  LiveCapturePosition(PCNativePage* page, NSRect region, NSPoint scroll,
                      NSArray<PCNativeCaptureScrollContainer*>* containers,
                      double width, void (^completion)(BOOL))
      : page_(page), window_(page.nativeView.window), region_(region), scroll_(scroll),
        containers_(ContainersScript(containers)), width_(width), completion_([completion copy]) {
    auto* contents = ContentsForNativePage(page);
    if (contents && contents->GetPrimaryMainFrame()) {
      contents_ = contents->GetWeakPtr();
      document_ = contents->GetPrimaryMainFrame()->GetWeakDocumentPtr();
    }
  }
  void Cancel() { cancelled_ = true; Finish(false); }
  bool Valid() const {
    return !cancelled_ && page_ && !page_.closed && page_.embeddedOwnerValid &&
        window_ && page_.nativeView.window == window_ && contents_ &&
        ContentsForNativePage(page_) == contents_.get() && !contents_->IsBeingDestroyed() &&
        !contents_->IsCrashed() && !IsNativePageRetiring(page_) &&
        !IsLiveTabTransferTarget(contents_.get()) &&
        document_.AsRenderFrameHostIfValid() &&
        document_.AsRenderFrameHostIfValid()->IsRenderFrameLive() &&
        document_.AsRenderFrameHostIfValid() == contents_->GetPrimaryMainFrame();
  }
  void Run() {
    if (attempts_ == 0) {
      timer_.Start(FROM_HERE, base::Seconds(5), base::BindOnce(
          &LiveCapturePosition::Cancel, base::Unretained(this)));
    }
    if (!Valid() || attempts_++ >= 20) { Finish(false); return; }
    const double zoom = blink::ZoomLevelToZoomFactor(content::HostZoomMap::GetZoomLevel(contents_.get()));
    if (!std::isfinite(zoom) || zoom <= 0) { Finish(false); return; }
    const double scale = width_ / (region_.size.width * zoom);
    if (!std::isfinite(scale) || scale <= 0 || scale > 10000) { Finish(false); return; }
    auto n = [](double value) { return base::NumberToString(value); };
    std::string script = R"JS((() => {
      if (!document.body || !['interactive','complete'].includes(document.readyState)) return false;
      let aligned = true;)JS" + containers_ + R"JS(
      document.body.style.transformOrigin = 'top left';
      document.body.style.transform = 'scale()JS" + n(scale) + ") translate(" +
        n(-region_.origin.x) + "px," + n(-region_.origin.y) + R"JS(px)';
      window.scroll({left:)JS" + n(scroll_.x * scale) + ",top:" + n(scroll_.y * scale) + R"JS(,behavior:'instant'});
      return aligned && Math.abs(scrollX - )JS" + n(scroll_.x * scale) + ") < 3 && Math.abs(scrollY - " +
        n(scroll_.y * scale) + ") < 3; })()";
    auto self = shared_from_this();
    document_.AsRenderFrameHostIfValid()->ExecuteJavaScriptInIsolatedWorld(
        base::UTF8ToUTF16(script), base::BindOnce([](std::shared_ptr<LiveCapturePosition> owner, base::Value value) {
          if (!owner->Valid()) { owner->Finish(false); return; }
          if (value.is_bool() && value.GetBool()) { owner->Finish(true); return; }
          base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(FROM_HERE,
              base::BindOnce(&LiveCapturePosition::Run, owner), base::Milliseconds(100));
        }, self), ISOLATED_WORLD_ID_CHROME_INTERNAL);
  }
 private:
  std::string ContainersScript(NSArray<PCNativeCaptureScrollContainer*>* containers) const {
    if (containers.count == 0) return std::string();
    base::ListValue list;
    for (PCNativeCaptureScrollContainer* container in containers) {
      base::DictValue entry;
      if (container.anchorID) entry.Set("anchor", base::SysNSStringToUTF8(container.anchorID));
      else entry.Set("anchor", base::Value());
      entry.Set("path", base::SysNSStringToUTF8(container.path));
      entry.Set("x", container.scrollOffset.x);
      entry.Set("y", container.scrollOffset.y);
      entry.Set("left", container.frame.origin.x);
      entry.Set("top", container.frame.origin.y);
      entry.Set("width", container.frame.size.width);
      entry.Set("height", container.frame.size.height);
      list.Append(std::move(entry));
    }
    auto json = base::WriteJson(list);
    if (!json) return "aligned = false;";
    auto n = [](double value) { return base::NumberToString(value); };
    return "const containers = " + *json + ";" + std::string(kFindScript) + R"JS(
      document.body.style.transform = '';
      for (const c of containers) {
        c.element = find(c.anchor, c.path);
        if (!c.element) { aligned = false; continue; }
        c.element.scrollTo({left:c.x, top:c.y, behavior:'instant'});
        if (Math.abs(c.element.scrollLeft - c.x) >= 3 || Math.abs(c.element.scrollTop - c.y) >= 3) aligned = false;
      }
      window.scroll({left:)JS" + n(scroll_.x) + ",top:" + n(scroll_.y) + R"JS(,behavior:'instant'});
      for (const c of containers) {
        if (!c.element) continue;
        const r = c.element.getBoundingClientRect();
        if (Math.abs(r.left + scrollX - c.left) > 4 || Math.abs(r.top + scrollY - c.top) > 4 ||
            Math.abs(r.width - c.width) > 4 || Math.abs(r.height - c.height) > 4) aligned = false;
      })JS";
  }
  void Finish(bool success) {
    timer_.Stop();
    cancelled_ = true;
    auto callback = completion_;
    completion_ = nil;
    if (callback) base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
        base::BindOnce([](void (^block)(BOOL), bool result) { block(result); }, callback, success));
  }
  PCNativePage* __weak page_;
  NSWindow* __weak window_;
  base::WeakPtr<content::WebContents> contents_;
  content::WeakDocumentPtr document_;
  NSRect region_;
  NSPoint scroll_;
  std::string containers_;
  double width_;
  int attempts_ = 0;
  bool cancelled_ = false;
  base::OneShotTimer timer_;
  void (^completion_)(BOOL);
};
}
@interface PCNativeLiveCapturePosition () {
 @public
  std::shared_ptr<parc::LiveCapturePosition> state;
}
- (instancetype)initWithState:(std::shared_ptr<parc::LiveCapturePosition>)value;
@end
@implementation PCNativeLiveCapturePosition
- (instancetype)initWithState:(std::shared_ptr<parc::LiveCapturePosition>)value {
  if ((self = [super init])) state = std::move(value);
  return self;
}
- (void)cancel { if (state) state->Cancel(); }
- (void)dealloc { if (state) state->Cancel(); }
@end
@implementation PCNativePage (LiveCapture)
- (double)liveCaptureZoomFactor {
  auto* contents = parc::ContentsForNativePage(self);
  return contents && self.embeddedOwnerValid ?
      blink::ZoomLevelToZoomFactor(content::HostZoomMap::GetZoomLevel(contents)) : 1;
}
- (PCNativeLiveCapturePosition*)positionLiveCapture:(NSRect)region scrollOffset:(NSPoint)scroll
    scrollContainers:(NSArray<PCNativeCaptureScrollContainer*>*)containers
    displayWidth:(double)width completion:(void (^)(BOOL))completion {
  if (!containers || containers.count > parc::kMaxScrollContainers) return nil;
  for (id container in containers) {
    if (![container isKindOfClass:[PCNativeCaptureScrollContainer class]]) return nil;
  }
  if (!self.embeddedOwnerValid || !completion || !std::isfinite(width) || width <= 0 || width > 1000000 ||
      !std::isfinite(region.origin.x) || !std::isfinite(region.origin.y) ||
      !std::isfinite(region.size.width) || !std::isfinite(region.size.height) ||
      !std::isfinite(scroll.x) || !std::isfinite(scroll.y) || region.origin.x < 0 || region.origin.y < 0 ||
      region.size.width <= 0 || region.size.height <= 0 || NSMaxX(region) > 16385 || NSMaxY(region) > 16385 ||
      std::abs(scroll.x) > 1000000 || std::abs(scroll.y) > 1000000) return nil;
  auto state = std::make_shared<parc::LiveCapturePosition>(self, region, scroll, containers, width,
                                                           completion);
  if (!state->Valid()) return nil;
  auto request = [[PCNativeLiveCapturePosition alloc] initWithState:state];
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce(&parc::LiveCapturePosition::Run, state));
  return request;
}
@end

namespace parc {
class EmbeddedPageSnapshot final : public std::enable_shared_from_this<EmbeddedPageSnapshot> {
 public:
  EmbeddedPageSnapshot(PCNativePage* page, content::WebContents& contents,
                       CaptureCompletion completion)
      : page_(page), contents_(contents.GetWeakPtr()),
        document_(contents.GetPrimaryMainFrame()->GetWeakDocumentPtr()),
        completion_([completion copy]), runner_(base::SequencedTaskRunner::GetCurrentDefault()) {}
  ~EmbeddedPageSnapshot() {
    if (capturer_) {
      runner_->PostTask(FROM_HERE, base::BindOnce([](base::ScopedClosureRunner) {}, std::move(capturer_)));
    }
    if (completion_) Reply(runner_, completion_, EncodedCapture());
  }
  static bool Eligible(PCNativePage* page, content::WebContents* contents) {
    if (!page || page.closed || !page.embeddedOwnerValid || !contents ||
        contents->IsBeingDestroyed() || contents->IsCrashed() || !contents->GetPrimaryMainFrame() ||
        !contents->GetPrimaryMainFrame()->IsRenderFrameLive() ||
        !contents->GetRenderWidgetHostView() || IsNativePageRetiring(page) ||
        IsLiveTabTransferTarget(contents)) return false;
    auto* profile = Profile::FromBrowserContext(contents->GetBrowserContext());
    if (!profile || profile->ShutdownStarted() || IsNativeProfileRemovalBlocked(profile->GetPath()) ||
        profile->GetPrefs()->GetBoolean(prefs::kDisableScreenshots)) return false;
#if BUILDFLAG(ENTERPRISE_SCREENSHOT_PROTECTION)
    auto* controller = enterprise_data_protection::DataProtectionNavigationController::
        FromWebContents(contents);
    if (controller && !controller->screenshot_allowed()) return false;
#endif
    return true;
  }
  void Start() {
    if (!Valid()) { Finish(EncodedCapture()); return; }
    capturer_ = contents_->IncrementCapturerCount(gfx::Size(), true, false, false);
    runner_->PostDelayedTask(FROM_HERE, base::BindOnce([](std::weak_ptr<EmbeddedPageSnapshot> weak) {
      if (auto owner = weak.lock()) owner->Finish(EncodedCapture());
    }, weak_from_this()), base::Seconds(5));
    Attempt();
  }

 private:
  bool Valid() const {
    return !finished_ && page_ && contents_ && ContentsForNativePage(page_) == contents_.get() &&
        Eligible(page_, contents_.get()) &&
        document_.AsRenderFrameHostIfValid() == contents_->GetPrimaryMainFrame();
  }
  void Attempt() {
    if (finished_) return;
    if (!Valid()) { Finish(EncodedCapture()); return; }
    auto* view = contents_->GetRenderWidgetHostView();
    if (!view->IsSurfaceAvailableForCopy() || view->GetViewBounds().IsEmpty()) { Retry(); return; }
    view->CopyFromSurface(gfx::Rect(), gfx::Size(), base::Seconds(2), base::BindOnce(
        [](scoped_refptr<base::SequencedTaskRunner> runner,
           std::shared_ptr<EmbeddedPageSnapshot> owner, const content::CopyFromSurfaceResult& result) {
          runner->PostTask(FROM_HERE, base::BindOnce(&EmbeddedPageSnapshot::Copied, owner,
              result.has_value() ? result->bitmap : SkBitmap()));
        }, runner_, shared_from_this()));
  }
  void Retry() {
    if (++attempts_ >= 20) { Finish(EncodedCapture()); return; }
    runner_->PostDelayedTask(FROM_HERE,
        base::BindOnce(&EmbeddedPageSnapshot::Attempt, shared_from_this()), base::Milliseconds(100));
  }
  void Copied(SkBitmap bitmap) {
    if (finished_) return;
    if (!Valid()) { Finish(EncodedCapture()); return; }
    if (bitmap.drawsNothing()) { Retry(); return; }
    base::ThreadPool::PostTaskAndReplyWithResult(FROM_HERE,
        {base::TaskPriority::USER_VISIBLE}, base::BindOnce(&EncodeBitmap, std::move(bitmap)),
        base::BindOnce(&EmbeddedPageSnapshot::Finish, shared_from_this()));
  }
  void Finish(EncodedCapture encoded) {
    if (finished_) return;
    finished_ = true;
    capturer_.RunAndReset();
    auto completion = completion_;
    completion_ = nil;
    Reply(runner_, completion, std::move(encoded));
  }
  static void Reply(scoped_refptr<base::SequencedTaskRunner> runner, CaptureCompletion completion,
                    EncodedCapture encoded) {
    NSData* data = encoded.png.empty() ? nil :
        [NSData dataWithBytes:encoded.png.data() length:encoded.png.size()];
    auto result = [[PCNativePageCaptureResult alloc] initWithData:data
        size:NSMakeSize(encoded.pixels.width(), encoded.pixels.height())
        error:data ? nil : @"The embedded page could not be captured."
        layout:nil];
    runner->PostTask(FROM_HERE, base::BindOnce(
        [](CaptureCompletion callback, PCNativePageCaptureResult* value) { callback(value); },
        completion, result));
  }
  PCNativePage* __weak page_;
  base::WeakPtr<content::WebContents> contents_;
  content::WeakDocumentPtr document_;
  CaptureCompletion completion_ = nil;
  scoped_refptr<base::SequencedTaskRunner> runner_;
  base::ScopedClosureRunner capturer_;
  int attempts_ = 0;
  bool finished_ = false;
};
}
@implementation PCNativePage (EmbeddedSnapshot)
- (BOOL)snapshotEmbeddedPageWithCompletion:(void (^)(PCNativePageCaptureResult*))completion {
  auto* contents = parc::ContentsForNativePage(self);
  if (!completion || !parc::EmbeddedPageSnapshot::Eligible(self, contents)) return NO;
  auto state = std::make_shared<parc::EmbeddedPageSnapshot>(self, *contents, completion);
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE,
      base::BindOnce(&parc::EmbeddedPageSnapshot::Start, state));
  return YES;
}
@end

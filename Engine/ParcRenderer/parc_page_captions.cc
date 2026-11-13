// Copyright 2026 Parc contributors.

#include "third_party/blink/renderer/core/html/media/parc_page_captions.h"

#include <algorithm>
#include <cmath>

#include "third_party/blink/renderer/core/css/style_change_reason.h"
#include "third_party/blink/renderer/core/dom/element.h"
#include "third_party/blink/renderer/core/dom/flat_tree_traversal.h"
#include "third_party/blink/renderer/core/dom/node_traversal.h"
#include "third_party/blink/renderer/core/dom/shadow_root.h"
#include "third_party/blink/renderer/core/dom/text.h"
#include "third_party/blink/renderer/core/editing/editing_utilities.h"
#include "third_party/blink/renderer/core/frame/local_frame.h"
#include "third_party/blink/renderer/core/frame/local_frame_view.h"
#include "third_party/blink/renderer/core/html/html_body_element.h"
#include "third_party/blink/renderer/core/html/html_frame_owner_element.h"
#include "third_party/blink/renderer/core/html/html_summary_element.h"
#include "third_party/blink/renderer/core/html/media/html_video_element.h"
#include "third_party/blink/renderer/core/html/media/parc_picture_in_picture_captions.h"
#include "third_party/blink/renderer/core/html/parser/html_parser_idioms.h"
#include "third_party/blink/renderer/core/html/track/text_track_container.h"
#include "third_party/blink/renderer/core/html_names.h"
#include "third_party/blink/renderer/core/layout/layout_box_model_object.h"
#include "third_party/blink/renderer/core/layout/layout_text.h"
#include "third_party/blink/renderer/core/layout/layout_video.h"
#include "third_party/blink/renderer/core/style/computed_style.h"
#include "third_party/blink/renderer/platform/heap/collection_support/heap_hash_set.h"
#include "third_party/blink/renderer/platform/heap/disallow_new_wrapper.h"
#include "third_party/blink/renderer/platform/heap/persistent.h"
#include "third_party/blink/renderer/platform/wtf/std_lib_extras.h"
#include "third_party/blink/renderer/platform/wtf/text/string_builder.h"
#include "ui/gfx/geometry/size_f.h"

#include "cc/paint/skia_paint_canvas.h"
#include "third_party/blink/renderer/core/dom/element_traversal.h"
#include "third_party/blink/renderer/core/html/media/html_media_element.h"
#include "third_party/blink/renderer/core/paint/cull_rect_updater.h"
#include "third_party/blink/renderer/core/paint/paint_layer.h"
#include "third_party/blink/renderer/core/paint/paint_layer_painter.h"
#include "third_party/blink/renderer/platform/graphics/paint/paint_record_builder.h"
#include "ui/gfx/geometry/quad_f.h"
#include "ui/gfx/geometry/rect_conversions.h"
#include "ui/gfx/geometry/size_conversions.h"

namespace blink {

namespace {

constexpr wtf_size_t kMaxPlaces = 16;

constexpr unsigned kMaxNodes = 5000;

constexpr unsigned kMaxPathDepth = 32;

HeapHashSet<WeakMember<Element>>& BoxesShownAsCaptions() {
  using BoxSetHolder = DisallowNewWrapper<HeapHashSet<WeakMember<Element>>>;
  DEFINE_STATIC_LOCAL(Persistent<BoxSetHolder>, holder,
                      (MakeGarbageCollected<BoxSetHolder>()));
  return holder->Value();
}

bool NamesCaptions(const AtomicString& value) {
  if (value.empty()) {
    return false;
  }
  const String lower = value.GetString().ToAsciiLower();
  return lower.contains("caption") || lower.contains("subtitles") ||
         lower.contains("timedtext") || lower.contains("timed-text") ||
         lower.contains("text-track");
}

bool HasCaptionName(const Element& element) {
  if (NamesCaptions(element.GetIdAttribute()) ||
      NamesCaptions(element.GetClassAttribute())) {
    return true;
  }
  for (const Attribute& attribute : element.AttributesWithoutUpdate()) {
    if (attribute.LocalName().starts_with("data-") &&
        NamesCaptions(attribute.Value())) {
      return true;
    }
  }
  return false;
}

bool HasControlRole(const Element& element) {
  static constexpr const char* kRoles[] = {
      "button",   "checkbox", "combobox", "dialog",    "grid",
      "gridcell", "link",     "listbox",  "marquee",   "menu",
      "menubar",  "menuitem", "menuitemcheckbox",      "menuitemradio",
      "option",   "progressbar",          "radio",     "radiogroup",
      "scrollbar", "searchbox", "slider", "spinbutton", "switch",
      "tab",      "tablist",  "textbox",  "timer",     "toolbar",
      "tree",     "treegrid", "treeitem"};
  const AtomicString& role = element.FastGetAttribute(html_names::kRoleAttr);
  if (role.empty()) {
    return false;
  }
  for (const String& token : role.GetString().Split(" ")) {
    for (const char* control : kRoles) {
      if (EqualIgnoringAsciiCase(token, control)) {
        return true;
      }
    }
  }
  return false;
}

bool IsControl(const Element& element) {
  return element.IsFormControlElement() || element.IsLink() ||
         IsA<HTMLSummaryElement>(element) || IsEditable(element) ||
         HasControlRole(element) ||
         element.HasTagName(html_names::kFigcaptionTag);
}

bool IsLiveRegion(const Element& element) {
  const AtomicString& live =
      element.FastGetAttribute(html_names::kAriaLiveAttr);
  return EqualIgnoringAsciiCase(live, "polite") ||
         EqualIgnoringAsciiCase(live, "assertive");
}

bool IsFocusable(const Element& element) {
  int tab_index = 0;
  return element.FastHasAttribute(html_names::kTabindexAttr) &&
         ParseHTMLInteger(element.FastGetAttribute(html_names::kTabindexAttr),
                          tab_index) &&
         tab_index >= 0;
}

bool IsTransparent(const Element& element) {
  const ComputedStyle* style = element.GetComputedStyle();
  return style && style->Opacity() == 0 &&
         !IsParcPictureInPictureCaptions(element);
}

std::optional<gfx::RectF> VisibleText(const Text& text,
                                      const gfx::RectF& region) {
  const LayoutObject* layout = text.GetLayoutObject();
  if (!layout || layout->Style().Visibility() != EVisibility::kVisible ||
      text.data().ContainsOnlyWhitespaceOrEmpty()) {
    return std::nullopt;
  }
  const gfx::RectF box = layout->AbsoluteBoundingBoxRectF();
  if (box.width() < 2 || box.height() < 2 ||
      !region.Contains(box.CenterPoint())) {
    return std::nullopt;
  }
  return box;
}

Element* FindPlayer(const HTMLVideoElement& video) {
  const LayoutObject* layout = video.GetLayoutObject();
  if (!layout) {
    return nullptr;
  }
  const float limit = layout->AbsoluteBoundingBoxRectF().size().GetArea() * 2;
  Element* found = nullptr;
  for (Element* parent = FlatTreeTraversal::ParentElement(video);
       limit && parent && !IsA<HTMLBodyElement>(*parent) &&
       parent != video.GetDocument().documentElement();
       parent = FlatTreeTraversal::ParentElement(*parent)) {
    const LayoutObject* parent_layout = parent->GetLayoutObject();
    if (!parent_layout) {
      continue;
    }
    if (parent_layout->AbsoluteBoundingBoxRectF().size().GetArea() > limit) {
      break;
    }
    found = parent;
  }
  return found;
}

class CaptionsFinder {
  STACK_ALLOCATED();

 public:
  CaptionsFinder(const gfx::RectF& region, HeapVector<Member<Element>>& found)
      : region_(region), found_(found) {}

  struct Look {
    bool excluded = false;
    bool text = false;
  };

  Look Visit(Element& element, bool hidden, bool in_control) {
    Look look;
    if (++visited_ > kMaxNodes || IsA<HTMLMediaElement>(element) ||
        IsA<HTMLFrameOwnerElement>(element)) {
      look.excluded = true;
      return look;
    }
    in_control = in_control || IsControl(element);
    look.excluded = in_control || IsFocusable(element);
    hidden = hidden || IsTransparent(element);
    HeapVector<Member<Element>> candidates;
    for (Node& child : FlatTreeTraversal::ChildrenOf(element)) {
      if (auto* text = DynamicTo<Text>(child)) {
        look.text |= ++visited_ <= kMaxNodes && !hidden && !in_control &&
                     VisibleText(*text, region_);
      } else if (auto* child_element = DynamicTo<Element>(child)) {
        const Look child_look = Visit(*child_element, hidden, in_control);

        if (!child_look.excluded && child_look.text &&
            IsA<LayoutBoxModelObject>(child_element->GetLayoutObject())) {
          candidates.push_back(child_element);
        }
        look.excluded |= child_look.excluded;
        look.text |= child_look.text;
      }
    }
    if (look.excluded) {
      for (Element* candidate : candidates) {
        found_.push_back(candidate);
      }
    }
    return look;
  }

 private:
  const gfx::RectF& region_;
  HeapVector<Member<Element>>& found_;
  unsigned visited_ = 0;
};

struct Caption {
  StringBuilder text;
  gfx::RectF text_area;
  gfx::RectF area;
  bool named = false;
  bool live = false;
};

void CollectText(const Element& element,
                 const gfx::RectF& region,
                 bool hidden,
                 Caption& caption) {
  caption.named = caption.named || HasCaptionName(element);
  caption.live = caption.live || IsLiveRegion(element);
  hidden = hidden || IsTransparent(element);
  for (Node& child : FlatTreeTraversal::ChildrenOf(element)) {
    if (auto* text_node = DynamicTo<Text>(child)) {
      const std::optional<gfx::RectF> box =
          hidden ? std::nullopt : VisibleText(*text_node, region);
      if (!box) {
        continue;
      }
      if (!caption.text.empty()) {
        caption.text.Append('\n');
      }
      caption.text.Append(text_node->data().StripWhiteSpace());
      caption.text_area.Union(*box);
      const LayoutObject& layout = *text_node->GetLayoutObject();
      gfx::RectF area = *box;
      if (const LayoutObject* parent = layout.Parent()) {
        area.Union(parent->AbsoluteBoundingBoxRectF());
      }
      area.Outset(layout.Style().ComputedFontSize() / 4);
      caption.area.Union(area);
    } else if (auto* child_element = DynamicTo<Element>(child)) {
      CollectText(*child_element, region, hidden, caption);
    }
  }
}

gfx::RectF VideoBox(const HTMLVideoElement& video) {
  const LayoutObject* layout = video.GetLayoutObject();
  return layout ? layout->AbsoluteBoundingBoxRectF() : gfx::RectF();
}

gfx::RectF CaptionRegion(const gfx::RectF& video) {
  gfx::RectF region = video;
  region.Outset(gfx::OutsetsF::VH(video.height() / 10, 0));
  return region;
}

}

bool IsParcPictureInPictureCaptions(const Element& element) {
  const HeapHashSet<WeakMember<Element>>& boxes = BoxesShownAsCaptions();
  return !boxes.empty() && boxes.Contains(const_cast<Element*>(&element));
}

ParcPageCaptions::ParcPageCaptions(HTMLVideoElement& video) : video_(video) {}

bool ParcPageCaptions::VideoShowsCues() const {
  if (!video_->TextTracksVisible()) {
    return false;
  }
  ShadowRoot* root = video_->UserAgentShadowRoot();
  if (!root) {
    return false;
  }
  for (Node& child : NodeTraversal::ChildrenOf(*root)) {
    if (const auto* container = DynamicTo<TextTrackContainer>(child)) {
      return ParcTextTrackContainerShowsCues(*container);
    }
  }
  return false;
}

bool ParcPageCaptions::Update() {
  Document& document = video_->GetDocument();

  if (document.DomTreeVersion() == dom_tree_version_ &&
      document.StyleVersion() == style_version_) {
    return false;
  }
  LocalFrame* frame = document.GetFrame();
  if (!frame || !frame->View() ||
      !frame->View()->UpdateAllLifecyclePhasesExceptPaint(
          DocumentUpdateReason::kOverlay)) {
    return false;
  }
  dom_tree_version_ = document.DomTreeVersion();

  if (VideoShowsCues()) {
    const bool shown = !shown_.empty();
    Show(HeapVector<Member<Element>>());
    style_version_ = document.StyleVersion();
    shown_text_ = String();
    shown_areas_.clear();
    return shown;
  }
  ++looks_;
  const gfx::RectF video = VideoBox(*video_);
  const gfx::RectF region = CaptionRegion(video);
  Element* player = FindPlayer(*video_);
  HeapVector<Member<Element>> boxes;
  if (player) {
    CaptionsFinder(region, boxes).Visit(*player, false, false);
  }

  HeapVector<Member<Element>> shown;
  StringBuilder shown_text;
  Vector<gfx::RectF> shown_areas;
  Vector<bool> seen(places_.size(), false);
  for (Element* box : boxes) {
    StringBuilder path;
    unsigned depth = 0;
    for (const Element* above = box;
         above && above != player && depth < kMaxPathDepth;
         above = FlatTreeTraversal::ParentElement(*above), ++depth) {
      path.Append(above->localName());
      if (above->HasClass()) {
        path.Append('.');
        path.Append(above->ClassNames()[0]);
      }
      path.Append('<');
    }
    Caption caption;
    CollectText(*box, region, false, caption);
    if (caption.text.empty()) {
      continue;
    }
    const String key = path.ToString();
    auto it = std::ranges::find(places_, key, &Place::path);
    if (it == places_.end()) {
      if (places_.size() == kMaxPlaces) {

        const wtf_size_t oldest = static_cast<wtf_size_t>(
            std::ranges::min_element(places_, {}, &Place::last_seen) -
            places_.begin());
        places_.EraseAt(oldest);
        seen.EraseAt(oldest);
      }
      places_.push_back(Place{key});
      seen.push_back(false);
      it = places_.end() - 1;
    }
    Place& place = *it;
    const wtf_size_t index = static_cast<wtf_size_t>(it - places_.begin());
    const String text = caption.text.ToString();

    place.text = seen[index] ? place.text + "\n" + text : text;
    seen[index] = true;
    place.last_seen = looks_;
    place.named = place.named || caption.named;
    place.live = place.live || caption.live;
    if (place.lines.size() < 2 && !place.lines.Contains(place.text)) {
      place.lines.push_back(place.text);
    }

    const gfx::PointF centre = caption.text_area.CenterPoint();
    const bool placed =
        std::abs(centre.x() - video.CenterPoint().x()) <= video.width() / 10 &&
        std::abs(centre.y() - video.CenterPoint().y()) >= video.height() / 5;
    const bool named = place.named && video.Contains(centre);
    if (named || (place.lines.size() == 2 && place.seen_empty && placed &&
                  (!place.live || place.named))) {
      shown.push_back(box);
      shown_text.Append(text);
      shown_text.Append('\n');
      caption.area.Intersect(region);
      shown_areas.push_back(caption.area);
    }
  }
  for (wtf_size_t i = 0; i < places_.size(); ++i) {
    if (!seen[i] && !places_[i].text.empty()) {
      places_[i].text = String();
      places_[i].seen_empty = true;
    }
  }

  const String text = shown_text.ToString();
  const bool changed = shown != shown_ || text != shown_text_ ||
                       shown_areas != shown_areas_;
  Show(shown);

  style_version_ = document.StyleVersion();
  shown_text_ = text;
  shown_areas_ = std::move(shown_areas);
  return changed;
}

SkBitmap ParcPageCaptions::Paint(const gfx::SizeF& window_size,
                                 float device_scale_factor,
                                 gfx::RectF& bounds) {
  Document& document = video_->GetDocument();
  LocalFrame* frame = document.GetFrame();
  if (shown_.empty() || !frame || !frame->View() || window_size.IsEmpty() ||
      !frame->View()->UpdateAllLifecyclePhasesExceptPaint(
          DocumentUpdateReason::kOverlay) ||
      document.Lifecycle().GetState() != DocumentLifecycle::kPrePaintClean) {
    return SkBitmap();
  }
  const auto* video = DynamicTo<LayoutVideo>(video_->GetLayoutObject());
  if (!video) {
    return SkBitmap();
  }
  const gfx::RectF region = CaptionRegion(VideoBox(*video_));
  HeapVector<Member<const LayoutBoxModelObject>> containers;
  Vector<gfx::RectF> areas;
  HeapVector<Member<Element>> painted;
  for (Element* box : shown_) {
    const auto* container =
        DynamicTo<LayoutBoxModelObject>(box->GetLayoutObject());
    if (&box->GetDocument() != &document || !container ||
        !container->HasLayer() || !container->IsStackingContext()) {
      continue;
    }
    Caption caption;
    CollectText(*box, region, false, caption);
    caption.area.Intersect(region);
    if (!caption.area.IsEmpty()) {
      containers.push_back(container);
      areas.push_back(caption.area);
      painted.push_back(box);
    }
  }
  SkBitmap bitmap = PaintParcLayersForPictureInPicture(
      containers, areas, *video, window_size, device_scale_factor, bounds);

  if (bitmap.drawsNothing()) {
    painted.clear();
  }
  if (painted.size() != shown_.size()) {
    Show(painted);
  }
  return bitmap;
}

void ParcPageCaptions::Clear() {
  Show(HeapVector<Member<Element>>());
  places_.clear();
  shown_text_ = String();
  shown_areas_.clear();
  dom_tree_version_ = 0;
  style_version_ = 0;
}

void ParcPageCaptions::Show(const HeapVector<Member<Element>>& boxes) {

  auto mark = [](Element& box, bool shown) {
    HeapHashSet<WeakMember<Element>>& captions = BoxesShownAsCaptions();
    if (captions.Contains(&box) == shown) {
      return;
    }
    if (shown) {
      captions.insert(&box);
    } else {
      captions.erase(&box);
    }
    box.SetNeedsStyleRecalc(kLocalStyleChange,
                            StyleChangeReasonForTracing::Create(
                                style_change_reason::kPseudoClass));
  };
  for (Element* box : shown_) {
    if (!boxes.Contains(box)) {
      mark(*box, false);
    }
  }
  for (Element* box : boxes) {
    mark(*box, true);
  }
  shown_ = boxes;
}

void ParcPageCaptions::Trace(Visitor* visitor) const {
  visitor->Trace(video_);
  visitor->Trace(shown_);
}

SkBitmap PaintParcTextTracksForPictureInPicture(
    TextTrackContainer& text_track_container,
    HTMLMediaElement& media_element,
    const gfx::SizeF& window_size,
    float device_scale_factor,
    gfx::RectF& bounds) {
  LocalFrame* frame = text_track_container.GetDocument().GetFrame();
  if (!frame || !frame->View() || !text_track_container.HasChildren() || window_size.IsEmpty()) {
    return SkBitmap();
  }

  if (!frame->View()->UpdateAllLifecyclePhasesExceptPaint(
          DocumentUpdateReason::kOverlay) ||
      text_track_container.GetDocument().Lifecycle().GetState() !=
          DocumentLifecycle::kPrePaintClean) {
    return SkBitmap();
  }
  const LayoutBox* container = text_track_container.GetLayoutBox();
  const auto* video = DynamicTo<LayoutVideo>(media_element.GetLayoutObject());
  if (!container || !container->HasLayer() || !video || !ParcTextTrackContainerShowsCues(text_track_container)) {
    return SkBitmap();
  }

  gfx::RectF cues;
  for (const Element& child : ElementTraversal::ChildrenOf(text_track_container)) {
    if (const LayoutObject* object = child.GetLayoutObject()) {
      cues.Union(
          gfx::RectF(object->AbsoluteBoundingBoxRectIncludingDescendants()));
    }
  }
  cues.Intersect(gfx::RectF(container->AbsoluteBoundingBoxRect()));

  return PaintParcLayersForPictureInPicture({container}, {cues}, *video,
                                        window_size, device_scale_factor,
                                        bounds);
}

bool ParcTextTrackContainerShowsCues(
    const TextTrackContainer& text_track_container) {
  const LayoutObject* container = text_track_container.GetLayoutObject();
  if (!container) {
    return false;
  }
  for (const Node& node : NodeTraversal::DescendantsOf(text_track_container)) {
    const auto* text = DynamicTo<Text>(node);
    const LayoutObject* layout = text ? text->GetLayoutObject() : nullptr;
    if (!layout || layout->Style().Visibility() != EVisibility::kVisible ||
        text->data().ContainsOnlyWhitespaceOrEmpty()) {
      continue;
    }
    bool transparent = false;
    for (const LayoutObject* above = layout->Parent(); above && !transparent;
         above = above == container ? nullptr : above->Parent()) {
      transparent = above->Style().Opacity() == 0;
    }
    if (!transparent) {
      return true;
    }
  }
  return false;
}

SkBitmap PaintParcLayersForPictureInPicture(
    const HeapVector<Member<const LayoutBoxModelObject>>& containers,
    const Vector<gfx::RectF>& areas,
    const LayoutVideo& video,
    const gfx::SizeF& window_size,
    float device_scale_factor,
    gfx::RectF& bounds) {
  DCHECK_EQ(containers.size(), areas.size());
  gfx::RectF cues;
  for (const gfx::RectF& area : areas) {
    cues.Union(area);
  }
  const gfx::RectF video_rect(
      video.LocalToAbsoluteRect(video.ReplacedContentRect()));
  if (cues.IsEmpty() || video_rect.IsEmpty()) {
    return SkBitmap();
  }

  const float scale = std::min(window_size.width() / video_rect.width(),
                               window_size.height() / video_rect.height());
  const gfx::SizeF picture = gfx::ScaleSize(video_rect.size(), scale);
  gfx::RectF placed((cues.x() - video_rect.x()) * scale,
                    (cues.y() - video_rect.y()) * scale, cues.width() * scale,
                    cues.height() * scale);
  const float fit = std::min({1.f, picture.width() / placed.width(),
                              picture.height() / placed.height()});
  placed.ClampToCenteredSize(gfx::ScaleSize(placed.size(), fit));
  placed.set_origin(gfx::PointF(
      std::clamp(placed.x(), 0.f,
                 std::max(0.f, picture.width() - placed.width())),
      std::clamp(placed.y(), 0.f,
                 std::max(0.f, picture.height() - placed.height()))));
  const float pixels = scale * fit * device_scale_factor;
  const gfx::Size size = gfx::ToCeiledSize(gfx::ScaleSize(cues.size(), pixels));
  constexpr int kMaxDimension = 8192;
  SkBitmap bitmap;
  if (size.IsEmpty() || size.width() > kMaxDimension ||
      size.height() > kMaxDimension ||
      !bitmap.tryAllocN32Pixels(size.width(), size.height())) {
    return SkBitmap();
  }
  bitmap.eraseColor(SK_ColorTRANSPARENT);
  cc::SkiaPaintCanvas canvas(bitmap);

  DocumentLifecycle& lifecycle = video.GetDocument().Lifecycle();
  lifecycle.AdvanceTo(DocumentLifecycle::kInPaint);
  for (wtf_size_t i = 0; i < containers.size(); ++i) {
    const LayoutBoxModelObject& container = *containers[i];
    const gfx::RectF& area = areas[i];
    PaintLayer& layer = *container.Layer();
    gfx::RectF local =
        container.AbsoluteToLocalQuad(gfx::QuadF(area)).BoundingBox();
    if (local.IsEmpty()) {
      continue;
    }
    local.Offset(gfx::Vector2dF(container.FirstFragment().PaintOffset()));
    OverriddenCullRectScope cull_rect_scope(
        layer, CullRect(gfx::ToEnclosingRect(local)),
        true);
    PaintRecordBuilder builder;
    PaintLayerPainter(layer).Paint(builder.Context(),
                                   PaintFlag::kOmitCompositingInfo);

    canvas.save();
    canvas.translate((area.x() - cues.x()) * pixels,
                     (area.y() - cues.y()) * pixels);
    canvas.scale(area.width() * pixels / local.width(),
                 area.height() * pixels / local.height());
    canvas.translate(-local.x(), -local.y());
    builder.EndRecording(
        canvas, container.FirstFragment().LocalBorderBoxProperties().Unalias());
    canvas.restore();
  }
  lifecycle.AdvanceTo(DocumentLifecycle::kPaintClean);

  bounds = gfx::ScaleRect(placed, 1 / picture.width(), 1 / picture.height());
  return bitmap;
}

}

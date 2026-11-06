// Copyright 2026 Parc contributors.
#include "third_party/blink/renderer/core/frame/parc_top_band_color_tracker.h"

#include <algorithm>
#include <utility>

#include "cc/paint/paint_flags.h"
#include "cc/paint/skia_paint_canvas.h"
#include "third_party/blink/public/common/parc/top_band_color_sampling.h"
#include "third_party/blink/public/platform/interface_registry.h"
#include "third_party/blink/public/platform/task_type.h"
#include "third_party/blink/renderer/core/css/css_value.h"
#include "third_party/blink/renderer/core/css/properties/longhands.h"
#include "third_party/blink/renderer/core/dom/document.h"
#include "third_party/blink/renderer/core/dom/element.h"
#include "third_party/blink/renderer/core/frame/local_frame.h"
#include "third_party/blink/renderer/core/frame/local_frame_view.h"
#include "third_party/blink/renderer/core/html/canvas/html_canvas_element.h"
#include "third_party/blink/renderer/core/html/html_image_element.h"
#include "third_party/blink/renderer/core/html/media/html_video_element.h"
#include "third_party/blink/renderer/core/layout/hit_test_location.h"
#include "third_party/blink/renderer/core/layout/hit_test_request.h"
#include "third_party/blink/renderer/core/layout/hit_test_result.h"
#include "third_party/blink/renderer/core/layout/layout_object.h"
#include "third_party/blink/renderer/core/layout/layout_view.h"
#include "third_party/blink/renderer/core/loader/resource/image_resource_content.h"
#include "third_party/blink/renderer/core/page/chrome_client.h"
#include "third_party/blink/renderer/core/page/page.h"
#include "third_party/blink/renderer/core/paint/paint_layer_scrollable_area.h"
#include "third_party/blink/renderer/core/style/computed_style.h"
#include "third_party/blink/renderer/core/style/fill_layer.h"
#include "third_party/blink/renderer/core/style/style_image.h"
#include "third_party/blink/renderer/platform/graphics/graphics_context.h"
#include "third_party/blink/renderer/platform/graphics/image.h"
#include "third_party/blink/renderer/platform/wtf/functional.h"
#include "third_party/blink/renderer/platform/wtf/text/atomic_string.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "ui/gfx/geometry/size.h"

namespace blink {

namespace {

namespace top_band = ::parc::top_band;

// 0x4686a2c's style test: a visible, displayed element with some opacity.
bool IsShown(const ComputedStyle& style) {
  return style.Visibility() == EVisibility::kVisible &&
         style.Display() != EDisplay::kNone && style.Opacity() > 0;
}

// The element a hit-test node stands for at a sample point, if it spans the
// top band (0x4686a2c).
Element* BandElement(Node* node, int viewport_width) {
  auto* element = DynamicTo<Element>(node);
  if (!element) {
    return nullptr;
  }
  const ComputedStyle* style = element->GetComputedStyle();
  LayoutObject* layout_object = element->GetLayoutObject();
  if (!style || !layout_object || !IsShown(*style)) {
    return nullptr;
  }
  const gfx::Rect box = layout_object->AbsoluteBoundingBoxRect();
  return top_band::SpansBand(box.x(), box.width(), box.height(),
                             viewport_width)
             ? element
             : nullptr;
}

// Video and canvas pixels change without style changes, so neither is a band
//
// sample there (0x46852f8; tags '\n' and 'Y').
bool IsVideoOrCanvas(const Element& element) {
  return IsA<HTMLVideoElement>(element) || IsA<HTMLCanvasElement>(element);
}

bool CoveredByVideoOrCanvas(const HitTestResult::NodeSet& nodes,
                            int viewport_width) {
  for (const auto& node : nodes) {
    for (Element* element = DynamicTo<Element>(node.Get()); element;
         element = element->ParentOrShadowHostElement()) {
      if (!IsVideoOrCanvas(*element)) {
        continue;
      }
      const ComputedStyle* style = element->GetComputedStyle();
      LayoutObject* layout_object = element->GetLayoutObject();
      if (style && layout_object && IsShown(*style)) {
        const gfx::Rect box = layout_object->AbsoluteBoundingBoxRect();
        if (box.width() >= viewport_width / 3 &&
            box.height() >= top_band::kMinimumBandHeight) {
          return true;
        }
      }
      break;
    }
  }
  return false;
}

// YouTube's masthead is skipped on youtube.com, so its page background shows
// through (0x46867fc).
bool IsYouTubeMasthead(const Element& element, const Document& document) {
  DEFINE_STATIC_LOCAL(const AtomicString, masthead, ("ytd-masthead"));
  if (!element.HasClass() || !element.ClassNames().Contains(masthead)) {
    return false;
  }
  const String host = document.Url().Host().ToString();
  return host == "youtube.com" || host.ends_with(".youtube.com");
}

// A layer's image that cannot reach the top band: it does not repeat
// vertically and is anchored to the bottom edge.
bool AnchoredToBottom(const FillLayer& layer) {
  if (layer.Repeat().y != EFillRepeat::kNoRepeatFill) {
    return false;
  }
  if (layer.BackgroundYOrigin() == BackgroundEdgeOrigin::kBottom) {
    return true;
  }
  const Length& position = layer.PositionY();
  return layer.BackgroundYOrigin() == BackgroundEdgeOrigin::kTop &&
         position.IsPercent() && position.Percent() == 100;
}

// Whether the element's own pixels decide its colour (0x4685508): an <img>,
// opacity below 1, or a background image that can cover the band. A
// non-repeating bitmap shorter than half the element leaves its background
// colour in charge.
bool ColorIsUnknown(const Element& element, const ComputedStyle& style) {
  if (IsA<HTMLImageElement>(element)) {
    return true;
  }
  if (style.Opacity() < 1) {
    return true;
  }
  if (!style.HasBackgroundImage()) {
    return false;
  }
  for (const FillLayer* layer = &style.BackgroundLayers(); layer;
       layer = layer->Next()) {
    StyleImage* image = layer->GetImage();
    if (!image || !(image->IsImageResource() || image->IsGeneratedImage()) ||
        AnchoredToBottom(*layer)) {
      continue;
    }
    LayoutObject* layout_object = element.GetLayoutObject();
    ImageResourceContent* content = image->CachedImage();
    if (!image->IsImageResource() ||
        layer->Repeat().x != EFillRepeat::kNoRepeatFill || !layout_object ||
        !layout_object->IsBox() || !content) {
      return true;
    }
    const float tile =
        content->IntrinsicSize(kRespectImageOrientation).height() *
        style.EffectiveZoom();
    const float box = layout_object->AbsoluteBoundingBoxRect().height();
    if (box * 0.5f <= tile) {
      return true;
    }
  }
  return false;
}

std::optional<SkColor> SampleBitmap(const SkBitmap& bitmap) {
  if (bitmap.drawsNothing()) {
    return std::nullopt;
  }
  const auto sample = top_band::SampleBand(
      bitmap.width(), bitmap.height(), top_band::kBandRows,
      top_band::kRightMargin,
      [&bitmap](int x, int y) { return bitmap.getColor(x, y); });
  // Only an opaque sample is a colour (0x46862e4).
  if (!sample || SkColorGetA(*sample) != SK_AlphaOPAQUE) {
    return std::nullopt;
  }
  return *sample;
}

std::optional<SkBitmap> DecodedBitmap(ImageResourceContent* content) {
  if (!content || !content->IsLoaded() || content->ErrorOccurred()) {
    return std::nullopt;
  }
  Image* image = content->GetImage();
  if (!image) {
    return std::nullopt;
  }
  return image->AsSkBitmapForCurrentFrame(kRespectImageOrientation);
}

// The size a generated background is drawn at: the element's, at most
// 800 px a side (0x46862e8).
gfx::Size RasterSize(const LayoutObject& layout_object) {
  const gfx::Rect box = layout_object.AbsoluteBoundingBoxRect();
  return gfx::Size(std::min(box.width(), top_band::kMaximumRasterSize),
                   std::min(box.height(), top_band::kMaximumRasterSize));
}

// SamplePixels' inputs, in its order: an <img>'s image, else each background
// layer's image and load state, with a generated layer's value, raster size
// and resolving style.
top_band::PixelSampleMemory::Key PixelKey(Element& element,
                                          const ComputedStyle& style) {
  top_band::PixelSource source;
  if (const auto* image_element = DynamicTo<HTMLImageElement>(element)) {
    ImageResourceContent* content = image_element->CachedImage();
    source.AddImage(content, content && content->IsLoaded());
  } else if (style.HasBackgroundImage()) {
    LayoutObject* layout_object = element.GetLayoutObject();
    const gfx::Size raster = layout_object && layout_object->IsBox()
                                 ? RasterSize(*layout_object)
                                 : gfx::Size();
    for (const FillLayer* layer = &style.BackgroundLayers(); layer;
         layer = layer->Next()) {
      StyleImage* image = layer->GetImage();
      if (!image) {
        continue;
      }
      if (image->IsGeneratedImage()) {
        // A re-resolved value is a new object with the same text.
        const CSSValue* value = image->CssValue();
        const String text = value ? value->CssText() : String();
        source.AddGenerated(
            text.Impl() ? text.Impl()->GetHash() : 0, raster.width(),
            raster.height(),
            style.VisitedDependentColor(GetCSSPropertyColor()).Rgb(),
            static_cast<int>(style.UsedColorScheme()), style.EffectiveZoom());
      } else {
        source.AddImage(image->Data(), image->IsLoaded());
      }
    }
  }
  return {DOMNodeIds::IdForNode(&element), source.value()};
}

// 0x4685778–0x46862e4: an <img>'s decoded pixels, else the first background
// layer with an image. A generated one is drawn at RasterSize into a bitmap
// of only the band rows SampleBand reads.
std::optional<SkColor> SamplePixels(const Element& element,
                                    const ComputedStyle& style) {
  if (const auto* image_element = DynamicTo<HTMLImageElement>(element)) {
    const auto bitmap = DecodedBitmap(image_element->CachedImage());
    return bitmap ? SampleBitmap(*bitmap) : std::nullopt;
  }
  LayoutObject* layout_object = element.GetLayoutObject();
  if (!layout_object || !layout_object->IsBox() ||
      !style.HasBackgroundImage()) {
    return std::nullopt;
  }
  const gfx::Size raster_size = RasterSize(*layout_object);
  if (raster_size.IsEmpty()) {
    return std::nullopt;
  }
  const int width = raster_size.width();
  const int height = raster_size.height();
  for (const FillLayer* layer = &style.BackgroundLayers(); layer;
       layer = layer->Next()) {
    StyleImage* image = layer->GetImage();
    if (!image) {
      continue;
    }
    std::optional<SkBitmap> bitmap;
    if (image->IsImageResource()) {
      bitmap = DecodedBitmap(image->CachedImage());
    } else if (image->IsGeneratedImage()) {
      const gfx::SizeF size(width, height);
      scoped_refptr<Image> generated =
          image->GetImage(*layout_object, element, style, size);
      SkBitmap raster;
      if (generated && raster.tryAllocN32Pixels(
                           width, std::min(height, top_band::kBandRows))) {
        raster.eraseColor(SK_ColorTRANSPARENT);
        cc::SkiaPaintCanvas canvas(raster);
        const gfx::RectF rect(size);
        generated->Draw(&canvas, cc::PaintFlags(), rect, rect,
                        ImageDrawOptions());
        bitmap = std::move(raster);
      }
    }
    if (bitmap && !bitmap->drawsNothing()) {
      return SampleBitmap(*bitmap);
    }
  }
  return std::nullopt;
}

HitTestResult HitTestBand(LayoutView& layout_view,
                          const PhysicalOffset& point) {
  const HitTestRequest request(
      HitTestRequest::kReadOnly | HitTestRequest::kActive |
      HitTestRequest::kIgnoreClipping |
      HitTestRequest::kIgnorePointerEventsNone | HitTestRequest::kListBased |
      HitTestRequest::kPenetratingList);
  const HitTestLocation location(point);
  HitTestResult result(request, location);
  layout_view.HitTestNoLifecycleUpdate(location, result);
  return result;
}

// While scrolled, the first band element at the viewport's top-left decides
// whether the band follows the viewport (a fixed or sticky header) or stays
// at the document's top (0x4685104–0x4685c2c).
bool HeaderFollowsViewport(LayoutView& layout_view, int viewport_width) {
  const HitTestResult result = HitTestBand(
      layout_view, PhysicalOffset(LayoutUnit(top_band::SampleColumn(
                                      0, viewport_width)),
                                  LayoutUnit(1)));
  for (const auto& node : result.ListBasedTestResult()) {
    Element* element = BandElement(node.Get(), viewport_width);
    if (!element) {
      continue;
    }
    for (LayoutObject* object = element->GetLayoutObject();
         object && object != &layout_view; object = object->Container()) {
      if (object->IsFixedPositioned() || object->IsStickyPositioned()) {
        return true;
      }
    }
    return false;
  }
  return false;
}

}  // namespace

bool TopBandColorTracker::ChosenState::operator==(
    const ChosenState& other) const {
  if (has_color != other.has_color || (has_color && color != other.color)) {
    return false;
  }
  return sample_frame == other.sample_frame &&
         frame_sample_id == other.frame_sample_id &&
         fallback == other.fallback &&
         reuse_frame_sample == other.reuse_frame_sample;
}

// 0x4684838.
TopBandColorTracker::TopBandColorTracker(LocalFrame& frame)
    : frame_(&frame),
      task_runner_(frame.GetTaskRunner(TaskType::kInternalDefault)),
      timer_(task_runner_, this, &TopBandColorTracker::TimerFired) {
  frame.GetInterfaceRegistry()->AddAssociatedInterface(
      BindRepeating(&TopBandColorTracker::BindAgent, WrapWeakPersistent(this)));
}

void TopBandColorTracker::Trace(Visitor* visitor) const {
  visitor->Trace(frame_);
  visitor->Trace(timer_);
  visitor->Trace(agent_);
  visitor->Trace(observer_);
  visitor->Trace(sampled_style_);
}

void TopBandColorTracker::BindAgent(
    mojo::PendingAssociatedReceiver<parc::mojom::blink::TopBandColorAgent>
        receiver) {
  if (frame_->IsDetached()) {
    return;
  }
  agent_.reset();
  agent_.Bind(std::move(receiver), task_runner_);
}

void TopBandColorTracker::SetObserver(
    mojo::PendingAssociatedRemote<parc::mojom::blink::TopBandColorObserver>
        observer) {
  if (frame_->IsDetached()) {
    return;
  }
  observer_.reset();
  observer_.Bind(std::move(observer), task_runner_);
  observer_.set_disconnect_handler(BindOnce(
      &TopBandColorTracker::ObserverDisconnected, WrapWeakPersistent(this)));
  //
  // new observer gets this document's last report without a crossfade and a
  // fresh detection.
  if (has_sent_) {
    observer_->DidSampleTopBandColor(
        last_sent_.has_color ? last_sent_.color.Rgb() : 0,
        last_sent_.has_color, last_sent_.sample_frame,
        last_sent_.frame_sample_id, last_sent_.reuse_frame_sample, false);
  }
  ScheduleDetection();
}

void TopBandColorTracker::ObserverDisconnected() {
  observer_.reset();
}

// 0x46847c0: a detection asked for during the throttle runs on the next
// lifecycle update after it.
void TopBandColorTracker::TimerFired(TimerBase*) {
  if (detection_pending_) {
    ScheduleDetection();
  }
}

// Without an observer nothing is requested; SetObserver schedules one.
void TopBandColorTracker::ScheduleDetection() {
  if (!observer_.is_bound()) {
    return;
  }
  if (LocalFrameView* view = frame_->View()) {
    view->ScheduleAnimation();
  }
}

void TopBandColorTracker::FireDetection() {
  LocalFrameView* view = frame_->View();
  // Nothing listens: no browser page binds this frame.
  if (!view || !observer_.is_bound()) {
    return;
  }
  if (timer_.IsActive()) {
    detection_pending_ = true;
    if (!awaiting_presentation_ || state_ == State::kUnavailable) {
      return;
    }
    Detect(*view);
    return;
  }
  timer_.StartOneShot(base::Milliseconds(top_band::kDetectionIntervalMs),
                      FROM_HERE);
  detection_pending_ = false;
  if (state_ == State::kUnavailable) {
    return;
  }
  Detect(*view);
}

// Document::FinishedParsing: the document background may now be reported.
void TopBandColorTracker::DidFinishParsing() {
  if (finished_parsing_) {
    return;
  }
  finished_parsing_ = true;
  ScheduleDetection();
}

void TopBandColorTracker::DidUpdateLargestContentfulPaint() {
  seen_contentful_paint_ = true;
  sampled_node_ = kInvalidDOMNodeId;
  sampled_style_ = nullptr;
  sampled_at_ = base::TimeTicks();
  sampled_color_.reset();
  pixel_memory_.Forget();
  ScheduleDetection();
}

void TopBandColorTracker::DidCommitNavigation() {
  state_ = State::kInitial;
  timer_.Stop();
  has_sent_ = false;
  seen_contentful_paint_ = false;
  finished_parsing_ = false;
  crossfade_armed_ = false;
  last_sent_ = ChosenState();
  awaiting_presentation_ = false;
  pending_.reset();
  ++generation_;
  sampled_node_ = kInvalidDOMNodeId;
  sampled_style_ = nullptr;
  sampled_at_ = base::TimeTicks();
  sampled_color_.reset();
  pixel_memory_.Forget();
  frame_sample_id_ = 0;
}

// A pending document-background report waits for parsing; drop it when the
// band stops being reportable (0x4684edc, 0x4685164).
void TopBandColorTracker::CancelPendingFallback() {
  if (awaiting_presentation_ && pending_ && pending_->fallback) {
    awaiting_presentation_ = false;
    pending_.reset();
    ++generation_;
  }
}

// 0x4686b58: the same element (by node id) within 1.5 s, with an unchanged
// background and opacity.
bool TopBandColorTracker::SameElementAsLastSample(
    const Element& element) const {
  if (sampled_node_ == kInvalidDOMNodeId ||
      base::TimeTicks::Now() - sampled_at_ >=
          base::Microseconds(top_band::kSameElementWindowUs) ||
      DOMNodeIds::ExistingIdForNode(&element) != sampled_node_) {
    return false;
  }
  if (IsA<HTMLImageElement>(element)) {
    return true;
  }
  const ComputedStyle* style = element.GetComputedStyle();
  if (!style || !sampled_style_) {
    return false;
  }
  if (style == sampled_style_) {
    return true;
  }
  return style->BackgroundLayers() == sampled_style_->BackgroundLayers() &&
         style->VisitedDependentColor(GetCSSPropertyBackgroundColor()) ==
             sampled_style_->VisitedDependentColor(
                 GetCSSPropertyBackgroundColor()) &&
         style->Opacity() == sampled_style_->Opacity();
}

void TopBandColorTracker::RememberSampledElement(const Element& element) {
  sampled_node_ = DOMNodeIds::IdForNode(const_cast<Element*>(&element));
  sampled_style_ = element.GetComputedStyle();
  sampled_at_ = base::TimeTicks::Now();
}

// 0x4684c40.
void TopBandColorTracker::Detect(LocalFrameView& view) {
  Document* document = frame_->GetDocument();
  LayoutView* layout_view = document ? document->GetLayoutView() : nullptr;
  if (!layout_view) {
    if (state_ != State::kUnavailable) {
      state_ = State::kUnavailable;
      EmitChosenState(view, ChosenState());
    }
    return;
  }
  PaintLayerScrollableArea* viewport = view.LayoutViewport();
  const int width =
      viewport ? viewport->VisibleContentRect(kExcludeScrollbars).width() : 0;
  if (width < 1) {
    CancelPendingFallback();
    return;
  }
  //
  // checks rather than updating the lifecycle there. While rendering is
  // blocked the parsing-finished and LCP hooks schedule the next detection.
  if (document->Lifecycle().GetState() < DocumentLifecycle::kPrePaintClean) {
    return;
  }

  // The canvas background (the propagated root background), when opaque.
  std::optional<Color> canvas;
  const Color root = layout_view->StyleRef().VisitedDependentColor(
      GetCSSPropertyBackgroundColor());
  if (root.Alpha() >= 1) {
    canvas = root;
  }
  const bool scrolled = viewport && viewport->GetScrollOffset().y() > 0;
  bool follows_viewport = false;
  bool checked_header = false;
  bool reuse_frame_sample = false;
  top_band::BandVotes<DOMNodeId, Color> votes;
  pixel_memory_.BeginPass();
  const int64_t now_us =
      (base::TimeTicks::Now() - base::TimeTicks()).InMicroseconds();

  for (int i = 0; i < 4; ++i) {
    PhysicalOffset point(LayoutUnit(top_band::SampleColumn(i, width)),
                         LayoutUnit(1));
    if (scrolled && !checked_header) {
      checked_header = true;
      follows_viewport = HeaderFollowsViewport(*layout_view, width);
    }
    if (!follows_viewport) {
      point = view.DocumentToFrame(point);
    }
    const HitTestResult result = HitTestBand(*layout_view, point);
    const HitTestResult::NodeSet& nodes = result.ListBasedTestResult();
    const bool may_sample_frame = !CoveredByVideoOrCanvas(nodes, width);

    std::optional<Color> overlay;
    Element* overlay_element = nullptr;
    bool voted = false;
    for (const auto& node : nodes) {
      Element* element = BandElement(node.Get(), width);
      if (!element || IsVideoOrCanvas(*element) ||
          IsYouTubeMasthead(*element, *document)) {
        continue;
      }
      const ComputedStyle& style = element->ComputedStyleRef();
      const Color background =
          style.VisitedDependentColor(GetCSSPropertyBackgroundColor());
      const bool translucent = background.Alpha() > 0 && background.Alpha() < 1;
      const bool unknown = ColorIsUnknown(*element, style);
      if (!translucent && !unknown) {
        if (background.Alpha() < 1) {
          continue;
        }
        votes.ForColor(
            DOMNodeIds::IdForNode(overlay_element ? overlay_element : element),
            overlay ? background.Blend(*overlay) : background);
        voted = true;
        break;
      }
      // Before the first contentful paint a translucent or pixel-coloured
      // band is not reported at all.
      if (!seen_contentful_paint_) {
        CancelPendingFallback();
        return;
      }
      if (!unknown) {
        overlay = overlay ? background.Blend(*overlay) : background;
        if (!overlay_element) {
          overlay_element = element;
        }
        continue;
      }
      std::optional<Color> pixels;
      if (sampled_color_ && SameElementAsLastSample(*element)) {
        pixels = sampled_color_;
      } else if (const auto sampled = pixel_memory_.Color(
                     PixelKey(*element, style), now_us,
                     [&] { return SamplePixels(*element, style); })) {
        RememberSampledElement(*element);
        sampled_color_ = Color::FromSkColor(*sampled);
        pixels = sampled_color_;
      }
      if (pixels) {
        votes.ForColor(DOMNodeIds::IdForNode(element), *pixels);
        voted = true;
        break;
      }
      if (!may_sample_frame) {
        continue;
      }
      const bool same = frame_sample_id_ && SameElementAsLastSample(*element);
      if (scrolled && !same) {
        reuse_frame_sample = true;
        continue;
      }
      if (!same) {
        sampled_color_.reset();
        RememberSampledElement(*element);
        ++frame_sample_id_;
      }
      votes.ForFrameSample(DOMNodeIds::IdForNode(element), frame_sample_id_);
      voted = true;
      break;
    }
    if (voted || !canvas) {
      continue;
    }
    if (overlay) {
      votes.ForColor(DOMNodeIds::IdForNode(overlay_element),
                     canvas->Blend(*overlay));
    } else {
      votes.ForCanvas();
    }
  }

  ChosenState chosen;
  const auto choice = top_band::ChooseBand(votes, canvas, reuse_frame_sample);
  chosen.sample_frame = choice.sample_frame;
  chosen.frame_sample_id = choice.frame_sample_id;
  chosen.reuse_frame_sample = choice.reuse_frame_sample;
  if (choice.color) {
    chosen.color = *choice.color;
    chosen.has_color = true;
  }
  if (!chosen.has_color && !chosen.sample_frame) {
    // Nothing voted: the document background, once parsing has finished.
    const Color background = view.DocumentBackgroundColor();
    if (background.Alpha() >= 1) {
      if (awaiting_presentation_) {
        if (!pending_) {
          if (!finished_parsing_) {
            awaiting_presentation_ = false;
            ++generation_;
            return;
          }
        } else if (pending_->sample_frame || !finished_parsing_) {
          const bool sample_frame = pending_->sample_frame;
          awaiting_presentation_ = false;
          pending_.reset();
          ++generation_;
          if (sample_frame) {
            detection_pending_ = true;
          }
          return;
        }
      } else if (!finished_parsing_) {
        return;
      }
      chosen.color = background;
      chosen.has_color = true;
      chosen.fallback = true;
    }
  }
  state_ = State::kEmitted;
  EmitChosenState(view, chosen);
}

// 0x4687028: a frame-sample or document-background report waits for the
// next presented frame, so the browser's copy and the bar change with it.
void TopBandColorTracker::EmitChosenState(LocalFrameView& view,
                                          const ChosenState& state) {
  if (awaiting_presentation_) {
    if (pending_ && *pending_ == state) {
      return;
    }
    awaiting_presentation_ = false;
    pending_.reset();
    ++generation_;
  }
  const bool changed = !has_sent_ || !(last_sent_ == state);
  if (changed && (state.sample_frame || state.fallback)) {
    if (Page* page = frame_->GetPage()) {
      pending_ = state;
      awaiting_presentation_ = true;
      ++generation_;
      page->GetChromeClient().NotifyPresentationTime(
          *frame_, BindOnce(&TopBandColorTracker::DidPresent,
                            WrapWeakPersistent(this), generation_));
      return;
    }
  }
  SendState(state);
}

// 0x468743c.
void TopBandColorTracker::DidPresent(uint32_t generation,
                                     const viz::FrameTimingDetails&) {
  if (generation != generation_) {
    return;
  }
  awaiting_presentation_ = false;
  if (pending_) {
    const ChosenState state = *pending_;
    pending_.reset();
    SendState(state);
  }
}

// 0x46874c0. Reports before the document's first LCP update and the first
// report after it cut; later ones crossfade.
void TopBandColorTracker::SendState(const ChosenState& state) {
  if (has_sent_ && last_sent_ == state) {
    return;
  }
  has_sent_ = true;
  last_sent_ = state;
  bool crossfade = false;
  if (seen_contentful_paint_) {
    crossfade = state_ != State::kUnavailable && crossfade_armed_;
    crossfade_armed_ = true;
  }
  if (!observer_.is_bound()) {
    return;
  }
  observer_->DidSampleTopBandColor(state.has_color ? state.color.Rgb() : 0,
                                   state.has_color, state.sample_frame,
                                   state.frame_sample_id,
                                   state.reuse_frame_sample, crossfade);
}

}  // namespace blink

#include "parc/webui_branding.h"

#include <algorithm>
#include <iterator>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "base/check.h"
#include "base/containers/span.h"
#include "base/logging.h"
#include "base/memory/ref_counted_memory.h"
#include "base/no_destructor.h"
#include "base/numerics/safe_conversions.h"
#include "chrome/grit/chrome_unscaled_resources.h"
#include "chrome/grit/settings_resources.h"
#include "chrome/grit/theme_resources.h"
#include "components/grit/components_scaled_resources.h"
#include "components/grit/metrics_internals_resources.h"
#include "components/grit/version_ui_resources.h"
#include "parc/webui_branding_rules.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "third_party/skia/include/core/SkCanvas.h"
#include "third_party/skia/include/core/SkColor.h"
#include "third_party/skia/include/core/SkPaint.h"
#include "third_party/skia/include/core/SkPath.h"
#include "third_party/skia/include/core/SkPathBuilder.h"
#include "ui/base/resource/resource_bundle.h"
#include "ui/gfx/codec/png_codec.h"
#include "ui/gfx/geometry/size.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/image/image_skia.h"
#include "ui/gfx/image/image_skia_rep.h"
#include "ui/gfx/image/image_skia_source.h"
#include "ui/webui/resources/grit/webui_resources.h"

namespace parc {
namespace {

struct BrandedText {
  int id;
  std::string_view name;
};

#define PARC_BRANDED_TEXT(id) {id, #id}
constexpr BrandedText kBrandedText[] = {
    PARC_BRANDED_TEXT(IDR_WEBUI_CR_ELEMENTS_ICONS_HTML_JS),
    PARC_BRANDED_TEXT(IDR_SETTINGS_SHARED_ROLLUP_JS),
    PARC_BRANDED_TEXT(IDR_METRICS_INTERNALS_FIELD_TRIALS_HTML_JS),
    PARC_BRANDED_TEXT(IDR_VERSION_UI_ABOUT_VERSION_HTML),
};
#undef PARC_BRANDED_TEXT

constexpr bool CoversEveryRule() {
  for (const branding::ResourceEdits& rule : branding::kResourceEdits) {
    if (std::none_of(std::begin(kBrandedText), std::end(kBrandedText),
                     [&](const BrandedText& text) {
                       return text.name == rule.resource;
                     })) {
      return false;
    }
  }
  return std::size(kBrandedText) == std::size(branding::kResourceEdits);
}
static_assert(CoversEveryRule());

enum class Artwork { kMark, kFlower };

struct MarkImage {
  int id;
  int size;
  SkColor ink;
  Artwork artwork = Artwork::kMark;
};

constexpr MarkImage kMarkImages[] = {
    {IDR_PRODUCT_LOGO_32, 32, SK_ColorBLACK},
    {IDR_PRODUCT_LOGO_NAME_22, 32, SK_ColorBLACK},
    {IDR_PRODUCT_LOGO_NAME_22_WHITE, 32, SK_ColorWHITE},
    {IDR_PRODUCT_LOGO, 32, SK_ColorBLACK},
    {IDR_PRODUCT_LOGO_WHITE, 32, SK_ColorWHITE},
    {IDR_PRODUCT_FAVICON, 16, SK_ColorBLACK},
    {IDR_NTP_FAVICON, 16, SK_ColorBLACK},
    {IDR_CRASH_SAD_FAVICON, 16, SK_ColorBLACK, Artwork::kFlower},
};

SkPath BuildPath(std::string_view text, branding::Contours contours) {
  const auto commands = branding::ParsePath(text, contours);
  CHECK(commands);
  SkPathBuilder builder;
  for (const branding::PathCommand& command : *commands) {
    const auto& v = command.values;
    switch (command.verb) {
      case 'M':
        builder.moveTo(v[0], v[1]);
        break;
      case 'L':
        builder.lineTo(v[0], v[1]);
        break;
      case 'C':
        builder.cubicTo(v[0], v[1], v[2], v[3], v[4], v[5]);
        break;
      default:
        builder.close();
        break;
    }
  }
  return builder.detach();
}

const SkPath& MarkPath() {
  static const base::NoDestructor<SkPath> path(
      BuildPath(branding::kMarkPath, branding::Contours::kClosed));
  return *path;
}

const std::vector<SkPath>& FlowerPaths() {
  static const base::NoDestructor<std::vector<SkPath>> paths([] {
    std::vector<SkPath> all;
    for (const branding::Stroke& stroke : branding::kFlowerStrokes) {
      all.push_back(BuildPath(stroke.path, branding::Contours::kOpen));
    }
    return all;
  }());
  return *paths;
}

void DrawFlower(SkCanvas& canvas, int pixels, SkColor ink) {
  const float scale = static_cast<float>(pixels) / branding::kFlowerHeight;
  canvas.translate((pixels - branding::kFlowerWidth * scale) / 2, 0);
  canvas.scale(scale, scale);
  SkPaint paint;
  paint.setAntiAlias(true);
  paint.setColor(ink);
  paint.setStyle(SkPaint::kStroke_Style);
  paint.setStrokeCap(SkPaint::kRound_Cap);
  paint.setStrokeJoin(SkPaint::kRound_Join);
  for (size_t i = 0; i < std::size(branding::kFlowerStrokes); ++i) {
    paint.setStrokeWidth(branding::kFlowerStrokes[i].width);
    canvas.drawPath(FlowerPaths()[i], paint);
  }
}

SkBitmap RenderMark(int pixels, SkColor ink, Artwork artwork) {
  SkBitmap bitmap;
  bitmap.allocN32Pixels(pixels, pixels);
  bitmap.eraseColor(SK_ColorTRANSPARENT);
  SkCanvas canvas(bitmap);
  if (artwork == Artwork::kFlower) {
    DrawFlower(canvas, pixels, ink);
    return bitmap;
  }
  const float scale = static_cast<float>(pixels) / 24;
  canvas.scale(scale, scale);
  SkPaint paint;
  paint.setAntiAlias(true);
  paint.setColor(ink);
  canvas.drawPath(MarkPath(), paint);
  return bitmap;
}

std::string EncodeMark(int pixels, const MarkImage& image) {
  const auto png = gfx::PNGCodec::EncodeBGRASkBitmap(
      RenderMark(pixels, image.ink, image.artwork), false);
  CHECK(png);
  return std::string(png->begin(), png->end());
}

struct MarkBytes {
  std::string one_x;
  std::string two_x;
};

const MarkBytes& BytesFor(size_t index) {
  static const base::NoDestructor<std::vector<MarkBytes>> bytes([] {
    std::vector<MarkBytes> all;
    for (const MarkImage& image : kMarkImages) {
      all.push_back(
          {EncodeMark(image.size, image), EncodeMark(image.size * 2, image)});
    }
    return all;
  }());
  return (*bytes)[index];
}

class MarkImageSource final : public gfx::ImageSkiaSource {
 public:
  explicit MarkImageSource(const MarkImage& image) : image_(image) {}

  gfx::ImageSkiaRep GetImageForScale(float scale) override {
    return gfx::ImageSkiaRep(
        RenderMark(std::max(1, base::ClampRound(image_.size * scale)),
                   image_.ink, image_.artwork),
        scale);
  }

  bool HasRepresentationAtAllScales() const override { return true; }

 private:
  const MarkImage image_;
};

}

scoped_refptr<base::RefCountedMemory> LoadBrandedResource(
    int resource_id,
    ui::ResourceScaleFactor scale_factor) {
  if (resource_id == IDR_WEBUI_IMAGES_CHROME_LOGO_DARK_SVG) {
    return base::MakeRefCounted<base::RefCountedStaticMemory>(
        base::as_byte_span(branding::kDarkLogoSvg));
  }
  if (resource_id == IDR_PRODUCT_LOGO_SVG) {
    return base::MakeRefCounted<base::RefCountedStaticMemory>(
        base::as_byte_span(branding::kAdaptiveLogoSvg));
  }
  if (resource_id == IDR_PRODUCT_LOGO_ANIMATION_SVG) {
    return base::MakeRefCounted<base::RefCountedStaticMemory>(
        base::as_byte_span(branding::kPaddedLogoSvg));
  }
  for (const BrandedText& text : kBrandedText) {
    if (text.id != resource_id) {
      continue;
    }
    std::string contents =
        ui::ResourceBundle::GetSharedInstance().LoadDataResourceStringForScale(
            resource_id, scale_factor);
    if (contents.empty()) {
      return nullptr;
    }
    const branding::ResourceEdits* edits =
        branding::FindResourceEdits(text.name);
    CHECK(edits);
    for (std::string_view group :
         branding::ApplyResourceEdits(contents, *edits).failed) {
      LOG(ERROR) << "Parc branding no longer matches " << text.name << ": "
                 << group;
    }
    return base::MakeRefCounted<base::RefCountedString>(std::move(contents));
  }
  return nullptr;
}

bool GetBrandedImageBytes(int resource_id,
                          ui::ResourceScaleFactor scale_factor,
                          std::string_view* value) {
  for (size_t i = 0; i < std::size(kMarkImages); ++i) {
    if (kMarkImages[i].id != resource_id) {
      continue;
    }
    const MarkBytes& bytes = BytesFor(i);
    *value = ui::GetScaleForResourceScaleFactor(scale_factor) > 1
                 ? bytes.two_x
                 : bytes.one_x;
    return true;
  }
  return false;
}

gfx::Image GetBrandedImage(int resource_id) {
  for (const MarkImage& image : kMarkImages) {
    if (image.id == resource_id) {
      gfx::ImageSkia mark(
          std::make_unique<MarkImageSource>(image),
          gfx::Size(image.size, image.size));
      mark.SetReadOnly();
      return gfx::Image(mark);
    }
  }
  return gfx::Image();
}

}

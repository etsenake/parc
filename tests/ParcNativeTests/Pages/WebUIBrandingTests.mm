#import "ParcNativeTest.h"

#include <algorithm>
#include <cstdio>
#include <iterator>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>

#include "webui_branding_rules.h"

using parc::branding::ApplyResourceEdits;
using parc::branding::Contours;
using parc::branding::Edit;
using parc::branding::EditGroup;
using parc::branding::EditOutcome;
using parc::branding::FindEdit;
using parc::branding::FindResourceEdits;
using parc::branding::kAdaptiveLogoSvg;
using parc::branding::kDarkLogoSvg;
using parc::branding::kFlowerHeight;
using parc::branding::kFlowerStrokes;
using parc::branding::kFlowerWidth;
using parc::branding::kMarkPath;
using parc::branding::kPaddedLogoSvg;
using parc::branding::kProductIcon;
using parc::branding::ParsePath;
using parc::branding::ResourceEdits;

namespace {

size_t Count(std::string_view text, std::string_view needle) {
  size_t count = 0;
  for (size_t at = text.find(needle); at != std::string_view::npos;
       at = text.find(needle, at + needle.size())) {
    ++count;
  }
  return count;
}

bool Has(const std::vector<std::string_view>& names, std::string_view name) {
  for (std::string_view entry : names) {
    if (entry == name) {
      return true;
    }
  }
  return false;
}

const ResourceEdits& Rules(std::string_view name) {
  const ResourceEdits* rules = FindResourceEdits(name);
  PARC_CHECK(rules != nullptr);
  return *rules;
}

std::string ChromiumIcon(std::string_view viewbox) {
  return std::string("      <g id=\"chrome-product\"") + std::string(viewbox) +
         ">\n        <path d=\"M9.45 14.574c.698.7 1.55 1.051 2.55 1.051Z\">"
         "\n        </path>\n      </g>\n";
}

std::string IconSet(int size, int product_icons) {
  std::string text = "<cr-iconset name=\"cr\" size=\"" + std::to_string(size) +
                     "\">\n  <svg>\n    <defs>\n      <g id=\"chevron-left\">"
                     "<path d=\"M15.41 7.41L14 6z\"></path></g>\n";
  for (int i = 0; i < product_icons; ++i) {
    text += ChromiumIcon(i % 2 ? " viewBox=\"0 -960 960 960\"" : "");
  }
  return text + "      <g id=\"close\"><path d=\"M19 6.41z\"></path></g>\n"
                "    </defs>\n  </svg>\n</cr-iconset>\n";
}

constexpr std::string_view kAboutTemplate =
    "<settings-section page-title=\"$i18n{aboutPageTitle}\">\n"
    "  <div class=\"cr-row two-line first\">\n"
    "    <img id=\"productLogo\" @click=\"${this.onProductLogoClick_}\"\n"
    "        srcset=\"chrome://theme/current-channel-logo@1x 1x,\n"
    "                chrome://theme/current-channel-logo@2x 2x\"\n"
    "        alt=\"$i18n{aboutProductLogoAlt}\"\n"
    "        role=\"presentation\">\n"
    "    <div class=\"product-title\">$i18n{aboutProductTitle}</div>\n"
    "  </div>\n";

}

static NSXMLElement* Svg(std::string_view text) {
  NSString* string = [[NSString alloc] initWithBytes:text.data() length:text.size() encoding:NSUTF8StringEncoding];
  NSXMLDocument* document = [[NSXMLDocument alloc] initWithXMLString:string options:0 error:nil];
  return document.rootElement;
}

static NSString* PathOf(NSXMLElement* element) {
  NSArray<NSXMLNode*>* paths = [element nodesForXPath:@".//*[local-name()='path']" error:nil];
  if (paths.count != 1) return nil;
  return [(NSXMLElement*)paths.firstObject attributeForName:@"d"].stringValue;
}

static NSString* Mark(void) {
  return [[NSString alloc] initWithBytes:kMarkPath.data() length:kMarkPath.size() encoding:NSUTF8StringEncoding];
}
static void CheckAppearance(std::string_view text, NSString* box) {
  NSXMLElement* logo = Svg(text);
  NSXMLNode* style = [logo nodesForXPath:@".//*[local-name()='style']" error:nil].firstObject;
  PARC_CHECK([[logo attributeForName:@"viewBox"].stringValue isEqual:box] && [PathOf(logo) isEqual:Mark()] &&
             [style.stringValue containsString:@"prefers-color-scheme: dark"]);
}
@interface ParcNativeTests_WebUIBrandingTests : ParcNativeTestCase
@end

@implementation ParcNativeTests_WebUIBrandingTests

- (void)testTheTwoContoursOfTheMarkFitInsideItsViewBox {
  const auto commands = ParsePath(kMarkPath);
  PARC_CHECK(commands.has_value());
  size_t contours = 0;
  float top = 24, bottom = 0, left = 24, right = 0;
  for (const auto& command : *commands) {
    PARC_CHECK(command.verb == 'M' || command.verb == 'C' ||
                command.verb == 'Z');
    contours += command.verb == 'M';
    const size_t arity = command.verb == 'C' ? 6 : command.verb == 'M' ? 2 : 0;
    for (size_t i = 0; i < arity; i += 2) {
      left = std::min(left, command.values[i]);
      right = std::max(right, command.values[i]);
      top = std::min(top, command.values[i + 1]);
      bottom = std::max(bottom, command.values[i + 1]);
    }
  }
  PARC_CHECK(contours == 2);
  PARC_CHECK(left >= 0 && top >= 0 && right <= 24 && bottom <= 24);
}

- (void)testAnEmptyPathIsRejected {
  PARC_CHECK(!ParsePath("").has_value());
}

- (void)testAPathMustStartWithMove {
  PARC_CHECK(!ParsePath("C1 2 3 4 5 6Z").has_value());
}

- (void)testAnIncompleteCubicIsRejected {
  PARC_CHECK(!ParsePath("M1 2C1 2Z").has_value());
}

- (void)testAnOpenContourIsRejected {
  PARC_CHECK(!ParsePath("M1 2L3 4").has_value());
}

- (void)testAnUnknownVerbIsRejected {
  PARC_CHECK(!ParsePath("M1 2X3 4Z").has_value());
}

- (void)testASecondMoveCannotDiscardAnOpenContour {
  PARC_CHECK(!ParsePath("M1 2M3 4Z").has_value());
}

- (void)testACoordinateNeedsDigits {
  PARC_CHECK(!ParsePath("M1 2L.Z").has_value());
}

- (void)testEveryFlowerStrokeIsOneOpenLineInsideItsCanvas {
  PARC_CHECK(std::size(kFlowerStrokes) == 5);
  for (const auto& stroke : kFlowerStrokes) {
    const auto commands = ParsePath(stroke.path, Contours::kOpen);
    PARC_CHECK(commands.has_value() && commands->front().verb == 'M');
    PARC_CHECK(stroke.width == 8.5f || stroke.width == 6.8f);
    const float half = stroke.width / 2;
    for (const auto& command : *commands) {
      PARC_CHECK(command.verb != 'M' || &command == &commands->front());
      const size_t arity = command.verb == 'C' ? 6 : 2;
      for (size_t i = 0; i < arity; i += 2) {
        PARC_CHECK(command.values[i] - half >= 0 && command.values[i] + half <= kFlowerWidth);
        PARC_CHECK(command.values[i + 1] - half >= 0 && command.values[i + 1] + half <= kFlowerHeight);
      }
    }
  }
}

- (void)testAnOpenStrokeRejectsClosingAndSecondMoves {
  PARC_CHECK(!ParsePath("M1 2L3 4Z", Contours::kOpen).has_value());
  PARC_CHECK(!ParsePath("M1 2L3 4M5 6L7 8", Contours::kOpen).has_value());
  PARC_CHECK(!ParsePath("M1 2", Contours::kOpen).has_value());
  PARC_CHECK(ParsePath("M1 2L3 4C5 6 7 8 9 10", Contours::kOpen).has_value());
}

- (void)testTheParserReadsSignedFractionalCoordinatesAcrossContours {
  const auto parsed = ParsePath("M1 2L3.5 -4Z M.25 6C1 2 3 4 5 6Z");
  PARC_CHECK(parsed.has_value() && parsed->size() == 6);
  PARC_CHECK((*parsed)[1].values[0] == 3.5f && (*parsed)[1].values[1] == -4);
  PARC_CHECK((*parsed)[3].values[0] == 0.25f);
}

- (void)testIconsReplaceOnlyTheProductGroups {
  const ResourceEdits& rules = Rules("IDR_WEBUI_CR_ELEMENTS_ICONS_HTML_JS");
  const std::string original = IconSet(20, 0) + IconSet(24, 1) + IconSet(24, 1);
  std::string text = original;
  EditOutcome outcome = ApplyResourceEdits(text, rules);
  PARC_CHECK(outcome.failed.empty() && Has(outcome.applied, "product icon"));
  PARC_CHECK(Count(text, kProductIcon) == 2);
  PARC_CHECK(Count(text, "M9.45 14.574") == 0);
  PARC_CHECK(Count(text, "<g id=\"chevron-left\">") == 3);
  PARC_CHECK(Count(text, "<g id=\"close\">") == 3);
}

- (void)testMissingIconsPreserveTheOriginalResource {
  const ResourceEdits& rules = Rules("IDR_WEBUI_CR_ELEMENTS_ICONS_HTML_JS");
  std::string one = IconSet(24, 1);
  const auto outcome = ApplyResourceEdits(one, rules);
  PARC_CHECK(Has(outcome.failed, "product icon") && outcome.applied.empty());
  PARC_CHECK(one == IconSet(24, 1));
}

- (void)testUnexpectedExtraIconsPreserveTheOriginalResource {
  const ResourceEdits& rules = Rules("IDR_WEBUI_CR_ELEMENTS_ICONS_HTML_JS");
  std::string three = IconSet(24, 3);
  const auto outcome = ApplyResourceEdits(three, rules);
  PARC_CHECK(Has(outcome.failed, "product icon"));
  PARC_CHECK(three == IconSet(24, 3));
}

- (void)testUnclosedIconMarkupPreservesTheOriginalResource {
  const ResourceEdits& rules = Rules("IDR_WEBUI_CR_ELEMENTS_ICONS_HTML_JS");
  const std::string unclosed_copy =
      ChromiumIcon("") + "<g id=\"chrome-product\"><path d=\"M1 2Z\"></path>";
  std::string unclosed = unclosed_copy;
  const auto outcome = ApplyResourceEdits(unclosed, rules);
  PARC_CHECK(Has(outcome.failed, "product icon"));
  PARC_CHECK(unclosed == unclosed_copy);
}

- (void)testNestedIconGroupsPreserveTheOriginalResource {
  const ResourceEdits& rules = Rules("IDR_WEBUI_CR_ELEMENTS_ICONS_HTML_JS");
  const std::string nested_copy =
      ChromiumIcon("") +
      "<g id=\"chrome-product\"><g><path d=\"M1 2Z\"></path></g></g>";
  std::string nested = nested_copy;
  const auto outcome = ApplyResourceEdits(nested, rules);
  PARC_CHECK(Has(outcome.failed, "product icon"));
  PARC_CHECK(nested == nested_copy);
}

- (void)testTheSettingsBundleUsesTheProductIconAndAboutLogo {
  const ResourceEdits& rules = Rules("IDR_SETTINGS_SHARED_ROLLUP_JS");
  const std::string bundle = "const a=1;" + IconSet(24, 2) + "x" +
                             IconSet(20, 2) + std::string(kAboutTemplate) +
                             "<cr-icon icon=\"cr:chrome-product\"></cr-icon>";
  std::string text = bundle;
  EditOutcome outcome = ApplyResourceEdits(text, rules);
  PARC_CHECK(outcome.failed.empty());
  PARC_CHECK(Has(outcome.applied, "product icon") &&
              Has(outcome.applied, "About logo"));
  PARC_CHECK(Count(text, kProductIcon) == 4);
  PARC_CHECK(Count(text, "<picture style=\"display: contents\">") == 1);
  PARC_CHECK(Count(text, "srcset=\"//resources/images/chrome_logo_dark.svg\"><img "
                          "id=\"productLogo\" width=\"32\" height=\"32\" @click") == 1);
  PARC_CHECK(Count(text, "role=\"presentation\">\n    </picture><div "
                          "class=\"product-title\">") == 1);
  PARC_CHECK(Count(text, "<cr-icon icon=\"cr:chrome-product\"></cr-icon>") == 1);
}

- (void)testAMissingIconLeavesTheAboutLogoEligible {
  const ResourceEdits& rules = Rules("IDR_SETTINGS_SHARED_ROLLUP_JS");
  std::string missing_icon = "const a=1;" + IconSet(24, 2) + IconSet(20, 1) +
                             std::string(kAboutTemplate);
  const auto outcome = ApplyResourceEdits(missing_icon, rules);
  PARC_CHECK(Has(outcome.failed, "product icon"));
  PARC_CHECK(Has(outcome.applied, "About logo"));
  PARC_CHECK(Count(missing_icon, kProductIcon) == 0);
  PARC_CHECK(Count(missing_icon, "<picture style=\"display: contents\">") == 1);
}

- (void)testDuplicateAboutTemplatesLeaveIconsEligible {
  const ResourceEdits& rules = Rules("IDR_SETTINGS_SHARED_ROLLUP_JS");
  std::string twice = IconSet(24, 2) + IconSet(20, 2) +
                      std::string(kAboutTemplate) + std::string(kAboutTemplate);
  const auto outcome = ApplyResourceEdits(twice, rules);
  PARC_CHECK(Has(outcome.failed, "About logo"));
  PARC_CHECK(Has(outcome.applied, "product icon"));
  PARC_CHECK(Count(twice, "<picture") == 0);
}

- (void)testAnIncompleteAboutTemplateStaysIntact {
  const ResourceEdits& rules = Rules("IDR_SETTINGS_SHARED_ROLLUP_JS");
  std::string half = IconSet(24, 2) + IconSet(20, 2) +
                     "<img id=\"productLogo\" srcset=\"x\">";
  const auto outcome = ApplyResourceEdits(half, rules);
  PARC_CHECK(Has(outcome.failed, "About logo"));
  PARC_CHECK(Count(half, "<picture") == 0 && Count(half, "</picture>") == 0);
}

- (void)testTheVersionPageNamesParcAndLinksItsLicences {
  const ResourceEdits& version = Rules("IDR_VERSION_UI_ABOUT_VERSION_HTML");
  std::string html =
      "<img alt=\"$i18n{logo_alt_text}\" src=\"chrome://theme/IDR_PRODUCT_LOGO\">"
      "<div id=\"copyright\">$i18n{copyright}</div>"
      "<td class=\"label\">$i18n{application_label}</td>";
  EditOutcome outcome = ApplyResourceEdits(html, version);
  PARC_CHECK(outcome.failed.empty() && outcome.applied.size() == 3);
  PARC_CHECK(Count(html, "alt=\"Parc\"") == 1);
  PARC_CHECK(Count(html, "<a href=\"chrome://license/\">Parc licences</a>") == 1);
  PARC_CHECK(Count(html, "<td class=\"label\">Parc</td>") == 1);
}

- (void)testChangedLicenceMarkupLeavesTheProductNameEligible {
  const ResourceEdits& version = Rules("IDR_VERSION_UI_ABOUT_VERSION_HTML");
  std::string changed = "<img alt=\"$i18n{logo_alt_text}\">"
                        "<div id=\"copyright\" class=\"x\">$i18n{copyright}</div>"
                        "$i18n{application_label}";
  const auto outcome = ApplyResourceEdits(changed, version);
  PARC_CHECK(outcome.failed.size() == 1 && Has(outcome.failed, "licence links"));
  PARC_CHECK(Count(changed, "alt=\"Parc\"") == 1);
}

- (void)testTheRelaunchNoticeNamesParc {
  const ResourceEdits& trials = Rules("IDR_METRICS_INTERNALS_FIELD_TRIALS_HTML_JS");
  std::string script =
      "Your changes will take effect the next time you relaunch Chromium.";
  const auto outcome = ApplyResourceEdits(script, trials);
  PARC_CHECK(outcome.failed.empty());
  PARC_CHECK(script == "Your changes will take effect the next time you relaunch Parc.");
}

- (void)testARewordedRelaunchNoticeRemainsIntact {
  const ResourceEdits& trials = Rules("IDR_METRICS_INTERNALS_FIELD_TRIALS_HTML_JS");
  std::string reworded = "Relaunch Chromium to apply your changes.";
  const auto outcome = ApplyResourceEdits(reworded, trials);
  PARC_CHECK(Has(outcome.failed, "relaunch notice"));
  PARC_CHECK(reworded == "Relaunch Chromium to apply your changes.");
}

- (void)testOverlappingEditsLeaveTheResourceIntact {
  static constexpr Edit kFirst[] = {{"abc", {}, "1", 1}};
  static constexpr Edit kSecond[] = {{"bcd", {}, "2", 1}};
  static constexpr EditGroup kGroups[] = {{"first", kFirst}, {"second", kSecond}};
  static constexpr ResourceEdits kOverlap = {"TEST", kGroups};
  std::string text = "xabcdx";
  const EditOutcome outcome = ApplyResourceEdits(text, kOverlap);
  PARC_CHECK(outcome.applied.empty() && outcome.failed.size() == 2);
  PARC_CHECK(text == "xabcdx");
}

- (void)testUnknownResourcesHaveNoEdits {
  PARC_CHECK(FindResourceEdits("IDR_NOT_BRANDED") == nullptr);
}

- (void)testAnEmptyNeedleCannotMatch {
  PARC_CHECK(!FindEdit("abc", {"", {}, "x", 0}).has_value());
}

- (void)testDelimitedMatchesIncludeTheClosingTag {
  const auto spans = FindEdit("<g id=\"chrome-product\">x</g>", {"<g id=\"chrome-product\"", "</g>", "y", 1});
  PARC_CHECK(spans.has_value() && spans->size() == 1 && (*spans)[0].end == 28);
}

- (void)testTheAppMarkArtworkIsTheEnginesPath {
  NSURL* file = [SWIFTPM_MODULE_BUNDLE URLForResource:@"Monochrome" withExtension:@"svg"];
  NSXMLDocument* document = [[NSXMLDocument alloc] initWithData:[NSData dataWithContentsOfURL:file] options:0 error:nil];
  NSXMLElement* svg = document.rootElement;
  PARC_CHECK([svg.localName isEqual:@"svg"] && [[svg attributeForName:@"viewBox"].stringValue isEqual:@"0 0 24 24"]);
  PARC_CHECK([PathOf(svg) isEqual:Mark()]);
}

- (void)testTheDarkLogoIsAWhiteMarkInATwentyFourUnitBox {
  NSXMLElement* dark = Svg(kDarkLogoSvg);
  PARC_CHECK([[dark attributeForName:@"viewBox"].stringValue isEqual:@"0 0 24 24"] && [PathOf(dark) isEqual:Mark()]);
  NSXMLElement* path = (NSXMLElement*)[dark nodesForXPath:@".//*[local-name()='path']" error:nil].firstObject;
  PARC_CHECK([[path attributeForName:@"fill"].stringValue isEqual:@"#fff"]);
}

- (void)testTheAdaptiveLogoFollowsTheSystemAppearance {
  CheckAppearance(kAdaptiveLogoSvg, @"0 0 24 24");
  PARC_CHECK(Count(kAdaptiveLogoSvg, "path{fill:#000}") == 1);
  PARC_CHECK(Count(kAdaptiveLogoSvg,
                    "@media (prefers-color-scheme: dark){path{fill:#fff}}") == 1);
}

- (void)testThePaddedLogoKeepsTheAdaptiveAppearance {
  CheckAppearance(kPaddedLogoSvg, @"-12 -12 48 48");
  PARC_CHECK(kPaddedLogoSvg.substr(kPaddedLogoSvg.find("<style>")) ==
              kAdaptiveLogoSvg.substr(kAdaptiveLogoSvg.find("<style>")));
}

- (void)testTheProductIconTakesTheIconColour {
  NSXMLElement* icon = Svg(kProductIcon);
  PARC_CHECK([icon.name isEqual:@"g"] && [[icon attributeForName:@"id"].stringValue isEqual:@"chrome-product"] &&
             [[icon attributeForName:@"viewBox"].stringValue isEqual:@"0 0 24 24"] && [PathOf(icon) isEqual:Mark()]);
  NSXMLElement* path = (NSXMLElement*)[icon nodesForXPath:@".//path" error:nil].firstObject;
  PARC_CHECK([path attributeForName:@"fill"] == nil);
}

@end

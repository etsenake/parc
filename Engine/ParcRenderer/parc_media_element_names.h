// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/core/html/media/parc_media_element_names.h.
// WebKit's AirPlay attribute and event names, which Safari-identity media
// elements answer to. Made on first use in place of entries in
// html_attribute_names.json5 and event_type_names.json5, which would
// regenerate html_names.h and event_type_names.h. Main thread.
#ifndef THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_MEDIA_ELEMENT_NAMES_H_
#define THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_MEDIA_ELEMENT_NAMES_H_

#include "third_party/blink/renderer/core/dom/qualified_name.h"
#include "third_party/blink/renderer/platform/wtf/std_lib_extras.h"
#include "third_party/blink/renderer/platform/wtf/text/atomic_string.h"

namespace blink::parc_media_element_names {

inline const QualifiedName& XWebkitAirplayAttr() {
  DEFINE_STATIC_LOCAL(const QualifiedName, name,
                      (AtomicString("x-webkit-airplay")));
  return name;
}

inline const QualifiedName& WebkitwirelessvideoplaybackdisabledAttr() {
  DEFINE_STATIC_LOCAL(const QualifiedName, name,
                      (AtomicString("webkitwirelessvideoplaybackdisabled")));
  return name;
}

inline const AtomicString& Webkitplaybacktargetavailabilitychanged() {
  DEFINE_STATIC_LOCAL(const AtomicString, name,
                      ("webkitplaybacktargetavailabilitychanged"));
  return name;
}

inline const AtomicString& Webkitcurrentplaybacktargetiswirelesschanged() {
  DEFINE_STATIC_LOCAL(const AtomicString, name,
                      ("webkitcurrentplaybacktargetiswirelesschanged"));
  return name;
}

}  // namespace blink::parc_media_element_names

#endif  // THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_MEDIA_ELEMENT_NAMES_H_

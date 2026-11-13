// Copyright 2026 Parc contributors.
#ifndef THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_PICTURE_IN_PICTURE_CAPTIONS_H_
#define THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_PICTURE_IN_PICTURE_CAPTIONS_H_

#include "third_party/blink/renderer/core/core_export.h"

namespace blink {

class Element;
class Node;

CORE_EXPORT bool IsParcPictureInPictureCaptions(const Element& element);
CORE_EXPORT bool IsParcPictureInPictureCaptions(const Node* node);

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_PICTURE_IN_PICTURE_CAPTIONS_H_

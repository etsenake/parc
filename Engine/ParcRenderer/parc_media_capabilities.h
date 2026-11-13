// Copyright 2026 Parc contributors.
#ifndef THIRD_PARTY_BLINK_RENDERER_MODULES_MEDIA_CAPABILITIES_PARC_MEDIA_CAPABILITIES_H_
#define THIRD_PARTY_BLINK_RENDERER_MODULES_MEDIA_CAPABILITIES_PARC_MEDIA_CAPABILITIES_H_

#include <stdint.h>

#include <optional>
#include <string_view>

#include "media/mojo/mojom/parc_video_toolbox_decoding.mojom-blink.h"
#include "third_party/blink/renderer/bindings/core/v8/script_promise.h"
#include "third_party/blink/renderer/core/execution_context/navigator_base.h"
#include "third_party/blink/renderer/platform/heap/garbage_collected.h"
#include "third_party/blink/renderer/platform/mojo/heap_mojo_remote.h"
#include "third_party/blink/renderer/platform/supplementable.h"
#include "third_party/blink/renderer/platform/wtf/vector.h"

namespace blink {

class ExceptionState;
class ExecutionContext;
class MediaCapabilitiesDecodingInfo;
class MediaDecodingConfiguration;
class MediaKeySystemAccess;
class ScriptState;
template <typename IDLResolvedType>
class ScriptPromiseResolver;
class String;
class VideoConfiguration;

struct ParcDecodingAnswer {
  bool supported = false;
  bool smooth = false;
  bool power_efficient = false;
};

struct ParcHevcParameters {
  uint8_t profile_space = 0;
  uint8_t profile_idc = 0;
  uint32_t compatibility_flags = 0;
  uint8_t level_idc = 0;
};

std::optional<ParcHevcParameters> ParcParseHevc(std::string_view codec);

struct ParcDoViParameters {
  uint8_t profile = 0;
  uint8_t level = 0;
};

std::optional<ParcDoViParameters> ParcParseDoVi(std::string_view codec);

MediaCapabilitiesDecodingInfo* ParcFinishDecodingInfo(
    MediaCapabilitiesDecodingInfo* info,
    ExecutionContext* context,
    const MediaDecodingConfiguration* config,
    MediaKeySystemAccess* access);

bool ParcSafariVideoAnswer(
    const MediaDecodingConfiguration* config,
    const VideoConfiguration* video,
    const String& codecs,
    const media::mojom::blink::ParcVideoToolboxDecodingFacts* facts,
    ParcDecodingAnswer& answer);

bool IsParcSafariFairPlayVideoCodec(const String& codec);

class ParcSafariMediaCapabilities final
    : public GarbageCollected<ParcSafariMediaCapabilities>,
      public Supplement<NavigatorBase> {
 public:
  static const char kSupplementName[];

  static ParcSafariMediaCapabilities& From(NavigatorBase& navigator);

  explicit ParcSafariMediaCapabilities(NavigatorBase& navigator);

  ScriptPromise<MediaCapabilitiesDecodingInfo> DecodingInfo(
      ScriptState* script_state,
      const MediaDecodingConfiguration* config,
      ExceptionState& exception_state);

  void Trace(Visitor* visitor) const override;

 private:
  void OnFacts(ScriptPromiseResolver<MediaCapabilitiesDecodingInfo>* resolver,
               const MediaDecodingConfiguration* config,
               media::mojom::blink::ParcVideoToolboxDecodingFactsPtr facts);
  void OnSpatialAudioSources(
      ScriptPromiseResolver<MediaCapabilitiesDecodingInfo>* resolver,
      const MediaDecodingConfiguration* config,
      bool smooth,
      bool power_efficient,
      const Vector<uint32_t>& sources);
  void Bind(ExecutionContext* execution_context);

  HeapMojoRemote<media::mojom::blink::ParcVideoToolboxDecoding> video_toolbox_;
  media::mojom::blink::ParcVideoToolboxDecodingFactsPtr facts_;
};

}

#endif

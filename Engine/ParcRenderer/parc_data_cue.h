// Copyright 2026 Parc contributors.
// WebKit's DataCue on Safari-identity documents (data_cue.idl): M156 Blink has
// none. The native HLS route's metadata track makes them from AVFoundation's
// timed metadata (ParcInbandTextTrack::AddDataCues), with the item kept as a
// platform value whose "value" is a new object on every read, as WebKit's
// SerializedPlatformDataCueCocoa::deserialize gives; pages construct them
// with a value or an ArrayBuffer. Installed by the overlay at
// third_party/blink/renderer/core/html/track/data_cue.h.
#ifndef THIRD_PARTY_BLINK_RENDERER_CORE_HTML_TRACK_DATA_CUE_H_
#define THIRD_PARTY_BLINK_RENDERER_CORE_HTML_TRACK_DATA_CUE_H_

#include <cstdint>
#include <optional>
#include <vector>

#include "media/base/parc_inband_tracks.h"
#include "third_party/blink/renderer/bindings/core/v8/script_value.h"
#include "third_party/blink/renderer/core/core_export.h"
#include "third_party/blink/renderer/core/html/track/text_track_cue.h"
#include "third_party/blink/renderer/platform/bindings/trace_wrapper_v8_reference.h"
#include "third_party/blink/renderer/platform/heap/member.h"
#include "third_party/blink/renderer/platform/wtf/text/wtf_string.h"

namespace blink {

class DOMArrayBuffer;
class ExceptionState;
class ExecutionContext;
class ScriptState;

class CORE_EXPORT DataCue final : public TextTrackCue {
  DEFINE_WRAPPERTYPEINFO();

 public:
  // new DataCue(startTime, endTime, value[, type]). Without a type, an
  // ArrayBuffer value is WebKit's ArrayBuffer constructor: a data cue of a
  // copy of its bytes and type "".
  static DataCue* Create(ScriptState* script_state,
                         double start_time,
                         double end_time,
                         const ScriptValue& value,
                         ExceptionState& exception_state);
  static DataCue* Create(ScriptState* script_state,
                         double start_time,
                         double end_time,
                         const ScriptValue& value,
                         const String& type,
                         ExceptionState& exception_state);
  // A timed metadata item of the native HLS player (DataCue::create with a
  // SerializedPlatformDataCue).
  static DataCue* CreateFromPlatformValue(ExecutionContext* context,
                                          double start_time,
                                          double end_time,
                                          const media::ParcDataCueValue& value,
                                          const String& type);

  DataCue(ExecutionContext* context,
          double start_time,
          double end_time,
          const String& type);
  ~DataCue() override;

  // DataCue.value: the platform value as a new object, else the value set,
  // else null.
  ScriptValue value(ScriptState* script_state) const;
  void setValue(ScriptState* script_state, const ScriptValue& value);
  const String& type() const { return type_; }
  // DataCue.data: null for a platform cue (WebKit's Cocoa platform value has
  // no data), else a copy of the bytes set, or null.
  DOMArrayBuffer* data() const;
  void setData(DOMArrayBuffer* data, ExceptionState& exception_state);

  const std::optional<media::ParcDataCueValue>& PlatformValue() const {
    return platform_value_;
  }
  // DataCue::cueContentsMatch: the same bytes, the same platform value and
  // the same (strictly equal) value.
  bool ContentsMatch(const DataCue& other) const;

  // TextTrackCue: a DataCue draws nothing.
  void UpdateDisplay(HTMLDivElement&) override {}
  void UpdatePastAndFutureNodes(double) override {}
  std::optional<double> GetNextIntraCueTime(double) const override {
    return std::nullopt;
  }
  void RemoveDisplayTree(RemovalNotification) override {}
  const AtomicString& InterfaceName() const override;
  ExecutionContext* GetExecutionContext() const override;
#ifndef NDEBUG
  String ToString() const override;
#endif

  void Trace(Visitor* visitor) const override;

 private:
  void SetBytes(DOMArrayBuffer* data);

  Member<ExecutionContext> context_;
  String type_;
  TraceWrapperV8Reference<v8::Value> value_;
  std::optional<std::vector<uint8_t>> data_;
  std::optional<media::ParcDataCueValue> platform_value_;
};

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_CORE_HTML_TRACK_DATA_CUE_H_

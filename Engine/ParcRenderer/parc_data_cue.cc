// Copyright 2026 Parc contributors.
// WebKit's DataCue (Source/WebCore/html/track/DataCue.cpp) on
// Safari-identity documents. Installed by the overlay at
// third_party/blink/renderer/core/html/track/data_cue.cc.

#include "third_party/blink/renderer/core/html/track/data_cue.h"

#include "third_party/blink/renderer/bindings/core/v8/native_value_traits_impl.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_object_builder.h"
#include "third_party/blink/renderer/core/execution_context/execution_context.h"
#include "third_party/blink/renderer/core/typed_arrays/dom_array_buffer.h"
#include "third_party/blink/renderer/platform/bindings/exception_state.h"
#include "third_party/blink/renderer/platform/bindings/script_state.h"
#include "third_party/blink/renderer/platform/heap/garbage_collected.h"
#include "third_party/blink/renderer/platform/wtf/text/string_builder.h"

namespace blink {

namespace {

String FromUtf8(const std::string& value) {
  return String::FromUtf8(value);
}

// SerializedPlatformDataCueCocoa::deserialize: the item's dictionary
// (SerializedPlatformDataCueValue::toNSDictionary) as a new object. A date
// value has no JS form there, so it gives no "data".
ScriptValue PlatformValueToScript(ScriptState* script_state,
                                  const media::ParcDataCueValue& value) {
  V8ObjectBuilder builder(script_state);
  if (value.type) {
    builder.AddString("type", FromUtf8(*value.type));
  }
  for (const auto& [name, attribute] : value.attributes) {
    builder.AddString(FromUtf8(name), FromUtf8(attribute));
  }
  if (value.locale) {
    builder.AddString("locale", FromUtf8(*value.locale));
  }
  if (value.key) {
    builder.AddString("key", FromUtf8(*value.key));
  }
  switch (value.kind) {
    case media::ParcDataCueValue::Kind::kString:
      builder.AddString("data", FromUtf8(value.string_value));
      break;
    case media::ParcDataCueValue::Kind::kNumber:
      builder.AddNumber("data", value.number_value);
      break;
    case media::ParcDataCueValue::Kind::kBoolean:
      builder.AddBoolean("data", value.number_value != 0);
      break;
    case media::ParcDataCueValue::Kind::kData:
      builder.Add("data", DOMArrayBuffer::Create(base::span(value.data)));
      break;
    case media::ParcDataCueValue::Kind::kDate:
    case media::ParcDataCueValue::Kind::kNone:
      break;
  }
  return builder.ToScriptObject();
}

}  // namespace

// static
DataCue* DataCue::Create(ScriptState* script_state,
                         double start_time,
                         double end_time,
                         const ScriptValue& value,
                         ExceptionState& exception_state) {
  v8::Local<v8::Value> v8_value = value.V8Value();
  if (!v8_value.IsEmpty() && v8_value->IsArrayBuffer()) {
    // WebKit's (startTime, endTime, ArrayBuffer data) constructor.
    DOMArrayBuffer* buffer = NativeValueTraits<DOMArrayBuffer>::NativeValue(
        script_state->GetIsolate(), v8_value, exception_state);
    if (exception_state.HadException()) {
      return nullptr;
    }
    auto* cue = MakeGarbageCollected<DataCue>(
        ExecutionContext::From(script_state), start_time, end_time,
        g_empty_string);
    cue->SetBytes(buffer);
    return cue;
  }
  return Create(script_state, start_time, end_time, value, g_empty_string,
                exception_state);
}

// static
DataCue* DataCue::Create(ScriptState* script_state,
                         double start_time,
                         double end_time,
                         const ScriptValue& value,
                         const String& type,
                         ExceptionState&) {
  auto* cue = MakeGarbageCollected<DataCue>(
      ExecutionContext::From(script_state), start_time, end_time, type);
  if (!value.IsEmpty()) {
    cue->value_.Reset(script_state->GetIsolate(), value.V8Value());
  }
  return cue;
}

// static
DataCue* DataCue::CreateFromPlatformValue(ExecutionContext* context,
                                          double start_time,
                                          double end_time,
                                          const media::ParcDataCueValue& value,
                                          const String& type) {
  auto* cue =
      MakeGarbageCollected<DataCue>(context, start_time, end_time, type);
  cue->platform_value_ = value;
  return cue;
}

DataCue::DataCue(ExecutionContext* context,
                 double start_time,
                 double end_time,
                 const String& type)
    : TextTrackCue(start_time, end_time), context_(context), type_(type) {}

DataCue::~DataCue() = default;

ScriptValue DataCue::value(ScriptState* script_state) const {
  v8::Isolate* isolate = script_state->GetIsolate();
  if (platform_value_) {
    return PlatformValueToScript(script_state, *platform_value_);
  }
  if (!value_.IsEmpty()) {
    return ScriptValue(isolate, value_.Get(isolate));
  }
  return ScriptValue::CreateNull(isolate);
}

void DataCue::setValue(ScriptState* script_state, const ScriptValue& value) {
  // WebKit keeps the value itself (no structured clone).
  if (value.IsEmpty()) {
    value_.Reset();
  } else {
    value_.Reset(script_state->GetIsolate(), value.V8Value());
  }
  platform_value_.reset();
  data_.reset();
}

DOMArrayBuffer* DataCue::data() const {
  if (platform_value_ || !data_) {
    return nullptr;
  }
  return DOMArrayBuffer::Create(base::span(*data_));
}

void DataCue::setData(DOMArrayBuffer* data, ExceptionState& exception_state) {
  if (!data) {
    exception_state.ThrowTypeError(
        "The DataCue.data attribute must be an instance of ArrayBuffer");
    return;
  }
  platform_value_.reset();
  value_.Reset();
  SetBytes(data);
}

void DataCue::SetBytes(DOMArrayBuffer* data) {
  base::span<const uint8_t> bytes = data->ByteSpan();
  data_.emplace(bytes.begin(), bytes.end());
}

bool DataCue::ContentsMatch(const DataCue& other) const {
  // DataCue::cueContentsMatch.
  if (other.data_.has_value() != data_.has_value() ||
      (data_ && *data_ != *other.data_)) {
    return false;
  }
  if (other.platform_value_.has_value() != platform_value_.has_value() ||
      (platform_value_ && !(*platform_value_ == *other.platform_value_))) {
    return false;
  }
  // valueOrNull(): no value is null, and null strictly equals null.
  if (value_.IsEmpty() || other.value_.IsEmpty()) {
    return value_.IsEmpty() == other.value_.IsEmpty();
  }
  v8::Isolate* isolate = context_ ? context_->GetIsolate() : nullptr;
  if (!isolate) {
    return false;
  }
  v8::HandleScope handle_scope(isolate);
  return value_.Get(isolate)->StrictEquals(other.value_.Get(isolate));
}

const AtomicString& DataCue::InterfaceName() const {
  DEFINE_STATIC_LOCAL(const AtomicString, name, ("DataCue"));
  return name;
}

ExecutionContext* DataCue::GetExecutionContext() const {
  return context_.Get();
}

#ifndef NDEBUG
String DataCue::ToString() const {
  StringBuilder builder;
  builder.Append("DataCue ");
  builder.AppendNumber(startTime());
  builder.Append(" - ");
  builder.AppendNumber(endTime());
  builder.Append(" type=");
  builder.Append(type_);
  return builder.ToString();
}
#endif

void DataCue::Trace(Visitor* visitor) const {
  visitor->Trace(context_);
  visitor->Trace(value_);
  TextTrackCue::Trace(visitor);
}

}  // namespace blink

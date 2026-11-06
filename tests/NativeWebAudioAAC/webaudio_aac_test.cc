// Drives blink::PlatformAudioFileDecoder, the renderer half of WebAudio's
// decodeAudioData() for AAC, through the patched media::AudioFileReader and
// AudioToolboxAudioDecoder. Each file decodes once with the decoder in-process
// and once behind a real MojoAudioDecoder and MojoAudioDecoderService on
// another thread, as the GPU process hosts it, and is compared with macOS's
// own ExtAudioFile decode. The Mojo side then disconnects, stops answering or
// is never reached, and the decode is cancelled, which must all fail cleanly.
// Usage: webaudio_aac_test <fixture directory written by run.py>

#include <AudioToolbox/AudioToolbox.h>

#include <algorithm>
#include <atomic>
#include <bit>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <memory>
#include <optional>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

#include "base/at_exit.h"
#include "base/command_line.h"
#include "base/containers/span.h"
#include "base/feature_list.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/location.h"
#include "base/memory/scoped_refptr.h"
#include "base/run_loop.h"
#include "base/task/sequenced_task_runner.h"
#include "base/task/single_thread_task_executor.h"
#include "base/task/single_thread_task_runner.h"
#include "base/task/thread_pool/thread_pool_instance.h"
#include "base/threading/thread.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "media/base/audio_buffer.h"
#include "media/base/audio_bus.h"
#include "media/base/audio_decoder.h"
#include "media/base/audio_decoder_config.h"
#include "media/base/decoder_buffer.h"
#include "media/base/decoder_status.h"
#include "media/base/media_log.h"
#include "media/base/media_util.h"
#include "media/filters/audio_file_reader.h"
#include "media/filters/in_memory_url_protocol.h"
#include "media/filters/mac/audio_toolbox_audio_decoder.h"
#include "media/mojo/clients/mojo_audio_decoder.h"
#include "media/mojo/common/media_type_converters.h"
#include "media/mojo/mojom/audio_decoder.mojom.h"
#include "media/mojo/services/mojo_audio_decoder_service.h"
#include "media/mojo/services/mojo_media_client.h"
#include "mojo/core/embedder/embedder.h"
#include "mojo/public/cpp/bindings/associated_receiver.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/pending_remote.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "mojo/public/cpp/bindings/self_owned_receiver.h"
#include "mojo/public/cpp/system/data_pipe.h"
#include "third_party/blink/renderer/modules/webaudio/platform_audio_file_decoder.h"

namespace {

using blink::PlatformAudioFileDecoder;

int g_failures = 0;

void Expect(bool condition, const std::string& name, const std::string& what) {
  std::printf("%s %s: %s\n", condition ? "PASS" : "FAIL", name.c_str(),
              what.c_str());
  if (!condition) {
    ++g_failures;
  }
}

std::vector<uint8_t> ReadFile(const std::string& path) {
  std::ifstream file(path, std::ios::binary);
  return std::vector<uint8_t>((std::istreambuf_iterator<char>(file)), {});
}

struct Pcm {
  int sample_rate = 0;
  std::vector<std::vector<float>> channels;
  size_t frames() const { return channels.empty() ? 0 : channels[0].size(); }
  float peak() const {
    float peak = 0;
    for (const auto& channel : channels) {
      for (float sample : channel) {
        peak = std::max(peak, std::fabs(sample));
      }
    }
    return peak;
  }
};

// macOS's decode, trimmed by its own reading of the file's priming and
// padding, at the file's rate and channel count.
Pcm Reference(const std::string& path) {
  Pcm pcm;
  CFURLRef url = CFURLCreateFromFileSystemRepresentation(
      nullptr, reinterpret_cast<const UInt8*>(path.c_str()), path.size(),
      false);
  ExtAudioFileRef file = nullptr;
  const OSStatus opened = ExtAudioFileOpenURL(url, &file);
  CFRelease(url);
  if (opened != noErr) {
    return pcm;
  }
  AudioStreamBasicDescription format = {};
  UInt32 size = sizeof(format);
  ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileDataFormat, &size,
                          &format);
  AudioStreamBasicDescription client = {};
  client.mFormatID = kAudioFormatLinearPCM;
  client.mFormatFlags =
      kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved;
  client.mSampleRate = format.mSampleRate;
  client.mChannelsPerFrame = format.mChannelsPerFrame;
  client.mBitsPerChannel = 32;
  client.mBytesPerFrame = client.mBytesPerPacket = sizeof(float);
  client.mFramesPerPacket = 1;
  ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat,
                          sizeof(client), &client);
  constexpr UInt32 kChunk = 4096;
  std::vector<std::vector<float>> chunk(client.mChannelsPerFrame,
                                        std::vector<float>(kChunk));
  std::vector<uint8_t> storage(sizeof(AudioBufferList) +
                               client.mChannelsPerFrame * sizeof(AudioBuffer));
  auto* list = reinterpret_cast<AudioBufferList*>(storage.data());
  pcm.sample_rate = static_cast<int>(format.mSampleRate);
  pcm.channels.resize(client.mChannelsPerFrame);
  while (true) {
    list->mNumberBuffers = client.mChannelsPerFrame;
    auto buffers = base::span(list->mBuffers, list->mNumberBuffers);
    for (UInt32 c = 0; c < client.mChannelsPerFrame; ++c) {
      buffers[c] = {1, kChunk * sizeof(float), chunk[c].data()};
    }
    UInt32 frames = kChunk;
    if (ExtAudioFileRead(file, &frames, list) != noErr || !frames) {
      break;
    }
    for (UInt32 c = 0; c < client.mChannelsPerFrame; ++c) {
      pcm.channels[c].insert(pcm.channels[c].end(), chunk[c].begin(),
                             chunk[c].begin() + frames);
    }
  }
  ExtAudioFileDispose(file);
  return pcm;
}

Pcm ToPcm(const PlatformAudioFileDecoder::Output& output) {
  Pcm pcm;
  pcm.sample_rate = output.sample_rate;
  pcm.channels.resize(output.channels);
  for (const auto& packet : output.packets) {
    for (int c = 0; c < output.channels; ++c) {
      auto samples = packet->channel(c);
      pcm.channels[c].insert(pcm.channels[c].end(), samples.begin(),
                             samples.end());
    }
  }
  return pcm;
}

// How the GPU process's decoder misbehaves.
struct GpuOptions {
  // Closes the pipe, as a GPU process crash does, at this Decode() call.
  std::optional<int> close_at_decode;
  // Swallows this Decode() call and every later one, as a hung GPU process.
  std::optional<int> hang_at_decode;
  // Leaves Initialize() for the test to answer through `held_init`.
  bool hold_init = false;
  // Leaves every Decode() undecoded for the test to answer.
  bool hold_decodes = false;
};

// The GPU process's side: AudioToolboxAudioDecoder behind the real
// MojoAudioDecoderService on its own thread. Only `decodes` is read off it.
struct GpuControl {
  GpuOptions options;
  std::atomic<int> decodes{0};
  mojo::SelfOwnedReceiverRef<media::mojom::AudioDecoder> receiver;
  media::AudioDecoder::InitCB held_init;
  std::vector<media::AudioDecoder::DecodeCB> held_decodes;
};

class ControlledDecoder final : public media::AudioDecoder {
 public:
  ControlledDecoder(std::unique_ptr<media::AudioDecoder> decoder,
                    GpuControl* control)
      : decoder_(std::move(decoder)), control_(control) {}

  media::AudioDecoderType GetDecoderType() const override {
    return decoder_->GetDecoderType();
  }
  void Initialize(const media::AudioDecoderConfig& config,
                  media::CdmContext* cdm_context,
                  InitCB init_cb,
                  const OutputCB& output_cb,
                  const media::WaitingCB& waiting_cb) override {
    if (control_->options.hold_init) {
      control_->held_init = std::move(init_cb);
      return;
    }
    decoder_->Initialize(config, cdm_context, std::move(init_cb), output_cb,
                         waiting_cb);
  }
  void Decode(scoped_refptr<media::DecoderBuffer> buffer,
              DecodeCB decode_cb) override {
    const int index = ++control_->decodes;
    const GpuOptions& options = control_->options;
    if (options.hold_decodes) {
      control_->held_decodes.push_back(std::move(decode_cb));
      return;
    }
    if (options.close_at_decode && index >= *options.close_at_decode) {
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE,
          base::BindOnce(
              [](GpuControl* control) { control->receiver->Close(); },
              control_));
      held_.push_back(std::move(decode_cb));
      return;
    }
    if (options.hang_at_decode && index >= *options.hang_at_decode) {
      held_.push_back(std::move(decode_cb));
      return;
    }
    decoder_->Decode(std::move(buffer), std::move(decode_cb));
  }
  void Reset(base::OnceClosure closure) override {
    decoder_->Reset(std::move(closure));
  }

 private:
  std::unique_ptr<media::AudioDecoder> decoder_;
  GpuControl* control_;
  std::vector<DecodeCB> held_;
};

class GpuMediaClient final : public media::MojoMediaClient {
 public:
  explicit GpuMediaClient(GpuControl* control) : control_(control) {}
  std::unique_ptr<media::AudioDecoder> CreateAudioDecoder(
      scoped_refptr<base::SequencedTaskRunner> task_runner,
      std::unique_ptr<media::MediaLog> media_log) override {
    return std::make_unique<ControlledDecoder>(
        std::make_unique<media::AudioToolboxAudioDecoder>(std::move(media_log)),
        control_);
  }

 private:
  GpuControl* control_;
};

class GpuProcess {
 public:
  GpuProcess() : thread_("gpu") { thread_.Start(); }
  ~GpuProcess() {
    thread_.task_runner()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](std::vector<std::unique_ptr<GpuState>> states) {
                         for (auto& state : states) {
                           if (state->control.receiver) {
                             state->control.receiver->Close();
                           }
                         }
                       },
                       std::move(states_)));
    thread_.Stop();
  }

  // Runs `task` on the GPU thread and waits for it.
  void RunOnGpu(base::OnceClosure task) {
    base::RunLoop loop;
    thread_.task_runner()->PostTaskAndReply(FROM_HERE, std::move(task),
                                            loop.QuitClosure());
    loop.Run();
  }

  // As InterfaceFactory::CreateAudioDecoder() binds the service.
  mojo::PendingRemote<media::mojom::AudioDecoder> CreateDecoder(
      GpuControl** control_out,
      GpuOptions options = {}) {
    auto state = std::make_unique<GpuState>();
    state->control.options = options;
    *control_out = &state->control;
    mojo::PendingRemote<media::mojom::AudioDecoder> remote;
    thread_.task_runner()->PostTask(
        FROM_HERE,
        base::BindOnce(
            [](GpuState* state,
               scoped_refptr<base::SingleThreadTaskRunner> task_runner,
               mojo::PendingReceiver<media::mojom::AudioDecoder> receiver) {
              state->control.receiver = mojo::MakeSelfOwnedReceiver(
                  std::make_unique<media::MojoAudioDecoderService>(
                      &state->client, nullptr, task_runner),
                  std::move(receiver));
            },
            state.get(), thread_.task_runner(),
            remote.InitWithNewPipeAndPassReceiver()));
    states_.push_back(std::move(state));
    return remote;
  }

 private:
  struct GpuState {
    GpuState() : client(&control) {}
    GpuControl control;
    GpuMediaClient client;
  };
  base::Thread thread_;
  std::vector<std::unique_ptr<GpuState>> states_;
};

struct Result {
  bool done = false;
  bool timed_out = false;
  base::TimeDelta elapsed;
  bool decoder_created = false;
  std::optional<PlatformAudioFileDecoder::Output> output;
};

// As base_audio_context.cc sends to the GPU process.
constexpr int kMojoDecodes = 8;

// `deadline` only ends the wait; a decode still running then counts as hung.
Result Run(std::vector<uint8_t> data,
           PlatformAudioFileDecoder::CreateDecoderCB create_decoder,
           int decodes_in_flight,
           base::RepeatingCallback<bool()> is_cancelled =
               base::BindRepeating([] { return false; }),
           base::TimeDelta timeout = base::Seconds(30),
           base::TimeDelta deadline = base::Seconds(60)) {
  // Shared with the callbacks, which outlive this call if the decode hangs.
  auto result = std::make_shared<Result>();
  auto input = std::make_shared<std::vector<uint8_t>>(std::move(data));
  base::RunLoop loop;
  const base::TimeTicks start = base::TimeTicks::Now();
  auto task_runner = base::SingleThreadTaskRunner::GetCurrentDefault();
  PlatformAudioFileDecoder::Decode(
      *input, task_runner,
      base::BindOnce(
          [](std::shared_ptr<Result> result,
             PlatformAudioFileDecoder::CreateDecoderCB create,
             scoped_refptr<base::SequencedTaskRunner> task_runner,
             media::MediaLog* media_log) {
            result->decoder_created = true;
            return std::move(create).Run(std::move(task_runner), media_log);
          },
          result, std::move(create_decoder)),
      std::move(is_cancelled), decodes_in_flight, timeout,
      base::BindOnce(
          [](std::shared_ptr<Result> result,
             std::shared_ptr<std::vector<uint8_t>> input, base::TimeTicks start,
             base::OnceClosure quit,
             std::optional<PlatformAudioFileDecoder::Output> output) {
            if (result->done) {
              std::printf("FAIL done ran twice\n");
              ++g_failures;
            }
            result->done = true;
            result->elapsed = base::TimeTicks::Now() - start;
            result->output = std::move(output);
            std::move(quit).Run();
          },
          result, input, start, loop.QuitClosure()));
  base::OneShotTimer watchdog;
  watchdog.Start(FROM_HERE, deadline,
                 base::BindOnce(
                     [](std::shared_ptr<Result> result, base::OnceClosure quit) {
                       result->timed_out = true;
                       std::move(quit).Run();
                     },
                     result, loop.QuitClosure()));
  loop.Run();
  if (result->timed_out) {
    std::printf("FAIL decode still running after %lld s\n",
                deadline.InSeconds());
    ++g_failures;
  }
  return std::move(*result);
}

PlatformAudioFileDecoder::CreateDecoderCB InProcess() {
  return base::BindOnce([](scoped_refptr<base::SequencedTaskRunner>,
                           media::MediaLog*)
                            -> std::unique_ptr<media::AudioDecoder> {
    return std::make_unique<media::AudioToolboxAudioDecoder>(
        std::make_unique<media::NullMediaLog>());
  });
}

PlatformAudioFileDecoder::CreateDecoderCB OverMojo(GpuProcess* gpu,
                                                   GpuControl** control = nullptr,
                                                   GpuOptions options = {}) {
  return base::BindOnce(
      [](GpuProcess* gpu, GpuControl** control, GpuOptions options,
         scoped_refptr<base::SequencedTaskRunner> task_runner,
         media::MediaLog* media_log) -> std::unique_ptr<media::AudioDecoder> {
        GpuControl* unused = nullptr;
        return std::make_unique<media::MojoAudioDecoder>(
            std::move(task_runner), media_log,
            gpu->CreateDecoder(control ? control : &unused, options));
      },
      gpu, control, options);
}

// Waits until `done` holds or `limit` passes; returns whether it held.
bool RunUntil(base::RepeatingCallback<bool()> done,
              base::TimeDelta limit = base::Seconds(10)) {
  const base::TimeTicks end = base::TimeTicks::Now() + limit;
  while (!done.Run() && base::TimeTicks::Now() < end) {
    base::RunLoop loop;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostDelayedTask(
        FROM_HERE, loop.QuitClosure(), base::Milliseconds(10));
    loop.Run();
  }
  return done.Run();
}

// Drives MojoAudioDecoderService over its raw interface, with the test
// writing the data pipe, to reach orders MojoAudioDecoder doesn't produce.
class RawDecoder final : public media::mojom::AudioDecoderClient {
 public:
  RawDecoder(GpuProcess* gpu, GpuControl** control, GpuOptions options)
      : remote_(gpu->CreateDecoder(control, options)) {
    mojo::PendingRemote<media::mojom::MediaLog> media_log;
    std::ignore = media_log.InitWithNewPipeAndPassReceiver();
    remote_->Construct(client_.BindNewEndpointAndPassRemote(),
                       std::move(media_log));
    mojo::ScopedDataPipeConsumerHandle consumer;
    mojo::CreateDataPipe(64 * 1024, producer_, consumer);
    remote_->SetDataSource(std::move(consumer));
  }

  void Initialize(const media::AudioDecoderConfig& config) {
    remote_->Initialize(
        config, std::nullopt,
        base::BindOnce(
            [](std::optional<media::DecoderStatus>* out,
               const media::DecoderStatus& status, bool, media::AudioDecoderType) {
              *out = status;
            },
            &init_status_));
  }
  // Sends the decode now; its bytes go into the pipe only with Write().
  void Decode(scoped_refptr<media::DecoderBuffer> buffer) {
    const int index = sent_++;
    remote_->Decode(media::mojom::DecoderBuffer::From(*buffer),
                    base::BindOnce(
                        [](std::vector<std::string>* answers, int index,
                           const media::DecoderStatus& status) {
                          answers->push_back(
                              std::to_string(index) + ":" +
                              (status.is_ok() ? std::string("ok")
                                              : std::to_string(static_cast<int>(
                                                    status.code()))));
                        },
                        &answers_, index));
  }
  void Write(const media::DecoderBuffer& buffer) {
    producer_->WriteAllData(base::span(buffer));
  }
  void ClosePipe() { producer_.reset(); }
  void Flush() { remote_.FlushForTesting(); }

  const std::optional<media::DecoderStatus>& init_status() const {
    return init_status_;
  }
  const std::vector<std::string>& answers() const { return answers_; }
  std::string AnswerText() const {
    std::string text;
    for (const auto& answer : answers_) {
      text += (text.empty() ? "" : " ") + answer;
    }
    return text;
  }

  // media::mojom::AudioDecoderClient implementation.
  void OnBufferDecoded(media::mojom::AudioBufferPtr buffer) override {}
  void OnWaiting(media::WaitingReason reason) override {}

 private:
  mojo::Remote<media::mojom::AudioDecoder> remote_;
  mojo::AssociatedReceiver<media::mojom::AudioDecoderClient> client_{this};
  mojo::ScopedDataPipeProducerHandle producer_;
  std::optional<media::DecoderStatus> init_status_;
  std::vector<std::string> answers_;
  int sent_ = 0;
};

std::string Frames(size_t ours, size_t reference) {
  return std::to_string(ours) + " frames, macOS " + std::to_string(reference);
}

// Largest sample difference over the frames both have, from frame 0.
float MaxDifference(const Pcm& a, const Pcm& b) {
  float difference = 0;
  for (size_t c = 0; c < std::min(a.channels.size(), b.channels.size()); ++c) {
    for (size_t i = 0; i < std::min(a.frames(), b.frames()); ++i) {
      difference =
          std::max(difference, std::fabs(a.channels[c][i] - b.channels[c][i]));
    }
  }
  return difference;
}

// FNV-1a over the samples' bits, to compare long decodes without keeping both.
uint64_t Digest(const PlatformAudioFileDecoder::Output& output) {
  uint64_t hash = 14695981039346656037ull;
  for (const auto& packet : output.packets) {
    for (int c = 0; c < packet->channels(); ++c) {
      for (float sample : packet->channel(c)) {
        hash = (hash ^ std::bit_cast<uint32_t>(sample)) * 1099511628211ull;
      }
    }
  }
  return hash;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2) {
    std::fprintf(stderr, "usage: %s <fixture directory>\n", argv[0]);
    return 2;
  }
  base::AtExitManager exit_manager;
  base::CommandLine::Init(argc, argv);
  base::FeatureList::InitInstance("", "");
  base::SingleThreadTaskExecutor executor;
  base::ThreadPoolInstance::CreateAndStartWithDefaultParams("webaudio-aac");
  mojo::core::Init();
  const std::string dir = argv[1];

  // The synchronous path the renderer tries first: FFmpeg, unchanged by the
  // reader's refactor, decodes WAV and has no AAC decoder, so AAC falls back.
  for (const char* file : {"stereo.wav", "lc.m4a"}) {
    const std::vector<uint8_t> data = ReadFile(dir + "/" + file);
    media::InMemoryUrlProtocol protocol(data, false);
    media::AudioFileReader reader(&protocol);
    const bool opened = reader.Open();
    std::vector<std::unique_ptr<media::AudioBus>> packets;
    const size_t frames = opened ? reader.Read(&packets) : 0;
    if (std::string(file) == "stereo.wav") {
      Expect(opened && frames == 88200 && reader.channels() == 2, "in-renderer",
             std::string(file) + " still decodes (" + std::to_string(frames) +
                 " frames)");
    } else {
      Expect(!opened, "in-renderer",
             std::string(file) + " has no FFmpeg decoder, so it falls back");
    }
  }

  GpuProcess gpu;
  // Every file must match macOS's decode in rate, channels, length and
  // samples: HE-AAC's tail and unlimited peaks, and raw ADTS HE-AAC at 44.1 kHz.
  for (const char* file : {"lc.m4a", "lc_mono.m4a", "lc.aac", "lc_long.m4a",
                           "he.m4a", "hev2.m4a", "he.aac"}) {
    const std::string path = dir + "/" + file;
    const std::vector<uint8_t> data = ReadFile(path);
    const Pcm reference = Reference(path);
    const Result direct = Run(data, InProcess(), 1);
    const Result mojo = Run(data, OverMojo(&gpu), kMojoDecodes);
    const std::string name = file;
    Expect(direct.done && direct.output && mojo.done && mojo.output, name,
           "decodes in-process and over Mojo");
    if (!direct.output || !mojo.output) {
      continue;
    }
    const Pcm ours = ToPcm(*mojo.output);
    const Pcm in_process = ToPcm(*direct.output);
    Expect(ours.sample_rate == in_process.sample_rate &&
               ours.channels == in_process.channels,
           name,
           "Mojo with " + std::to_string(kMojoDecodes) +
               " decodes in flight returns exactly the in-process decoder's "
               "audio");
    Expect(mojo.output->frames == ours.frames(), name,
           "reported frame count matches the audio");
    std::printf("INFO %s: %d Hz, %zu channels, %s, peak %.4f (macOS %.4f), "
                "decoded in %.0f ms\n",
                file, ours.sample_rate, ours.channels.size(),
                Frames(ours.frames(), reference.frames()).c_str(), ours.peak(),
                reference.peak(), mojo.elapsed.InMillisecondsF());
    const bool same_format = ours.sample_rate == reference.sample_rate &&
                             ours.channels.size() == reference.channels.size();
    const bool same_length = ours.frames() == reference.frames();
    const float difference = MaxDifference(ours, reference);
    const bool same_audio = same_format && difference < 1e-4f;
    const std::string what = Frames(ours.frames(), reference.frames()) +
                             ", largest difference " +
                             std::to_string(difference);
    const std::string format = std::to_string(ours.sample_rate) + " Hz, " +
                               std::to_string(ours.channels.size()) +
                               " channels; macOS " +
                               std::to_string(reference.sample_rate) + " Hz, " +
                               std::to_string(reference.channels.size());
    Expect(same_format, name,
           "keeps the decoder's rate and channels, as macOS does (" + format +
               ")");
    Expect(same_length && same_audio, name,
           "matches macOS to the frame and sample (" + what + ")");
  }

  // Raw ADTS cut mid-file keeps the frames before the cut, as Read() does.
  {
    const std::vector<uint8_t> data = ReadFile(dir + "/lc_truncated.aac");
    const Result result = Run(data, OverMojo(&gpu), kMojoDecodes);
    const size_t frames = result.output ? result.output->frames : 0;
    Expect(result.output && frames > 30000 && frames < 91136,
           "truncated ADTS", std::to_string(frames) + " frames before the cut");
  }

  // Not AAC: the fallback declines without creating a decoder.
  {
    const Result result =
        Run(ReadFile(dir + "/stereo.wav"), OverMojo(&gpu), kMojoDecodes);
    Expect(result.done && !result.output && !result.decoder_created,
           "stereo.wav", "is declined without reaching the GPU process");
  }
  {
    const Result result =
        Run(ReadFile(dir + "/garbage.bin"), OverMojo(&gpu), kMojoDecodes);
    Expect(result.done && !result.output && !result.decoder_created,
           "garbage.bin", "is declined without reaching the GPU process");
  }

  const std::vector<uint8_t> long_file = ReadFile(dir + "/lc_long.m4a");

  // The GPU process crashes part way through.
  {
    GpuControl* control = nullptr;
    const Result result =
        Run(long_file, OverMojo(&gpu, &control, {.close_at_decode = 50}),
            kMojoDecodes);
    Expect(result.done && !result.output && control &&
               control->decodes.load() >= 50,
           "GPU process crash",
           "fails the decode (EncodingError), with no partial audio, after " +
               std::to_string(result.elapsed.InMilliseconds()) + " ms");
  }

  // The GPU process is unavailable: the decoder's pipe is dropped unbound.
  {
    const Result result = Run(
        long_file, base::BindOnce([](scoped_refptr<base::SequencedTaskRunner>
                                         task_runner,
                                     media::MediaLog* media_log)
                                      -> std::unique_ptr<media::AudioDecoder> {
          mojo::PendingRemote<media::mojom::AudioDecoder> remote;
          std::ignore = remote.InitWithNewPipeAndPassReceiver();
          return std::make_unique<media::MojoAudioDecoder>(
              std::move(task_runner), media_log, std::move(remote));
        }),
        kMojoDecodes);
    Expect(result.done && !result.output, "GPU process unavailable",
           "fails the decode");
  }

  // The GPU process stops answering: the watchdog fails the decode.
  {
    const Result result = Run(
        long_file,
        OverMojo(&gpu, nullptr, {.hang_at_decode = 20}),
        kMojoDecodes, base::BindRepeating([] { return false; }),
        base::Seconds(2),
        base::Seconds(20));
    Expect(result.done && !result.output && result.elapsed < base::Seconds(6),
           "GPU process hang",
           "the 2 s watchdog fails the decode after " +
               std::to_string(result.elapsed.InMilliseconds()) + " ms");
  }

  // The document is destroyed mid-decode.
  {
    GpuControl* control = nullptr;
    auto checks = std::make_shared<int>(0);
    const Result result =
        Run(long_file, OverMojo(&gpu, &control), kMojoDecodes,
            base::BindRepeating([](std::shared_ptr<int> checks) {
              return ++*checks > 40;
            }, checks));
    // At most one check per packet sent, plus those still in flight.
    const int decodes = control ? control->decodes.load() : -1;
    Expect(result.done && !result.output && decodes > 0 &&
               decodes <= 41 + kMojoDecodes,
           "cancellation",
           "stops after " + std::to_string(decodes) +
               " packets reached the GPU process");
  }

  // A reset with decodes still queued at the service answers each of them, in
  // order, before the reset, and the decoder works afterwards.
  {
    const std::vector<uint8_t> data = ReadFile(dir + "/lc.m4a");
    media::InMemoryUrlProtocol protocol(data, false);
    media::AudioFileReader reader(&protocol);
    const bool opened = reader.OpenWithoutDecoder();
    media::NullMediaLog media_log;
    auto task_runner = base::SingleThreadTaskRunner::GetCurrentDefault();
    GpuControl* control = nullptr;
    media::MojoAudioDecoder decoder(
        task_runner, &media_log,
        gpu.CreateDecoder(&control));
    std::vector<std::string> events;
    base::RunLoop initialized;
    bool init_ok = false;
    if (opened) {
      decoder.Initialize(
          reader.config(), nullptr,
          base::BindOnce(
              [](bool* ok, base::OnceClosure quit, media::DecoderStatus status) {
                *ok = status.is_ok();
                std::move(quit).Run();
              },
              &init_ok, initialized.QuitClosure()),
          base::DoNothing(), base::DoNothing());
      initialized.Run();
    }
    base::RunLoop reset;
    for (int i = 0; init_ok && i < 10; ++i) {
      decoder.Decode(reader.ReadNextBuffer(),
                     base::BindOnce(
                         [](std::vector<std::string>* events, int i,
                            media::DecoderStatus status) {
                           events->push_back(std::to_string(i));
                         },
                         &events, i));
    }
    if (init_ok) {
      decoder.Reset(base::BindOnce(
          [](std::vector<std::string>* events, base::OnceClosure quit) {
            events->push_back("reset");
            std::move(quit).Run();
          },
          &events, reset.QuitClosure()));
      reset.Run();
    }
    std::optional<media::DecoderStatus> after;
    base::RunLoop decoded;
    if (init_ok) {
      decoder.Decode(reader.ReadNextBuffer(),
                     base::BindOnce(
                         [](std::optional<media::DecoderStatus>* after,
                            base::OnceClosure quit,
                            media::DecoderStatus status) {
                           *after = status;
                           std::move(quit).Run();
                         },
                         &after, decoded.QuitClosure()));
      decoded.Run();
    }
    std::string order;
    for (const auto& event : events) {
      order += (order.empty() ? "" : " ") + event;
    }
    Expect(init_ok && order == "0 1 2 3 4 5 6 7 8 9 reset" && after &&
               after->is_ok(),
           "service reset",
           "answers queued decodes in order, then the reset (" + order + ")");
  }

  // The service's own packets: lc.m4a's config and first access units.
  const std::vector<uint8_t> lc = ReadFile(dir + "/lc.m4a");
  media::InMemoryUrlProtocol lc_protocol(lc, false);
  media::AudioFileReader lc_reader(&lc_protocol);
  const bool lc_opened = lc_reader.OpenWithoutDecoder();
  std::vector<scoped_refptr<media::DecoderBuffer>> lc_packets;
  for (int i = 0; lc_opened && i < 3; ++i) {
    lc_packets.push_back(lc_reader.ReadNextBuffer());
  }
  const std::string not_initialized = std::to_string(
      static_cast<int>(media::DecoderStatus::Codes::kNotInitialized));
  const std::string failed_read = std::to_string(
      static_cast<int>(media::DecoderStatus::Codes::kFailedToGetDecoderBuffer));

  // Decodes whose data arrives after Initialize() failed: the service no
  // longer has a decoder and answers each in order.
  if (lc_opened) {
    GpuControl* control = nullptr;
    RawDecoder raw(&gpu, &control, {.hold_init = true});
    raw.Initialize(lc_reader.config());
    for (const auto& packet : lc_packets) {
      raw.Decode(packet);
    }
    raw.Flush();
    gpu.RunOnGpu(base::BindOnce(
        [](GpuControl* control) {
          std::move(control->held_init)
              .Run(media::DecoderStatus::Codes::kFailedToCreateDecoder);
        },
        control));
    RunUntil(base::BindRepeating(
        [](RawDecoder* raw) { return raw->init_status().has_value(); }, &raw));
    for (const auto& packet : lc_packets) {
      raw.Write(*packet);
    }
    RunUntil(base::BindRepeating(
        [](RawDecoder* raw) { return raw->answers().size() == 3; }, &raw));
    Expect(raw.init_status() && !raw.init_status()->is_ok() &&
               raw.AnswerText() == "0:" + not_initialized + " 1:" +
                                       not_initialized + " 2:" +
                                       not_initialized,
           "service after a failed Initialize()",
           "answers decodes read afterwards in order (" + raw.AnswerText() +
               ")");
  }

  // A read that fails behind a decode the decoder still has is answered after
  // that decode.
  if (lc_opened) {
    GpuControl* control = nullptr;
    RawDecoder raw(&gpu, &control, {.hold_decodes = true});
    raw.Initialize(lc_reader.config());
    RunUntil(base::BindRepeating(
        [](RawDecoder* raw) { return raw->init_status().has_value(); }, &raw));
    raw.Decode(lc_packets[0]);
    raw.Write(*lc_packets[0]);
    raw.ClosePipe();
    raw.Decode(lc_packets[1]);
    raw.Decode(lc_packets[2]);
    raw.Flush();
    // Give the service time to see the closed pipe and fail both reads.
    RunUntil(base::BindRepeating([] { return false; }),
             base::Milliseconds(200));
    const bool answered_early = !raw.answers().empty();
    gpu.RunOnGpu(base::BindOnce(
        [](GpuControl* control) {
          for (auto& decode_cb : control->held_decodes) {
            std::move(decode_cb).Run(media::DecoderStatus::Codes::kOk);
          }
          control->held_decodes.clear();
        },
        control));
    RunUntil(base::BindRepeating(
        [](RawDecoder* raw) { return raw->answers().size() == 3; }, &raw));
    Expect(raw.init_status() && raw.init_status()->is_ok() && !answered_early &&
               raw.AnswerText() == "0:ok 1:" + failed_read + " 2:" + failed_read,
           "service failed read",
           "is answered after the decode ahead of it (" + raw.AnswerText() +
               ")");
  }

  // Throughput: a 10-minute AAC-LC file, serial against pipelined decodes.
  {
    const std::string path = dir + "/lc_10min.m4a";
    const std::vector<uint8_t> data = ReadFile(path);
    SInt64 reference_frames = 0;
    {
      CFURLRef url = CFURLCreateFromFileSystemRepresentation(
          nullptr, reinterpret_cast<const UInt8*>(path.c_str()), path.size(),
          false);
      ExtAudioFileRef file = nullptr;
      if (ExtAudioFileOpenURL(url, &file) == noErr) {
        UInt32 size = sizeof(reference_frames);
        ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileLengthFrames,
                                &size, &reference_frames);
        ExtAudioFileDispose(file);
      }
      CFRelease(url);
    }
    std::optional<uint64_t> serial_digest;
    for (int decodes : {1, 2, 4, 8, 16, 32}) {
      const Result result = Run(data, OverMojo(&gpu), decodes,
                                base::BindRepeating([] { return false; }),
                                base::Seconds(30), base::Seconds(600));
      const size_t frames = result.output ? result.output->frames : 0;
      const uint64_t digest = result.output ? Digest(*result.output) : 0;
      if (!serial_digest) {
        serial_digest = digest;
      }
      std::printf("TIME lc_10min.m4a over Mojo, %d in flight: %.0f ms, %zu "
                  "frames (macOS %lld)\n",
                  decodes, result.elapsed.InMillisecondsF(), frames,
                  static_cast<long long>(reference_frames));
      Expect(result.output && frames == static_cast<size_t>(reference_frames) &&
                 digest == *serial_digest,
             "10-minute file",
             std::to_string(decodes) +
                 " in flight decodes the same audio as one at a time, to "
                 "macOS's length");
    }
  }

  std::printf("%s: %d failure(s)\n", g_failures ? "FAILED" : "PASSED",
              g_failures);
  return g_failures ? 1 : 0;
}

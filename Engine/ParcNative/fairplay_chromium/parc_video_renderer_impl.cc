#include "media/renderers/video_renderer_impl.h"

#include <algorithm>
#include <cmath>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/logging.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/tick_clock.h"
#include "base/time/time.h"
#include "media/base/timestamp_constants.h"
#include "media/base/video_frame.h"

namespace media {

namespace {

constexpr size_t kParcMaxWindowFrames = 64;
constexpr size_t kParcMaxWindowBytes = 192 * 1024 * 1024;
constexpr double kParcDecodeMargin = 1.25;
constexpr int kParcSpeedSamples = 8;
constexpr base::TimeDelta kParcMaxWindowSpan = base::Seconds(30);
constexpr base::TimeDelta kParcMaxStartWait = base::Seconds(2);

}

ParcVideoRendererExtension* VideoRendererImpl::GetParcExtension() {
  return this;
}

void VideoRendererImpl::ParcStartPlayingBackwardFrom(
    base::TimeDelta timestamp,
    ParcSeekDemuxerCB seek_demuxer_cb) {
  DVLOG(1) << __func__ << "(" << timestamp.InMicroseconds() << ")";
  DCHECK(task_runner_->RunsTasksInCurrentSequence());
  base::AutoLock auto_lock(lock_);
  DCHECK_EQ(state_, kFlushed);
  DCHECK(!pending_read_);
  DCHECK_EQ(buffering_state_, BUFFERING_HAVE_NOTHING);

  state_ = kPlaying;
  parc_backward_ = true;
  parc_seek_demuxer_cb_ = std::move(seek_demuxer_cb);
  last_render_time_ = last_frame_ready_time_ = base::TimeTicks();
  ParcDecodeWindowEndingAt_Locked(timestamp, true);
}

void VideoRendererImpl::ParcDecodeWindowEndingAt_Locked(base::TimeDelta end,
                                                        bool starting) {
  DCHECK(task_runner_->RunsTasksInCurrentSequence());
  lock_.AssertAcquired();
  DCHECK(parc_backward_);
  DCHECK(!parc_decoding_);

  parc_decoded_.clear();
  parc_decoded_bytes_ = 0;
  parc_window_passed_ = false;
  parc_window_awaited_ = false;
  parc_requested_end_ = end;
  base::TimeDelta cost;
  const base::TimeDelta span = ParcPlanWindow_Locked(&cost);
  if (parc_decode_speed_ && !parc_shown_.empty() && !end.is_negative()) {
    base::TimeDelta now = parc_shown_.back()->timestamp();
    const double rate = ParcClock_Locked(&now);
    const base::TimeDelta reached = now - cost * (rate * kParcDecodeMargin);
    if (starting && cost <= kParcMaxStartWait &&
        (reached < end || (parc_keyframe_distance_.is_zero() &&
                           parc_shown_.front()->timestamp() ==
                               parc_first_timestamp_))) {
      parc_window_awaited_ = true;
    } else if (reached < end) {
      end = std::max(reached, base::TimeDelta());
    }
  }
  parc_window_end_ = end;
  if (end.is_negative()) {
    parc_at_start_ = true;
    return;
  }

  parc_seek_time_ = std::max(end - span, base::TimeDelta());
  parc_window_start_ = tick_clock_->NowTicks();
  parc_first_timestamp_ = parc_last_timestamp_ = kNoTimestamp;
  parc_window_frames_ = 0;
  parc_decoding_ = true;
  parc_seeking_ = true;
  pending_read_ = false;
  if (mappable_shared_image_pool_) {
    mappable_shared_image_pool_->Abort();
  }
  cancel_on_flush_weak_factory_.InvalidateWeakPtrs();
  base::OnceClosure seeked =
      base::BindOnce(&VideoRendererImpl::ParcOnDemuxerSeeked,
                     cancel_on_flush_weak_factory_.GetWeakPtr());
  task_runner_->PostTask(
      FROM_HERE,
      base::BindOnce(parc_seek_demuxer_cb_, parc_seek_time_, std::move(seeked)));
}

base::TimeDelta VideoRendererImpl::ParcPlanWindow_Locked(
    base::TimeDelta* cost) {
  lock_.AssertAcquired();
  parc_stride_ = base::TimeDelta();
  parc_scan_ = false;
  if (cost) {
    *cost = base::TimeDelta();
  }
  if (!parc_decode_speed_ || !parc_frame_duration_.is_positive()) {
    return base::TimeDelta();
  }

  const double rate = ParcClock_Locked(nullptr);
  const double needed = rate * kParcDecodeMargin;
  const base::TimeDelta preroll =
      std::max(parc_preroll_, parc_keyframe_distance_);
  if (parc_decode_speed_ > needed) {
    const base::TimeDelta span =
        (parc_seek_cost_ * parc_decode_speed_ + preroll) *
        (needed / (parc_decode_speed_ - needed));
    const size_t budget = std::clamp<size_t>(
        kParcMaxWindowBytes / std::max<size_t>(parc_frame_bytes_, 1), 1,
        kParcMaxWindowFrames);
    const double frames = std::max(
        {1.0, std::floor(parc_render_interval_ * rate / parc_frame_duration_),
         std::ceil(span / (parc_frame_duration_ * budget))});
    if (span <= kParcMaxWindowSpan &&
        (frames == 1 || parc_frame_duration_ * frames * 2 <=
                            std::max(preroll, parc_seek_cost_ * needed))) {
      if (frames > 1) {
        parc_stride_ = parc_frame_duration_ * frames;
      }
      if (cost) {
        *cost = parc_seek_cost_ + (span + preroll) / parc_decode_speed_;
      }
      return span;
    }
  }

  parc_scan_ = true;
  if (cost) {
    *cost = parc_seek_cost_ + parc_frame_duration_ / parc_decode_speed_;
  }
  return base::TimeDelta();
}

double VideoRendererImpl::ParcClock_Locked(base::TimeDelta* now) {
  lock_.AssertAcquired();
  std::vector<base::TimeTicks> wall_clock_times;
  const bool moving = wall_clock_time_cb_.Run(
      {base::TimeDelta(), base::Seconds(1)}, &wall_clock_times);
  const base::TimeDelta second = wall_clock_times[0] - wall_clock_times[1];
  if (!second.is_positive()) {
    return 1;
  }
  const double rate = base::Seconds(1) / second;
  if (now && moving) {
    *now = (wall_clock_times[0] - tick_clock_->NowTicks()) * rate;
  }
  return rate;
}

void VideoRendererImpl::ParcOnDemuxerSeeked() {
  DCHECK(task_runner_->RunsTasksInCurrentSequence());
  base::AutoLock auto_lock(lock_);
  DCHECK(parc_decoding_);
  DCHECK(!parc_resetting_);
  parc_seeking_ = false;
  parc_resetting_ = true;
  video_decoder_stream_->Reset(
      base::BindOnce(&VideoRendererImpl::ParcOnDecoderStreamReset,
                     weak_factory_.GetWeakPtr()));
}

void VideoRendererImpl::ParcOnDecoderStreamReset() {
  DCHECK(task_runner_->RunsTasksInCurrentSequence());
  {
    base::AutoLock auto_lock(lock_);
    parc_resetting_ = false;
    if (state_ != kFlushing) {
      AttemptRead_Locked();
      return;
    }
  }
  OnVideoDecoderStreamResetDone();
}

void VideoRendererImpl::ParcFrameReady_Locked(scoped_refptr<VideoFrame> frame) {
  DCHECK(task_runner_->RunsTasksInCurrentSequence());
  lock_.AssertAcquired();

  if (!frame->metadata().end_of_stream) {
    ++stats_.video_frames_decoded;
    if (frame->metadata().power_efficient) {
      ++stats_.video_frames_decoded_power_efficient;
    }
  }

  if (frame->metadata().end_of_stream ||
      frame->timestamp() > parc_window_end_) {
    if (!frame->metadata().end_of_stream && parc_decoded_.empty() &&
        frame->timestamp() <= parc_requested_end_) {
      parc_decoded_bytes_ =
          VideoFrame::AllocationSize(frame->format(), frame->coded_size());
      parc_decoded_.push_back(std::move(frame));
    } else if (!frame->metadata().end_of_stream) {
      ++stats_.video_frames_dropped;
      if (parc_scan_ && parc_decoded_.size() == 1 &&
          frame->timestamp() > parc_last_timestamp_) {
        parc_last_timestamp_ = frame->timestamp();
        parc_last_frame_ticks_ = tick_clock_->NowTicks();
      }
    }
    UpdateStats_Locked();
    ParcFinishWindow_Locked();
    return;
  }

  const base::TimeDelta timestamp = frame->timestamp();
  const base::TimeTicks now = tick_clock_->NowTicks();
  const size_t bytes =
      VideoFrame::AllocationSize(frame->format(), frame->coded_size());
  parc_frame_bytes_ = bytes;
  if (parc_first_timestamp_ == kNoTimestamp) {
    parc_first_timestamp_ = parc_last_timestamp_ = timestamp;
    parc_first_frame_ticks_ = parc_last_frame_ticks_ = now;
    const base::TimeDelta seek_cost = now - parc_window_start_;
    parc_seek_cost_ = parc_seek_cost_.is_zero()
                          ? seek_cost
                          : (parc_seek_cost_ + seek_cost) / 2;
    parc_preroll_ = std::max(parc_preroll_, parc_seek_time_ - timestamp);

    if (parc_decode_speed_ && !parc_scan_ && !parc_shown_.empty()) {
      if (parc_window_awaited_ &&
          (parc_window_end_ - timestamp) / parc_decode_speed_ >
              kParcMaxStartWait) {
        parc_window_awaited_ = false;
        if (buffering_state_ == BUFFERING_HAVE_NOTHING) {
          TransitionToHaveEnough_Locked();
        }
      }
      if (!parc_window_awaited_) {
        base::TimeDelta current = parc_shown_.back()->timestamp();
        const double needed = ParcClock_Locked(&current) * kParcDecodeMargin;
        const base::TimeDelta end =
            timestamp + (current - timestamp) *
                            (parc_decode_speed_ / (parc_decode_speed_ + needed));
        parc_window_end_ = std::max(timestamp, std::min(parc_window_end_, end));
      }
    }
  } else if (timestamp > parc_last_timestamp_) {
    const base::TimeDelta duration = timestamp - parc_last_timestamp_;
    parc_frame_duration_ = parc_frame_duration_.is_zero()
                               ? duration
                               : (parc_frame_duration_ * 3 + duration) / 4;
    parc_last_timestamp_ = timestamp;
    parc_last_frame_ticks_ = now;
  }
  if (!parc_decode_speed_ && ++parc_window_frames_ == kParcSpeedSamples &&
      now > parc_first_frame_ticks_) {
    parc_decode_speed_ = (parc_last_timestamp_ - parc_first_timestamp_) /
                         (now - parc_first_frame_ticks_);
    ParcPlanWindow_Locked(nullptr);
    parc_scan_ = false;
  }

  if (parc_scan_ && !parc_decoded_.empty()) {
    ++stats_.video_frames_dropped;
    UpdateStats_Locked();
    ParcFinishWindow_Locked();
    return;
  }

  if (parc_stride_.is_positive() && !parc_decoded_.empty() &&
      timestamp > parc_decoded_.back()->timestamp() &&
      timestamp - parc_decoded_.back()->timestamp() <
          parc_stride_ - parc_frame_duration_ / 2) {
    ++stats_.video_frames_dropped;
    UpdateStats_Locked();
    AttemptRead_Locked();
    return;
  }

  auto it = std::upper_bound(
      parc_decoded_.begin(), parc_decoded_.end(), timestamp,
      [](base::TimeDelta timestamp, const scoped_refptr<VideoFrame>& other) {
        return timestamp < other->timestamp();
      });
  parc_decoded_bytes_ += bytes;
  parc_decoded_.insert(it, std::move(frame));
  while (parc_decoded_.size() > kParcMaxWindowFrames ||
         (parc_decoded_.size() > 1 &&
          parc_decoded_bytes_ > kParcMaxWindowBytes)) {
    const VideoFrame& first = *parc_decoded_.front();
    parc_decoded_bytes_ -=
        VideoFrame::AllocationSize(first.format(), first.coded_size());
    parc_decoded_.erase(parc_decoded_.begin());
    ++stats_.video_frames_dropped;
  }

  UpdateStats_Locked();
  AttemptRead_Locked();
}

void VideoRendererImpl::ParcFinishWindow_Locked() {
  DCHECK(task_runner_->RunsTasksInCurrentSequence());
  lock_.AssertAcquired();

  parc_decoding_ = false;
  if (parc_last_timestamp_ != kNoTimestamp &&
      parc_last_timestamp_ > parc_first_timestamp_) {
    const base::TimeDelta decoding =
        parc_last_frame_ticks_ - parc_first_frame_ticks_;
    if (decoding.is_positive()) {
      const double speed =
          (parc_last_timestamp_ - parc_first_timestamp_) / decoding;
      parc_decode_speed_ =
          parc_decode_speed_
              ? (parc_decode_speed_ + std::min(speed, parc_decode_speed_ * 2)) /
                    2
              : speed;
    }
  }
  if (parc_decoded_.empty()) {
    parc_at_start_ = true;
  }
  ParcShowNextWindow_Locked();
}

void VideoRendererImpl::ParcShowNextWindow_Locked() {
  DCHECK(task_runner_->RunsTasksInCurrentSequence());
  lock_.AssertAcquired();
  DCHECK(!parc_decoding_);

  if ((parc_shown_.empty() || parc_shown_passed_) && !parc_decoded_.empty()) {
    const bool starting = parc_shown_.empty();
    parc_shown_ = std::move(parc_decoded_);
    parc_decoded_.clear();
    parc_decoded_bytes_ = 0;
    parc_shown_passed_ = false;
    ParcDecodeWindowEndingAt_Locked(
        parc_shown_.front()->timestamp() - base::Microseconds(1), starting);
  }

  if (buffering_state_ == BUFFERING_HAVE_NOTHING &&
      !(parc_decoding_ && parc_window_awaited_)) {
    TransitionToHaveEnough_Locked();
  }
}

scoped_refptr<VideoFrame> VideoRendererImpl::ParcRender_Locked(
    base::TimeTicks deadline_min) {
  lock_.AssertAcquired();
  DCHECK(!parc_shown_.empty());

  std::vector<base::TimeDelta> timestamps;
  timestamps.reserve(parc_shown_.size() + 1);
  for (const auto& frame : parc_shown_) {
    timestamps.push_back(frame->timestamp());
  }
  timestamps.push_back(parc_window_end_);
  std::vector<base::TimeTicks> wall_clock_times;
  wall_clock_time_cb_.Run(timestamps, &wall_clock_times);

  size_t current = parc_shown_.size();
  while (current > 0 && wall_clock_times[current - 1] < deadline_min) {
    --current;
  }
  if (current == 0) {
    current = 1;
    const bool window_passed =
        parc_decoding_ && wall_clock_times.back() < deadline_min;
    if (!parc_shown_passed_ || window_passed != parc_window_passed_) {
      parc_shown_passed_ = true;
      parc_window_passed_ = window_passed;
      task_runner_->PostTask(FROM_HERE,
                             base::BindOnce(&VideoRendererImpl::ParcStall,
                                            weak_factory_.GetWeakPtr()));
    }
  }

  parc_shown_.resize(current);
  return parc_shown_.back();
}

void VideoRendererImpl::ParcStall() {
  DCHECK(task_runner_->RunsTasksInCurrentSequence());
  base::AutoLock auto_lock(lock_);
  if (!parc_backward_ || !parc_shown_passed_ || parc_at_start_) {
    return;
  }

  if (!parc_decoding_) {
    ParcShowNextWindow_Locked();
    return;
  }

  if (parc_window_passed_ && buffering_state_ == BUFFERING_HAVE_ENOUGH) {
    buffering_state_ = BUFFERING_HAVE_NOTHING;
    task_runner_->PostTask(
        FROM_HERE,
        base::BindOnce(&VideoRendererImpl::OnBufferingStateChange,
                       weak_factory_.GetWeakPtr(), buffering_state_));
  }
}

}

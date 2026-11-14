// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_BACKGROUND_PICTURE_IN_PICTURE_H_
#define PARC_NATIVE_NATIVE_BACKGROUND_PICTURE_IN_PICTURE_H_

#include <algorithm>
#include <optional>
#include <vector>

namespace parc {

enum class BackgroundPipVisibility {
  kVisible,
  kHidden,
  kOccluded,
};

enum class BackgroundPipSessionState {
  kIdle,
  kPendingActive,  // EnterPictureInPicture issued; awaiting session
  kActive,         // This policy owns the live PiP session
  kUserClosed,     // User closed/hid/returned while still backgrounded
  // Enter was issued then shell returned before the PiP bit flipped. A late
  // success must still Exit; do not treat it as foreign Idle PiP.
  kCancelPending,
};

enum class BackgroundPipCommand {
  kNone,
  kEnter,
  kExit,
};

enum class BackgroundPipSignal {
  kReconcile,
  kPictureInPictureChanged,
  // Chromium often never fires PiP-changed(false) on a failed Enter. The
  // owner arms this after a short wait so pending can retry.
  kEnterTimedOut,
};

struct BackgroundPipStep {
  BackgroundPipSessionState state = BackgroundPipSessionState::kIdle;
  BackgroundPipCommand command = BackgroundPipCommand::kNone;
};

inline bool BackgroundPipShellIsForeground(BackgroundPipVisibility visibility) {
  return visibility == BackgroundPipVisibility::kVisible;
}

inline bool BackgroundPipShellIsBackgrounded(BackgroundPipVisibility visibility) {
  return visibility == BackgroundPipVisibility::kHidden ||
         visibility == BackgroundPipVisibility::kOccluded;
}

inline bool BackgroundPipMediaEligible(bool auto_picture_in_picture_allowed,
                                       bool controllable,
                                       bool playing,
                                       bool muted,
                                       bool has_video) {
  return auto_picture_in_picture_allowed && controllable && playing && !muted &&
         has_video;
}

// Pure reduce: shell + Chromium PiP bit + media eligibility + signal.
// Paint visibility is intentionally not an input.
// `silent_enter_retries_remaining`: at most one automatic re-Enter after a
// silent timeout while still backgrounded. Pass 1 on the first pending Enter
// from Idle; pass 0 after that retry has been consumed.
inline BackgroundPipStep ReduceBackgroundPipSession(
    BackgroundPipSessionState state,
    BackgroundPipVisibility shell,
    bool chromium_in_picture_in_picture,
    bool media_eligible,
    BackgroundPipSignal signal = BackgroundPipSignal::kReconcile,
    unsigned silent_enter_retries_remaining = 0) {
  BackgroundPipStep step;
  step.state = state;

  if (BackgroundPipShellIsForeground(shell)) {
    if (state == BackgroundPipSessionState::kCancelPending) {
      if (chromium_in_picture_in_picture) {
        step.state = BackgroundPipSessionState::kIdle;
        step.command = BackgroundPipCommand::kExit;
      } else if (signal == BackgroundPipSignal::kPictureInPictureChanged ||
                 signal == BackgroundPipSignal::kEnterTimedOut) {
        // Late failure / timeout — request is done, no Exit needed.
        step.state = BackgroundPipSessionState::kIdle;
      }
      // Else keep CancelPending until late success, false edge, or timeout.
      return step;
    }
    // Own or in-flight auto-enter must Exit if Chromium already shows PiP.
    if ((state == BackgroundPipSessionState::kActive ||
         state == BackgroundPipSessionState::kPendingActive) &&
        chromium_in_picture_in_picture) {
      step.state = BackgroundPipSessionState::kIdle;
      step.command = BackgroundPipCommand::kExit;
      return step;
    }
    // Enter still in flight (bit not flipped): remember the cancel so a late
    // success is Exit'd instead of classified as foreign Idle PiP.
    if (state == BackgroundPipSessionState::kPendingActive) {
      step.state = BackgroundPipSessionState::kCancelPending;
      return step;
    }
    step.state = BackgroundPipSessionState::kIdle;
    return step;
  }

  switch (state) {
    case BackgroundPipSessionState::kIdle:
      if (chromium_in_picture_in_picture) {
        // Manual / foreign PiP — do not claim.
        return step;
      }
      if (media_eligible) {
        step.state = BackgroundPipSessionState::kPendingActive;
        step.command = BackgroundPipCommand::kEnter;
      }
      return step;

    case BackgroundPipSessionState::kPendingActive:
      if (chromium_in_picture_in_picture) {
        step.state = BackgroundPipSessionState::kActive;
        return step;
      }
      if (signal == BackgroundPipSignal::kPictureInPictureChanged) {
        // Explicit false edge while pending — back to Idle (fresh edge can enter).
        step.state = BackgroundPipSessionState::kIdle;
        return step;
      }
      if (signal == BackgroundPipSignal::kEnterTimedOut) {
        if (media_eligible && silent_enter_retries_remaining > 0) {
          step.state = BackgroundPipSessionState::kPendingActive;
          step.command = BackgroundPipCommand::kEnter;
        } else {
          // No more silent retries — wait for a new shell/media edge from Idle.
          step.state = BackgroundPipSessionState::kIdle;
        }
        return step;
      }
      // Reconcile: keep waiting. Do not drop on transient !media_eligible —
      // that races an in-flight Enter and orphans a late success as foreign.
      return step;

    case BackgroundPipSessionState::kActive:
      // Only an explicit PiP-false edge counts as user dismiss. Reconcile
      // must not latch UserClosed on transient bit churn.
      if (!chromium_in_picture_in_picture &&
          signal == BackgroundPipSignal::kPictureInPictureChanged) {
        step.state = BackgroundPipSessionState::kUserClosed;
      }
      return step;

    case BackgroundPipSessionState::kUserClosed:
      return step;

    case BackgroundPipSessionState::kCancelPending:
      // Backgrounded again before the cancelled Enter settled.
      if (chromium_in_picture_in_picture) {
        step.state = BackgroundPipSessionState::kActive;
        return step;
      }
      if (signal == BackgroundPipSignal::kPictureInPictureChanged) {
        // Cancelled request failed; start a fresh enter while still away.
        if (media_eligible) {
          step.state = BackgroundPipSessionState::kPendingActive;
          step.command = BackgroundPipCommand::kEnter;
        } else {
          step.state = BackgroundPipSessionState::kIdle;
        }
        return step;
      }
      if (signal == BackgroundPipSignal::kEnterTimedOut) {
        // Cmd-Tab flick: settle window ended while away again — resume enter
        // instead of sitting Idle with playing video and no PiP.
        if (media_eligible) {
          step.state = BackgroundPipSessionState::kPendingActive;
          step.command = BackgroundPipCommand::kEnter;
        } else {
          step.state = BackgroundPipSessionState::kIdle;
        }
        return step;
      }
      return step;
  }
  return step;
}

template <typename State>
bool HasBackgroundPipVideoTrack(const std::optional<std::vector<State>>& states,
                                State audio_video, State video_only) {
  if (!states) return false;
  return std::ranges::any_of(*states, [=](State state) {
    return state == audio_video || state == video_only;
  });
}

inline bool ShouldEnterBackgroundVideoPictureInPicture(
    BackgroundPipVisibility visibility,
    bool already_in_picture_in_picture,
    bool auto_picture_in_picture_allowed,
    bool controllable,
    bool playing,
    bool muted,
    bool has_video,
    bool user_dismissed_while_backgrounded = false) {
  const auto step = ReduceBackgroundPipSession(
      user_dismissed_while_backgrounded ? BackgroundPipSessionState::kUserClosed
                                        : BackgroundPipSessionState::kIdle,
      visibility, already_in_picture_in_picture,
      BackgroundPipMediaEligible(auto_picture_in_picture_allowed, controllable,
                                 playing, muted, has_video));
  return step.command == BackgroundPipCommand::kEnter;
}

inline bool ShouldRememberBackgroundVideoPictureInPictureDismissal(
    BackgroundPipVisibility visibility_when_left_pip) {
  return BackgroundPipShellIsBackgrounded(visibility_when_left_pip);
}

inline bool ShouldExitBackgroundVideoPictureInPicture(
    BackgroundPipVisibility visibility,
    bool entered_by_background_policy,
    bool currently_in_picture_in_picture) {
  const auto step = ReduceBackgroundPipSession(
      entered_by_background_policy ? BackgroundPipSessionState::kActive
                                   : BackgroundPipSessionState::kIdle,
      visibility, currently_in_picture_in_picture,
      /*media_eligible=*/false);
  return step.command == BackgroundPipCommand::kExit;
}

}  // namespace parc

#endif  // PARC_NATIVE_NATIVE_BACKGROUND_PICTURE_IN_PICTURE_H_

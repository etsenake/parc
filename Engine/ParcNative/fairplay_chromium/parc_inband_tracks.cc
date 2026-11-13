#include "media/base/parc_inband_tracks.h"

namespace media {

ParcInbandTextTrack::ParcInbandTextTrack() = default;
ParcInbandTextTrack::ParcInbandTextTrack(const ParcInbandTextTrack&) = default;
ParcInbandTextTrack::ParcInbandTextTrack(ParcInbandTextTrack&&) = default;
ParcInbandTextTrack& ParcInbandTextTrack::operator=(
    const ParcInbandTextTrack&) = default;
ParcInbandTextTrack& ParcInbandTextTrack::operator=(ParcInbandTextTrack&&) =
    default;
ParcInbandTextTrack::~ParcInbandTextTrack() = default;

ParcInbandTextCue::ParcInbandTextCue() = default;
ParcInbandTextCue::ParcInbandTextCue(const ParcInbandTextCue&) = default;
ParcInbandTextCue::ParcInbandTextCue(ParcInbandTextCue&&) = default;
ParcInbandTextCue& ParcInbandTextCue::operator=(const ParcInbandTextCue&) =
    default;
ParcInbandTextCue& ParcInbandTextCue::operator=(ParcInbandTextCue&&) = default;
ParcInbandTextCue::~ParcInbandTextCue() = default;

ParcDataCueValue::ParcDataCueValue() = default;
ParcDataCueValue::ParcDataCueValue(const ParcDataCueValue&) = default;
ParcDataCueValue::ParcDataCueValue(ParcDataCueValue&&) = default;
ParcDataCueValue& ParcDataCueValue::operator=(const ParcDataCueValue&) =
    default;
ParcDataCueValue& ParcDataCueValue::operator=(ParcDataCueValue&&) = default;
ParcDataCueValue::~ParcDataCueValue() = default;
bool ParcDataCueValue::operator==(const ParcDataCueValue&) const = default;

ParcInbandDataCue::ParcInbandDataCue() = default;
ParcInbandDataCue::ParcInbandDataCue(const ParcInbandDataCue&) = default;
ParcInbandDataCue::ParcInbandDataCue(ParcInbandDataCue&&) = default;
ParcInbandDataCue& ParcInbandDataCue::operator=(const ParcInbandDataCue&) =
    default;
ParcInbandDataCue& ParcInbandDataCue::operator=(ParcInbandDataCue&&) = default;
ParcInbandDataCue::~ParcInbandDataCue() = default;

ParcInbandAudioTrack::ParcInbandAudioTrack() = default;
ParcInbandAudioTrack::ParcInbandAudioTrack(const ParcInbandAudioTrack&) =
    default;
ParcInbandAudioTrack::ParcInbandAudioTrack(ParcInbandAudioTrack&&) = default;
ParcInbandAudioTrack& ParcInbandAudioTrack::operator=(
    const ParcInbandAudioTrack&) = default;
ParcInbandAudioTrack& ParcInbandAudioTrack::operator=(ParcInbandAudioTrack&&) =
    default;
ParcInbandAudioTrack::~ParcInbandAudioTrack() = default;

ParcInbandTrackForwarder::ParcInbandTrackForwarder(
    base::RepeatingCallback<void(const std::vector<ParcInbandTextTrack>&,
                                 ParcInbandTextTrackModeCB)> set_tracks,
    base::RepeatingCallback<void(const std::string&,
                                 const std::vector<ParcInbandTextCue>&)>
        add_cues,
    base::RepeatingCallback<void(const std::string&,
                                 const std::vector<ParcInbandDataCue>&)>
        add_data_cues,
    base::RepeatingCallback<void(const std::vector<ParcInbandAudioTrack>&,
                                 ParcInbandAudioTrackEnabledCB)>
        set_audio_tracks)
    : set_tracks_(std::move(set_tracks)),
      add_cues_(std::move(add_cues)),
      add_data_cues_(std::move(add_data_cues)),
      set_audio_tracks_(std::move(set_audio_tracks)) {}

ParcInbandTrackForwarder::~ParcInbandTrackForwarder() = default;

void ParcInbandTrackForwarder::ParcSetInbandTextTracks(
    const std::vector<ParcInbandTextTrack>& tracks,
    ParcInbandTextTrackModeCB set_mode) {
  set_tracks_.Run(tracks, std::move(set_mode));
}

void ParcInbandTrackForwarder::ParcAddInbandTextCues(
    const std::string& key,
    const std::vector<ParcInbandTextCue>& cues) {
  add_cues_.Run(key, cues);
}

void ParcInbandTrackForwarder::ParcAddInbandDataCues(
    const std::string& key,
    const std::vector<ParcInbandDataCue>& cues) {
  add_data_cues_.Run(key, cues);
}

void ParcInbandTrackForwarder::ParcSetInbandAudioTracks(
    const std::vector<ParcInbandAudioTrack>& tracks,
    ParcInbandAudioTrackEnabledCB set_enabled) {
  set_audio_tracks_.Run(tracks, std::move(set_enabled));
}

}

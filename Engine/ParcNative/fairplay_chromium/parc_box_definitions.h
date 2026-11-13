#ifndef MEDIA_FORMATS_MP4_PARC_BOX_DEFINITIONS_H_
#define MEDIA_FORMATS_MP4_PARC_BOX_DEFINITIONS_H_

namespace media::mp4 {

class BoxReader;
struct AudioSampleEntry;
struct VideoSampleEntry;

bool ParcReadAudioSampleEntryBoxes(BoxReader* reader, AudioSampleEntry* entry);
bool ParcReadH263SampleEntry(BoxReader* reader, VideoSampleEntry* entry);

}

#endif

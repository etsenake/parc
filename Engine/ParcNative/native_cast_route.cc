// Copyright 2026 Parc contributors.
#include "native_cast_route.h"

#include <algorithm>

#include "base/feature_list.h"
#include "chrome/browser/media/router/media_router_feature.h"
#include "components/media_router/browser/presentation/web_contents_presentation_manager.h"
#include "components/media_router/common/media_source.h"
#include "components/sessions/content/session_tab_helper.h"
#include "content/public/browser/presentation_request.h"
#include "url/gurl.h"

namespace parc {

std::optional<media_router::MediaRoute> CastRouteForWebContents(
    content::WebContents* web_contents,
    const std::vector<media_router::MediaRoute>& routes) {
  auto presentation_manager =
      media_router::WebContentsPresentationManager::Get(web_contents);
  if (presentation_manager) {
    for (const auto& started : presentation_manager->GetMediaRoutes()) {
      auto it = std::ranges::find(routes, started.media_route_id(),
                                  &media_router::MediaRoute::media_route_id);
      if (it != routes.end()) {
        return *it;
      }
    }
  }
  const int tab_id = sessions::SessionTabHelper::IdForTab(web_contents).id();
  const bool mirroring = base::FeatureList::IsEnabled(
      media_router::kFallbackToAudioTabMirroring);
  for (const auto& route : routes) {
    const auto& source = route.media_source();
    if ((source.IsRemotePlaybackSource() &&
         source.TabIdFromRemotePlaybackSource() == tab_id) ||
        (mirroring && source.IsTabMirroringSource() &&
         source.TabId() == tab_id)) {
      return route;
    }
  }
  if (!presentation_manager ||
      !presentation_manager->HasDefaultPresentationRequest()) {
    return std::nullopt;
  }
  const auto& urls =
      presentation_manager->GetDefaultPresentationRequest().presentation_urls;
  for (const auto& route : routes) {
    if (route.is_local() && route.is_connecting() &&
        std::ranges::any_of(urls, [&route](const GURL& url) {
          return route.media_source() ==
                 media_router::MediaSource::ForPresentationUrl(url);
        })) {
      return route;
    }
  }
  return std::nullopt;
}

std::optional<media_router::MediaSource> CastSpeakerSourceForWebContents(
    content::WebContents* web_contents) {
  auto presentation_manager =
      media_router::WebContentsPresentationManager::Get(web_contents);
  const SessionID tab_id = sessions::SessionTabHelper::IdForTab(web_contents);
  if (!base::FeatureList::IsEnabled(
          media_router::kFallbackToAudioTabMirroring) ||
      !presentation_manager ||
      !presentation_manager->HasDefaultPresentationRequest() ||
      !tab_id.is_valid()) {
    return std::nullopt;
  }
  return media_router::MediaSource::ForTab(tab_id.id());
}

bool HasCastSpeaker(const std::vector<media_router::MediaSink>& sinks) {
  return std::ranges::any_of(sinks, [](const media_router::MediaSink& sink) {
    return sink.icon_type() == media_router::SinkIconType::CAST_AUDIO ||
           sink.icon_type() == media_router::SinkIconType::CAST_AUDIO_GROUP;
  });
}

}

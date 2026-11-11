// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_PROFILE_POLICY_H_
#define PARC_NATIVE_NATIVE_PROFILE_POLICY_H_

class PrefRegistrySimple;
namespace parc {
void RegisterNativeProfilePrefs(PrefRegistrySimple* registry);
bool RestoreNativeSessionState();
}  // namespace parc

#endif  // PARC_NATIVE_NATIVE_PROFILE_POLICY_H_

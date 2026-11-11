// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_PROFILE_POLICY_H_
#define PARC_NATIVE_NATIVE_PROFILE_POLICY_H_

class PrefRegistrySimple;
class PrefService;
namespace parc {
void RegisterNativeProfilePrefs(PrefRegistrySimple* registry);
bool RestoreNativeSessionState();
bool NativeGaiaAccountsAllowed(PrefService* preferences);
}  // namespace parc

#endif  // PARC_NATIVE_NATIVE_PROFILE_POLICY_H_

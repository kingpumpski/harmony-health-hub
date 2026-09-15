export interface DeploymentProfile {
  profileKey: string;
  countryCode: string;
  regionCode?: string;
  locale: string;
  timezone: string;
  currencyCode: string;
  dataResidencyRegion?: string;
  regulatoryProfile: Record<string, unknown>;
  clinicalProfile: Record<string, unknown>;
  communicationProfile: Record<string, unknown>;
  accessibilityProfile: Record<string, unknown>;
  securityProfile: Record<string, unknown>;
  enabledModules: string[];
  effectiveFrom: string;
  effectiveTo?: string;
}

export interface DeploymentProfileSource {
  findActive(profileKey: string, at: Date): DeploymentProfile | undefined;
}

export function resolveDeploymentProfile(source: DeploymentProfileSource, profileKey: string, at = new Date()): DeploymentProfile {
  const profile = source.findActive(profileKey, at);
  if (!profile) throw new Error(`No active deployment profile for ${profileKey}`);
  const effectiveFrom = new Date(profile.effectiveFrom);
  const effectiveTo = profile.effectiveTo ? new Date(profile.effectiveTo) : undefined;
  if (Number.isNaN(effectiveFrom.getTime()) || (effectiveTo && Number.isNaN(effectiveTo.getTime()))) {
    throw new Error(`Invalid effective dates for deployment profile ${profileKey}`);
  }
  if (effectiveFrom > at || (effectiveTo && effectiveTo <= at)) {
    throw new Error(`Deployment profile ${profileKey} is not effective at the requested time`);
  }
  if (!/^[A-Z]{2,3}$/.test(profile.countryCode)) throw new Error(`Invalid country code for ${profileKey}`);
  if (!/^[A-Z]{3}$/.test(profile.currencyCode)) throw new Error(`Invalid currency code for ${profileKey}`);
  if (!profile.locale || !profile.timezone) throw new Error(`Locale/timezone is required for ${profileKey}`);
  return { ...profile, enabledModules: [...new Set(profile.enabledModules)] };
}

export function isModuleAllowed(profile: DeploymentProfile, moduleId: string): boolean {
  return profile.enabledModules.includes(moduleId);
}

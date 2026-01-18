# Flux Bootstrap - DEPRECATED
# This file is kept for reference but flux_bootstrap_git has been replaced
# with a two-phase approach using flux-operator and flux-instance modules.
#
# The new approach:
# 1. flux-operator module deploys the Flux operator via Helm
# 2. flux-instance module creates FluxInstance CR after operator is ready
#
# This prevents the observedGeneration: -1 race condition by ensuring
# Flux controllers are fully ready before HelmReleases are created.

# NOTE: flux_bootstrap_git resource removed - use flux-operator and flux-instance modules

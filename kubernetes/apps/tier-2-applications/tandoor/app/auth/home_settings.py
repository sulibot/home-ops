"""Site-specific authentication settings for the pinned Tandoor release."""
from recipes.settings import *  # noqa: F403

ACCOUNT_ADAPTER = "cookbook.helper.home_auth.LocalAccountAdapter"
SOCIALACCOUNT_ADAPTER = "cookbook.helper.home_auth.TrustedSocialAccountAdapter"

# Do not implicitly connect an OIDC identity to a local account by email.
SOCIALACCOUNT_EMAIL_AUTHENTICATION = False
SOCIALACCOUNT_EMAIL_AUTHENTICATION_AUTO_CONNECT = False

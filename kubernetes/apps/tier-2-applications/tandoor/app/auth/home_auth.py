"""Allow trusted Authentik signups into the existing shared household.

Authentik must enforce the trusted-users application policy. Local signup and
email-based account linking remain disabled; the recovery account can log in.
"""
import os

from django.contrib.auth.models import Group
from django.db import transaction
from django_scopes import scopes_disabled

from cookbook.helper.AllAuthCustomAdapter import AllAuthCustomAdapter
from cookbook.helper.social_adapter import TandoorSocialAccountAdapter
from cookbook.models import Household, Space, UserSpace


class LocalAccountAdapter(AllAuthCustomAdapter):
    def is_open_for_signup(self, request):
        return False


class TrustedSocialAccountAdapter(TandoorSocialAccountAdapter):
    def is_open_for_signup(self, request, sociallogin):
        # The provider ID is the configured Authentik OIDC application, not a
        # user-supplied email claim. Authentik enforces its trusted-user policy.
        return sociallogin.account.provider == "authentik"

    @transaction.atomic
    def save_user(self, request, sociallogin, form=None):
        if sociallogin.account.provider != "authentik":
            raise ValueError("Only Authentik can provision shared-space users")
        with scopes_disabled():
            space = Space.objects.get(pk=int(os.environ["TANDOOR_HOME_SPACE_ID"]))
            household = Household.objects.get(
                pk=int(os.environ["TANDOOR_FAMILY_HOUSEHOLD_ID"]), space=space
            )
            user_group = Group.objects.get(name="user")
            user = super().save_user(request, sociallogin, form=form)
            membership, created = UserSpace.objects.get_or_create(
                user=user, space=space, defaults={"household": household, "active": False}
            )
            if created:
                membership.groups.add(user_group)
            # Do not alter roles or household for an already-existing membership.
            UserSpace.objects.filter(user=user).exclude(pk=membership.pk).update(active=False)
            if not membership.active:
                membership.active = True
                membership.save(update_fields=["active"])
            return user

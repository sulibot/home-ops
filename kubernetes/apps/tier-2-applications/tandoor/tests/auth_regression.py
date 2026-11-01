# Run with: kubectl exec -i -n default deploy/tandoor -- /opt/recipes/venv/bin/python manage.py shell < kubernetes/apps/tier-2-applications/tandoor/tests/auth_regression.py
from django.conf import settings
from django_scopes import scopes_disabled
from cookbook.helper.home_auth import LocalAccountAdapter, TrustedSocialAccountAdapter
from cookbook.helper.social_adapter import TandoorSocialAccountAdapter
from cookbook.models import Household, Space, UserSpace
from types import SimpleNamespace
from django.contrib.auth.models import User, AnonymousUser
from django.test import RequestFactory
from django.db import transaction
from unittest.mock import patch
from allauth.socialaccount.models import SocialAccount, SocialLogin
from allauth.account.models import EmailAddress
import os
home_id = int(os.environ['TANDOOR_HOME_SPACE_ID'])
family_id = int(os.environ['TANDOOR_FAMILY_HOUSEHOLD_ID'])
adapter = TrustedSocialAccountAdapter()
r = RequestFactory().get('/accounts/oidc/authentik/login/callback/')
r.user = AnonymousUser()
r.session = {}
with scopes_disabled(), transaction.atomic():
    assert not LocalAccountAdapter().is_open_for_signup(r)
    assert adapter.is_open_for_signup(r, SimpleNamespace(account=SimpleNamespace(provider='authentik')))
    assert not adapter.is_open_for_signup(r, SimpleNamespace(account=SimpleNamespace(provider='other')))
    assert not settings.SOCIALACCOUNT_EMAIL_AUTHENTICATION
    assert not settings.SOCIALACCOUNT_EMAIL_AUTHENTICATION_AUTO_CONNECT
    # A verified email matching the recovery account must not auto-link it.
    recovery = User.objects.get(username="tandoor-recovery")
    recovery_email = EmailAddress.objects.get(user=recovery, primary=True).email
    provider = SimpleNamespace(app=None, get_settings=lambda: {})
    collision = SimpleNamespace(provider=provider, email_addresses=[SimpleNamespace(email=recovery_email, verified=True)])
    assert adapter.authenticate_by_email(collision) is None
    social = SocialLogin(user=User(username='codex-temporary-auth-test'), account=SocialAccount(provider='authentik',uid='codex-temporary-auth-test'))
    user = adapter.save_user(r,social)
    home=Space.objects.get(pk=home_id); family=Household.objects.get(pk=family_id,space=home)
    memberships=UserSpace.objects.filter(user=user,space=home)
    assert memberships.count()==1
    membership=memberships.get()
    assert membership.active and membership.household_id==family.id
    assert list(membership.groups.values_list('name',flat=True))==['user']
    assert not user.is_superuser
    with patch.object(TandoorSocialAccountAdapter,'save_user',return_value=user):
        adapter.save_user(r, social)
    assert UserSpace.objects.filter(user=user,space=home).count()==1
    os.environ['TANDOOR_FAMILY_HOUSEHOLD_ID']='999999999'
    try:
        adapter.save_user(r,social)
        raise AssertionError('missing household should fail')
    except Household.DoesNotExist:
        pass
    os.environ['TANDOOR_FAMILY_HOUSEHOLD_ID']=str(family_id)
    os.environ['TANDOOR_HOME_SPACE_ID']='999999999'
    try:
        adapter.save_user(r,social)
        raise AssertionError('missing space should fail')
    except Space.DoesNotExist:
        pass
    os.environ['TANDOOR_HOME_SPACE_ID']=str(home_id)
    try:
        adapter.save_user(r,SimpleNamespace(account=SimpleNamespace(provider='other')))
        raise AssertionError('wrong provider should fail')
    except ValueError:
        pass
    transaction.set_rollback(True)
print('PASS: local denied; Authentik allowed; other denied; new user Home/Family user, idempotent; missing space/household fail closed; email auto-link disabled; transaction rolled back')

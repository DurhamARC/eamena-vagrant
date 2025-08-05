from django.core.management.base import BaseCommand
from django.core.cache import cache
from django.contrib.auth.models import User


class Command(BaseCommand):
    help = 'Clear user permission cache'

    def add_arguments(self, parser):
        parser.add_argument('--user', help='Clear cache for specific user')
        parser.add_argument('--all', action='store_true', help='Clear all caches')

    def handle(self, *args, **options):
        if options['user']:
            user = User.objects.get(username=options['user'])
            cache.delete(f"auth.user.{user.pk}")
            user._perm_cache = {}
            user._group_perm_cache = {}
            self.stdout.write(f"Cleared cache for user: {options['user']}")
        elif options['all']:
            cache.clear()
            self.stdout.write("Cleared all caches")
        else:
            # Clear permission caches for all users
            for user in User.objects.all():
                user._perm_cache = {}
                user._group_perm_cache = {}
            self.stdout.write("Cleared permission caches for all users")
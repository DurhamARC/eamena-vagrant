from django.core.management.base import BaseCommand
from django.contrib.auth.models import Permission

class Command(BaseCommand):
    help = 'List all available user permissions'

    def handle(self, *args, **options):
        perms = Permission.objects.all().values_list('codename', flat=True)
        print(','.join(perms))
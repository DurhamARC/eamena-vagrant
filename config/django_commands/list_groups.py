from django.core.management.base import BaseCommand
from django.contrib.auth.models import Group

class Command(BaseCommand):
    help = 'List all available permission groups'

    def handle(self, *args, **options):
        groups = Group.objects.all().values_list('name', flat=True)
        print(','.join(groups))
from django.core.management.base import BaseCommand
from django.contrib.auth.models import User


class Command(BaseCommand):
    help = 'List all users'

    def handle(self, *args, **options):
        users = User.objects.all().values_list('username', flat=True)
        print(','.join(users))
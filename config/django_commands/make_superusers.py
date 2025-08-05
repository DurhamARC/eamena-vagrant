from django.core.management.base import BaseCommand
from django.contrib.auth.models import User, Group, Permission


class Command(BaseCommand):
    help = 'Create users and assign them to groups'

    def add_arguments(self, parser):
        parser.add_argument('users', help='Comma-separated user:password pairs')
        parser.add_argument('groups', help='Comma-separated group names')
        parser.add_argument('permissions', nargs='?', help='Comma-separated permission codenames')

    def handle(self, *args, **options):
        # Parse users
        users_data = []
        for user_pair in options['users'].split(','):
            username, password = user_pair.strip().split(':')
            users_data.append((username, password))
        
        # Parse groups
        group_names = [name.strip() for name in options['groups'].split(',')]
        
        # Get group objects
        group_objects = []
        for group_name in group_names:
            try:
                group = Group.objects.get(name=group_name)
                group_objects.append(group)
            except Group.DoesNotExist:
                self.stdout.write(f"Warning: Group '{group_name}' does not exist")
        
        # Parse permissions
        permission_objects = []
        if options['permissions'] is not None:
            perm_codenames = [codename.strip() for codename in options['permissions'].split(',')]
            
            # Get permission objects
            for perm_name in perm_codenames:
                try:
                    permission = Permission.objects.get(codename=perm_name)
                    permission_objects.append(permission)
                except Permission.DoesNotExist:
                    self.stdout.write(f"Warning: Permission '{perm_name}' does not exist")
        
        # Create users and assign groups
        for username, password in users_data:
            user, created = User.objects.get_or_create(username=username, is_staff=True, is_superuser=True)
            
            if created:
                user.set_password(password)
                user.save()
                self.stdout.write(f"Created user: {username}")
            else:
                self.stdout.write(f"User {username} already exists")
            
            # Add to groups
            for group in group_objects:
                user.groups.add(group)
            
            # Add to permissions
            for permission in permission_objects:
                user.user_permissions.add(permission)
            
            self.stdout.write(f"Added {username} to groups: {', '.join(group_names)}")
            self.stdout.write(f"Assigned {username} {len(permission_objects)} user permissions")
            
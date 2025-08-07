import os

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

os.environ['GDAL_DATA'] = '/opt/bitnami/postgresql/share/gdal/'

DATABASES = {
    "default": {
        "ATOMIC_REQUESTS": False,
        "AUTOCOMMIT": True,
        "CONN_MAX_AGE": 0,
        "ENGINE": "django.contrib.gis.db.backends.postgis",
        "HOST": "localhost",
        "NAME": "herbridge",
        "OPTIONS": {},
        "PASSWORD": "postgis",
        "PORT": "5432",
        "POSTGIS_TEMPLATE": "template_postgis",
        "TEST": {
            "CHARSET": None,
            "COLLATION": None,
            "MIRROR": None,
            "NAME": None
        },
        "TIME_ZONE": None,
        "USER": "postgres"
    }
}

DATABASES['default']['USER'] = '<postgres user>'
DATABASES['default']['PASSWORD'] = '<postgres password>'
DATABASES['default']['NAME'] = '<postgres database>'

DEBUG = False
ALLOWED_HOSTS = ['35.225.119.170', 'localhost', '127.0.0.1', '<sub.domain.com>']

FRONTEND_AUTH_PASSWORD = '<a password for access to this instance>'
FRONTEND_AUTH_TOKEN = '<a cookie for users who are logged in>'
EAMENA_TARGET = '<an eamena installation as a target>'

ARCHES_USERNAME = '<arches app user with permission to generate Oauth token>'
ARCHES_PASSWORD = '<password for that user>'
ARCHES_CLIENT_ID = '<arches app client ID>'
ARCHES_CLIENT_SECRET = '<arches app oauth secret>'

# SECURITY WARNING: keep the secret key used in production secret!
SECRET_KEY = 'xxx'

## configuration for S3 static files and media storage
# AWS_ACCESS_KEY_ID = '<key>'
# AWS_SECRET_ACCESS_KEY = '<secret key>'

# AWS_STORAGE_BUCKET_NAME = '<bucket name>'
# AWS_S3_CUSTOM_DOMAIN = f'{AWS_STORAGE_BUCKET_NAME}.s3.amazonaws.com'

# AWS_S3_OBJECT_PARAMETERS = {
#     'CacheControl': 'max-age=86400',
# }

# AWS_IS_GZIPPED = True

# AWS_LOCATION = 'static'
# STATICFILES_STORAGE = 'storages.backends.s3boto3.S3Boto3Storage'
# STATIC_URL = f"https://{AWS_S3_CUSTOM_DOMAIN}/{AWS_LOCATION}/"
# MEDIA_URL = f"https://{AWS_S3_CUSTOM_DOMAIN}/media/"
# DEFAULT_FILE_STORAGE = 'herbridge.storage_backends.MediaStorage'

# MIDDLEWARE Copied from settings.py
MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

# Use Whitenoise for serving static files in the absence of S3...
MIDDLEWARE.extend([
    "whitenoise.middleware.WhiteNoiseMiddleware",
])

STATIC_URL = '/static/'
STATIC_ROOT = os.path.join(BASE_DIR, "frontend/static")

LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'console': {
            'format': '%(asctime)s %(name)-12s %(levelname)-8s %(message)s',
        },
    },
    'handlers': {
        'file': {
            'level': 'WARNING',  # DEBUG, INFO, WARNING, ERROR
            'class': 'logging.FileHandler',
            'filename': os.path.join(BASE_DIR, 'herbridge.log'),
            'formatter': 'console'
        },
        'console': {
            'level': 'DEBUG' if DEBUG else 'WARNING',
            'class': 'logging.StreamHandler',
            'formatter': 'console'
        }
    },
    'loggers': {
        'django': {
            'handlers': ['console'],
            'level': 'DEBUG',
            'propagate': True,
        },
    },
}
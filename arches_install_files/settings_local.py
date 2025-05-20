"""
settings_local.py - Local settings for local people

EAMENA v4 is based on Arches 7.3
https://github.com/archesproject/arches

This file is for settings that should be different on every
instance of EAMENA v4 and *must not* be committed into
a public repository such as Github.

Examples of settings in this file include passwords, encryption
keys and settings specific to this instance such as optimisation
settings or logging options.

"""

import os

try:
    from .settings_paths import *
except ImportError as e:
    try: 
        from settings_paths import *
    except ImportError as e:
        pass

ENABLE_HERBRIDGE_ENDPOINTS=True

ALLOWED_HOSTS = ['replace_me', 'localhost', '127.0.0.1']

DATABASES = {
    "default": {
        "ATOMIC_REQUESTS": False,
        "AUTOCOMMIT": True,
        "CONN_MAX_AGE": 0,
        "ENGINE": "django.contrib.gis.db.backends.postgis",
        "HOST": "localhost",
        "NAME": "eamena",
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

ELASTICSEARCH_HTTP_PORT = 9200  # this should be in increments of 200, eg: 9400, 9600, 9800
ELASTICSEARCH_HOSTS = [{"scheme": "http", "host": "localhost", "port": ELASTICSEARCH_HTTP_PORT}]
ELASTICSEARCH_CONNECTION_OPTIONS = {"timeout": 30}
ELASTICSEARCH_PREFIX = "eamena"

# a list of objects of the form below
# {
#     'module': dotted path to the Classname within a python module,
#     'name': name of the custom index  <-- follow ES index naming rules
# }
ELASTICSEARCH_CUSTOM_INDEXES = []
# [{
#     'module': 'my_project.search_indexes.sample_index.SampleIndex',
#     'name': 'my_new_custom_index',
#     'should_update_asynchronously': False
# }]

# We're not using Kibana, so this is nonsense
KIBANA_URL = ""
KIBANA_CONFIG_BASEPATH = "kibana"  # must match Kibana config.yml setting (server.basePath) but without the leading slash,
# also make sure to set server.rewriteBasePath: true

CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',
        'LOCATION': '127.0.0.1:11211',
    },
    'user_permission': {
        'BACKEND': 'django.core.cache.backends.db.DatabaseCache',
        'LOCATION': 'user_permission_cache',
    }
}

#Identify the usernames and duration (seconds) for which you want to cache the time wheel
SEARCH_EXPORT_LIMIT = 100000
SEARCH_EXPORT_IMMEDIATE_DOWNLOAD_THRESHOLD = 2000  # The maximum number of instances a user can download from search export without celery
SEARCH_EXPORT_IMMEDIATE_DOWNLOAD_THRESHOLD_HTML_FORMAT = 10

CACHE_BY_USER = {'anonymous': 3600 * 24}

CELERY_ACCEPT_CONTENT = ['json']
CELERY_RESULT_BACKEND = 'django-db' # Use 'django-cache' if you want to use your cache as your backend
CELERY_TASK_SERIALIZER = 'json'

CELERY_SEARCH_EXPORT_EXPIRES = 24 * 3600  # seconds
CELERY_SEARCH_EXPORT_CHECK = 3600  # seconds

CELERY_BEAT_SCHEDULE = {
    "delete-expired-search-export": {"task": "arches.app.tasks.delete_file", "schedule": CELERY_SEARCH_EXPORT_CHECK,},
    "notification": {"task": "arches.app.tasks.message", "schedule": CELERY_SEARCH_EXPORT_CHECK, "args": ("Celery Beat is Running",),},
}

# By setting RESTRICT_MEDIA_ACCESS to True, media file requests will be
# served by Django rather than your web server (e.g. Apache). This allows file requests to be checked against nodegroup permissions.
# However, this will adversely impact performace when serving large files or during periods of high traffic.
RESTRICT_MEDIA_ACCESS = False

RESTRICT_CELERY_EXPORT_FOR_ANONYMOUS_USER = True

CELERY_CHECK_ONLY_INSPECT_BROKER = False

TILESERVER_URL = ''

# This is the namespace to use for export of data (for RDF/XML for example)
# Ideally this should point to the url where you host your site
# Make sure to use a trailing slash
ARCHES_NAMESPACE_FOR_DATA_EXPORT = "http://127.0.0.1:8000/"

# SECURITY WARNING: keep the secret key used in production secret!
SECRET_KEY = 'xxx'

# SECURITY WARNING: don't run with debug turned on in production!
DEBUG = True

LOAD_DEFAULT_ONTOLOGY = False
LOAD_PACKAGE_ONTOLOGIES = True
FILE_TYPE_CHECKING = False

# Sets default max upload size to 15MB
DATA_UPLOAD_MAX_MEMORY_SIZE = 15728640

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
            'filename': os.path.join(APP_ROOT, 'arches.log'),
            'formatter': 'console'
        },
        'console': {
            'level': 'WARNING',
            'class': 'logging.StreamHandler',
            'formatter': 'console'
        }
    },
    'loggers': {
        'arches': {
            'handlers': ['file', 'console'],
            'level': 'WARNING',
            'propagate': True
        }
    }
}

BYPASS_UNIQUE_CONSTRAINT_TILE_VALIDATION = True # TODO: RESET THESE TO FALSE BEFORE GOING LIVE!!
BYPASS_REQUIRED_VALUE_TILE_VALIDATION = True
DEFAULT_RESOURCE_IMPORT_USER = {'username': 'admin', 'userid': 1}

# Hide nodes and cards in a report that have no data
HIDE_EMPTY_NODES_IN_REPORT = True


DATE_IMPORT_EXPORT_FORMAT = "%Y-%m-%d" # Custom date format for dates imported from and exported to csv

# This is used to indicate whether the data in the CSV and SHP exports should be
# ordered as seen in the resource cards or not.
EXPORT_DATA_FIELDS_IN_CARD_ORDER = False


#Identify the usernames and duration (seconds) for which you want to cache the time wheel
CACHE_BY_USER = {'anonymous': 3600 * 24}
TILE_CACHE_TIMEOUT = 600 #seconds
CLUSTER_DISTANCE_MAX = 20000 #meters
GRAPH_MODEL_CACHE_TIMEOUT = None

OAUTH_CLIENT_ID = '' #'9JCibwrWQ4hwuGn5fu2u1oRZSs9V6gK8Vu8hpRC4'


ENABLE_CAPTCHA = False
# RECAPTCHA_PUBLIC_KEY = ''
# RECAPTCHA_PRIVATE_KEY = ''
# RECAPTCHA_USE_SSL = False
NOCAPTCHA = True
# RECAPTCHA_PROXY = 'http://127.0.0.1:8000'
if DEBUG is True:
    SILENCED_SYSTEM_CHECKS = ["captcha.recaptcha_test_key_error"]

EMAIL_USE_TLS = True
EMAIL_HOST = 'smtp.gmail.com'
EMAIL_HOST_USER = 'replace_me@example.com'
EMAIL_FROM_ADDRESS = 'replace_me@example.com'
EMAIL_HOST_PASSWORD = 'replace_me'
EMAIL_PORT = 587
USER_SIGNUP_GROUP = 'Guest'

DEFAULT_FROM_EMAIL = EMAIL_HOST_USER

CELERY_BROKER_URL = 'amqp://arches:fake_password@127.0.0.1/arches'
CELERY_ACCEPT_CONTENT = ['json']
CELERY_RESULT_BACKEND = 'django-db' # Use 'django-cache' if you want to use your cache as your backend
CELERY_TASK_SERIALIZER = 'json'

CELERY_SEARCH_EXPORT_EXPIRES = 24 * 3600  # seconds
CELERY_SEARCH_EXPORT_CHECK = 3600  # seconds

CELERY_BEAT_SCHEDULE = {
    "delete-expired-search-export": {"task": "arches.app.tasks.delete_file", "schedule": CELERY_SEARCH_EXPORT_CHECK,},
    "notification": {"task": "arches.app.tasks.message", "schedule": CELERY_SEARCH_EXPORT_CHECK, "args": ("Celery Beat is Running",),},
}

# Set to True if you want to send celery tasks to the broker without being able to detect celery.
# This might be necessary if the worker pool is regulary fully active, with no idle workers, or if
# you need to run the celery task using solo pool (e.g. on Windows). You may need to provide another
# way of monitoring celery so you can detect the background task not being available.
CELERY_CHECK_ONLY_INSPECT_BROKER = False

CANTALOUPE_DIR = os.path.join(ROOT_DIR, "uploadedfiles")
CANTALOUPE_HTTP_ENDPOINT = "http://localhost:8182/"
# By setting RESTRICT_CELERY_EXPORT_FOR_ANONYMOUS_USER to True, if the user is attempting
# to export search results above the SEARCH_EXPORT_IMMEDIATE_DOWNLOAD_THRESHOLD
# value and is not signed in with a user account then the request will not be allowed.
RESTRICT_CELERY_EXPORT_FOR_ANONYMOUS_USER = False

CELERY_CHECK_ONLY_INSPECT_BROKER = False

TILESERVER_URL = ''

# This is the namespace to use for export of data (for RDF/XML for example)
# Ideally this should point to the url where you host your site
# Make sure to use a trailing slash

MOBILE_OAUTH_CLIENT_ID = ''  #'9JCibwrWQ4hwuGn5fu2u1oRZSs9V6gK8Vu8hpRC4'
MOBILE_DEFAULT_ONLINE_BASEMAP = {'default': 'mapbox://styles/mapbox/streets-v9'}

ENABLE_CAPTCHA = False
NOCAPTCHA = True


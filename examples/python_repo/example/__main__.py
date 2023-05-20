import os
import coflux

from . import repo

project_name = os.environ.get("COFLUX_PROJECT", "project_1")
environment_name = os.environ.get("COFLUX_ENVIRONMENT", "development")
host = os.environ.get("COFLUX_HOST", "localhost:7070")

coflux.init(project_name, environment_name, repo, "1", host)

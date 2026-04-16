"""Image Lifecycle backend configuration."""
import os

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./image-lifecycle.db")
SECRET_KEY = os.getenv("SECRET_KEY", "change-me-in-production")
SESSION_MAX_AGE = int(os.getenv("SESSION_MAX_AGE", "86400"))
SCRIPTS_DIR = os.getenv("SCRIPTS_DIR", "/home/cloudsigma/cloudsigma-image-lifecycle/scripts")
CS_API_BASE = os.getenv("CS_API_BASE", "https://dus.cloudsigma.com/api/v2")
CS_API_USER = os.getenv("CS_API_USER", "")
CS_API_PASS = os.getenv("CS_API_PASS", "")
INITIAL_OWNER_EMAIL = os.getenv("INITIAL_OWNER_EMAIL", "beloslava.spiridonova@cloudsigma.com")
INITIAL_OWNER_NAME = os.getenv("INITIAL_OWNER_NAME", "Beloslava Spiridonova")
LOGS_DIR = os.getenv("LOGS_DIR", "/tmp/image-lifecycle-logs")
VERSION = "1.0.0"

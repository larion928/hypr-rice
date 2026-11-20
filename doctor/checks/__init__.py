"""The checks, in report order. Each module has TITLE and detect(context) -> list of Finding."""
from . import boot, crashes, disk, journal, kernel, laptop, pacman, rice, services, system

CHECKS = (services, kernel, journal, crashes, pacman, disk, rice, system, laptop, boot)

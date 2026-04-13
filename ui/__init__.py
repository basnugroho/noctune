"""
NOC Tune UI Package

Contains the web-based UI components for NOC Tune.
"""

from .ttfb_test_ui import main as run_ttfb_ui, TTFBHandler
from .get_location import main as run_location

__all__ = ['run_ttfb_ui', 'run_location', 'TTFBHandler']

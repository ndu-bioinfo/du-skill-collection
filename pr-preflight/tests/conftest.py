import os
import sys

# Make the plugin's script importable.
sys.path.insert(
    0,
    os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "scripts",
    ),
)

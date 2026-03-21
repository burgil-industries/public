#!/usr/bin/env bash
exec < /dev/tty

echo "Linux version is under development. Please check back later for updates."
exit 0

echo "Bootstrapping installer..."

# 1. Check for Python
if ! command -v python3 >/dev/null 2>&1; then
    echo "Python 3 is required but not installed."
    echo "Opening Python website..."
    xdg-open https://www.python.org/downloads/ 2>/dev/null || open https://www.python.org/downloads/ 2>/dev/null || start https://www.python.org/downloads/
    exit 1
fi

# 2. Setup a temporary environment
TMP_DIR="/tmp/ali_setup_env"
mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

echo "Downloading UI components..."
# Create a virtual environment and install CustomTkinter silently
python3 -m venv venv
source venv/bin/activate
pip install customtkinter --quiet

# 3. Write the Python UI code on the fly
cat << 'EOF' > setup_gui.py
import customtkinter as ctk
import os
import sys

# Setup the dark mode window
ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("blue")

app = ctk.CTk()
app.geometry("540x400")
app.title("ALI 1.0.0 Setup")

# Title Label
title = ctk.CTkLabel(app, text="Welcome to ALI Setup", font=("Segoe UI", 24, "bold"))
title.pack(pady=20)

# Path Input
path_var = ctk.StringVar(value=os.path.expanduser("~/.local/ALI"))
path_entry = ctk.CTkEntry(app, textvariable=path_var, width=300)
path_entry.pack(pady=20)

def install():
    install_dir = path_var.get()
    # Your logic to write files goes here
    print(f"Installing to {install_dir}...")
    app.destroy()

# Install Button
btn = ctk.CTkButton(app, text="Install Now", command=install)
btn.pack(pady=20)

app.mainloop()
EOF

# 4. Run the GUI
echo "Launching Setup..."
python3 setup_gui.py

# 5. Cleanup
deactivate
rm -rf "$TMP_DIR"
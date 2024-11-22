#!/bin/bash

# Function to display messages
function info {
  echo -e "\033[1;34m[INFO]\033[0m $1"
}

function success {
  echo -e "\033[1;32m[SUCCESS]\033[0m $1"
}

function error {
  echo -e "\033[1;31m[ERROR]\033[0m $1"
}

# Function to check if nvm is installed and sourced
function check_nvm {
  if [ -s "$HOME/.nvm/nvm.sh" ]; then
    # Load nvm if it exists in the typical location
    source "$HOME/.nvm/nvm.sh"
  fi

  if command -v nvm >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Check if the script is running from the Anvil-OOD-Dashboard repository
REPO_URL="https://github.com/richtan/Anvil-OOD-Dashboard"
USE_CURRENT_DIR=false

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  REMOTE_URL=$(git config --get remote.origin.url)
  if [[ "$REMOTE_URL" == "$REPO_URL" || "$REMOTE_URL" == "git@github.com:richtan/Anvil-OOD-Dashboard.git" ]]; then
    USE_CURRENT_DIR=true
  fi
fi

if $USE_CURRENT_DIR; then
  DASHBOARD_DIR=$(pwd)
  FOLDER_NAME=$(basename "$DASHBOARD_DIR")
  info "Detected script is running from the Anvil-OOD-Dashboard repository. Using current directory: $DASHBOARD_DIR"
else
  # Define the base directory
  BASE_DIR="$HOME/ondemand/dev"

  # Prompt the user for the folder name within the base directory
  echo "The dashboard will be installed within the $BASE_DIR directory."
  read -p "Enter the folder name where you want to install the dashboard [default: dashboard]: " FOLDER_NAME

  # Use "dashboard" as the default folder name if the user didn't specify one
  FOLDER_NAME=${FOLDER_NAME:-dashboard}

  # Define the full installation directory path
  DASHBOARD_DIR="$BASE_DIR/$FOLDER_NAME"

  # Check if the repository folder already exists
  if [ -d "$DASHBOARD_DIR" ]; then
    read -p "The directory $DASHBOARD_DIR already exists. Do you want to overwrite it? (yes/no) [default: no]: " overwrite
    overwrite=${overwrite:-no}
    if [[ "$overwrite" == "yes" || "$overwrite" == "y" ]]; then
      rm -rf "$DASHBOARD_DIR"
      info "Existing directory $DASHBOARD_DIR removed."
    else
      success "Skipping cloning as the directory $DASHBOARD_DIR already exists."
      exit 0
    fi
  fi

  # Clone the repository
  info "Cloning the repository into $DASHBOARD_DIR..."
  
  # Prompt user to choose between HTTPS or SSH
  read -p "Do you want to clone using SSH? (yes/no): " use_ssh

  if [ "$use_ssh" == "yes" ]; then
    git clone git@github.com:richtan/Anvil-OOD-Dashboard.git "$DASHBOARD_DIR" >/dev/null 2>&1
  else
    git clone https://github.com/richtan/Anvil-OOD-Dashboard "$DASHBOARD_DIR" >/dev/null 2>&1
  fi

  if [ $? -eq 0 ]; then
    success "Repository cloned successfully into $DASHBOARD_DIR."
  else
    error "Failed to clone the repository. Please check your network connection or the repository URL."
    exit 1
  fi
fi

# Copy system apps from the other-apps directory
OTHER_APPS_DIR="$DASHBOARD_DIR/other-apps"
if [ -d "$OTHER_APPS_DIR" ]; then
  for APP_DIR in "$OTHER_APPS_DIR"/*; do
    if [ -d "$APP_DIR" ]; then
      APP_NAME=$(basename "$APP_DIR")
      DEST_DIR="$HOME/ondemand/dev/$APP_NAME"
      if [ ! -d "$DEST_DIR" ]; then
        info "Copying system app $APP_NAME to $DEST_DIR..."
        cp -r "$APP_DIR" "$DEST_DIR"
        if [ $? -eq 0 ]; then
          success "System app $APP_NAME copied to $DEST_DIR."
        else
          error "Failed to copy system app $APP_NAME to $DEST_DIR."
        fi
      else
        info "System app $APP_NAME already exists at $DEST_DIR. Skipping copy."
      fi
    fi
  done
else
  info "No other-apps directory found in the repository."
fi

cd "$DASHBOARD_DIR" >/dev/null 2>&1 || { error "Failed to navigate to the directory $DASHBOARD_DIR. Ensure the directory exists and has the correct permissions."; exit 1; }

# 2. Setup the dashboard config environment variables
info "Setting up environment variables..."
if [ -f ".env.local" ]; then
  success ".env.local already exists. Skipping environment setup."
else
  cp .env.local.example .env.local >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    success "Environment variables set up successfully. Please edit the .env.local file with your preferred values."
  else
    error "Failed to create .env.local. Please check if .env.local.example exists and you have the correct permissions."
    exit 1
  fi
fi

# 3. Install Ruby dependencies
info "Checking Ruby dependencies..."

# Install rbenv if not installed
if command -v rbenv >/dev/null; then
  success "rbenv is already installed."
else
  info "Installing rbenv... (ETA: 3-5 minutes)"
  curl -fsSL https://github.com/rbenv/rbenv-installer/raw/HEAD/bin/rbenv-installer | bash >/dev/null 2>&1
  source "$HOME/.bash_profile" >/dev/null 2>&1
  if command -v rbenv >/dev/null; then
    success "rbenv installed successfully."
  else
    error "Failed to install rbenv. Please ensure curl is installed and you have the necessary permissions."
    exit 1
  fi
fi

# Check if Ruby 2.7.8 is installed and set up
if rbenv versions | grep -q "2.7.8"; then
  success "Ruby 2.7.8 is already installed."
else
  info "Installing Ruby 2.7.8... (ETA: 1-2 minutes)"
  rbenv install 2.7.8 >/dev/null 2>&1
  rbenv local 2.7.8 >/dev/null 2>&1
  if ruby -v | grep "2.7.8" >/dev/null 2>&1; then
    success "Ruby 2.7.8 installed and activated."
  else
    error "Failed to install Ruby 2.7.8. Please check rbenv installation and ensure your system meets the Ruby requirements."
    exit 1
  fi
fi

# Install bundler if not installed
if gem list bundler -i --version 2.4.22 >/dev/null; then
  success "bundler 2.4.22 is already installed."
else
  info "Installing bundler... (ETA: 3-5 seconds)"
  gem install bundler -v 2.4.22 >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    error "Failed to install bundler. Please check your Ruby setup and ensure you have the necessary permissions."
    exit 1
  fi
fi

# Install required Ruby gems
if bundle check >/dev/null 2>&1; then
  success "All required Ruby gems are already installed."
else
  info "Installing required Ruby gems... (ETA: 10-20 seconds)"
  bundle install >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    success "Ruby dependencies installed successfully."
  else
    error "Failed to install Ruby dependencies. Please check the Gemfile for issues and ensure you have network access."
    exit 1
  fi
fi

# 4. Install NodeJS dependencies
info "Checking NodeJS dependencies..."

# Install nvm if not installed
if check_nvm; then
  success "nvm is already installed."
else
  info "Installing nvm... (ETA: 5-10 seconds)"
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash >/dev/null 2>&1
  source "$HOME/.bashrc" >/dev/null 2>&1
  if check_nvm; then
    success "nvm installed successfully."
  else
    error "Failed to install nvm. Please ensure curl is installed and you have the necessary permissions."
    exit 1
  fi
fi

# Check if NodeJS 10.17.0 is installed and set up
if nvm ls | grep -q "v10.17.0"; then
  success "NodeJS 10.17.0 is already installed."
else
  info "Installing NodeJS 10.17.0... (ETA: 10-15 seconds)"
  nvm install 10.17.0 >/dev/null 2>&1
  nvm use 10.17.0 >/dev/null 2>&1
  if node -v | grep "v10.17.0" >/dev/null 2>&1; then
    success "NodeJS 10.17.0 installed and activated."
  else
    error "Failed to install NodeJS 10.17.0. Please ensure nvm is functioning properly and you have network access."
    exit 1
  fi
fi

# Install yarn if not installed
if command -v yarn >/dev/null; then
  success "yarn is already installed."
else
  info "Installing yarn... (ETA: 3-5 seconds)"
  npm install yarn -g >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    error "Failed to install yarn. Please check your npm setup and network connection."
    exit 1
  fi
fi

# Install required NodeJS dependencies
if npm ls >/dev/null 2>&1; then
  success "All required NodeJS dependencies are already installed."
else
  info "Installing required NodeJS dependencies... (ETA: 5-10 seconds)"
  npm install >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    success "NodeJS dependencies installed successfully."
  else
    error "Failed to install NodeJS dependencies. Please check the package.json for issues and ensure you have network access."
    exit 1
  fi
fi

# 5. Compile the CSS/JS assets
info "Compiling CSS/JS assets... (ETA: 10-20 seconds)"
bin/recompile_js >/dev/null 2>&1

if [ $? -eq 0 ]; then
  success "CSS/JS assets compiled successfully."
else
  error "Failed to compile CSS/JS assets. Please check the script for errors and ensure all dependencies are installed correctly."
  exit 1
fi

# Success message with the access URL
success "Dashboard setup completed successfully!"
info "If you receive a message saying 'App has not been initialized or does not exist,' please click the 'Initialize App' button."

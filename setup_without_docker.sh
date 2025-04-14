#!/bin/bash

# Dify Source Code Setup Script
# This script sets up Dify from source code without Docker
# Requirements:
# - Python 3.12
# - Node.js v18+ and npm

set -e  # Exit on error

echo "===== Dify Source Code Setup Script ====="
echo "This script will set up Dify from source code without using Docker"

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check dependencies
echo "Checking dependencies..."

# Check Python version
if ! command_exists python3; then
  echo "Python 3 is not installed. Please install Python 3.12."
  exit 1
fi

PYTHON_VERSION=$(python3 --version | awk '{print $2}')
PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d. -f1)
PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d. -f2)

if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 12 ]); then
  echo "Python 3.12+ is required. Your version: $PYTHON_VERSION"
  echo "Install Python 3.12+ using pyenv:"
  echo "pyenv install 3.12"
  echo "pyenv global 3.12"
  exit 1
fi

# Check Poetry
if ! command_exists poetry; then
  echo "Poetry is not installed. Installing Poetry..."
  curl -sSL https://install.python-poetry.org | python3 -
  export PATH="$HOME/.local/bin:$PATH"
fi

# Check Node.js
if ! command_exists node; then
  echo "Node.js is not installed. Please install Node.js v18+."
  exit 1
fi

NODE_VERSION=$(node --version | cut -d 'v' -f2)
NODE_MAJOR=$(echo $NODE_VERSION | cut -d. -f1)

if [ "$NODE_MAJOR" -lt 18 ]; then
  echo "Node.js v18+ is required. Your version: $NODE_VERSION"
  exit 1
fi

# Check NPM
if ! command_exists npm; then
  echo "npm is not installed. Please install npm."
  exit 1
fi

# Install FFmpeg for OpenAI TTS
if ! command_exists ffmpeg; then
  echo "FFmpeg is not installed. Installing FFmpeg..."
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    brew install ffmpeg
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    if command_exists apt-get; then
      sudo apt-get update
      sudo apt-get install -y ffmpeg
    elif command_exists yum; then
      sudo yum install -y epel-release
      sudo yum install -y ffmpeg ffmpeg-devel
    fi
  fi
fi

# Install and setup PostgreSQL
install_postgresql() {
  echo "Installing PostgreSQL..."
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    brew install postgresql@14
    brew services start postgresql@14
    # Wait for PostgreSQL to start
    sleep 5
    # Create database and user
    createdb dify || echo "Database already exists"
    psql -c "CREATE USER dify WITH PASSWORD 'difyai123456';" || echo "User already exists"
    psql -c "GRANT ALL PRIVILEGES ON DATABASE dify TO dify;" || echo "Privileges already granted"
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    if command_exists apt-get; then
      # Debian/Ubuntu
      sudo apt-get update
      sudo apt-get install -y postgresql postgresql-contrib
      # Start PostgreSQL service
      sudo systemctl start postgresql
      sudo systemctl enable postgresql
      # Create database and user
      sudo -u postgres psql -c "CREATE DATABASE dify;" || echo "Database already exists"
      sudo -u postgres psql -c "CREATE USER dify WITH PASSWORD 'difyai123456';" || echo "User already exists"
      sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE dify TO dify;" || echo "Privileges already granted"
    elif command_exists yum; then
      # CentOS/RHEL/Fedora
      sudo yum install -y postgresql-server postgresql-contrib
      sudo postgresql-setup --initdb
      sudo systemctl start postgresql
      sudo systemctl enable postgresql
      # Create database and user
      sudo -u postgres psql -c "CREATE DATABASE dify;" || echo "Database already exists"
      sudo -u postgres psql -c "CREATE USER dify WITH PASSWORD 'difyai123456';" || echo "User already exists"
      sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE dify TO dify;" || echo "Privileges already granted"
    fi
  fi

  echo "PostgreSQL setup complete."
}

# Install and setup Redis
install_redis() {
  echo "Installing Redis..."
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    brew install redis
    brew services start redis
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    if command_exists apt-get; then
      # Debian/Ubuntu
      sudo apt-get update
      sudo apt-get install -y redis-server
      sudo systemctl start redis-server
      sudo systemctl enable redis-server
    elif command_exists yum; then
      # CentOS/RHEL/Fedora
      sudo yum install -y redis
      sudo systemctl start redis
      sudo systemctl enable redis
    fi
  fi

  # Set Redis password
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS Redis configuration
    REDIS_CONF="/usr/local/etc/redis.conf"
    # Set requirepass if not already set
    grep -q "^requirepass " $REDIS_CONF || echo "requirepass difyai123456" | sudo tee -a $REDIS_CONF
    brew services restart redis
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux Redis configuration
    REDIS_CONF="/etc/redis/redis.conf"
    # Set requirepass if not already set
    grep -q "^requirepass " $REDIS_CONF || echo "requirepass difyai123456" | sudo tee -a $REDIS_CONF
    sudo systemctl restart redis-server
  fi

  echo "Redis setup complete."
}

# Install and setup Qdrant as the vector database
install_qdrant() {
  echo "Installing Qdrant vector database..."
  mkdir -p $HOME/qdrant_storage
  
  if command_exists pip3; then
    # Install Qdrant via pip
    pip3 install qdrant-client
  fi

  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    brew install rust
    cargo install qdrant-cli
    # Run Qdrant in the background
    nohup qdrant --db-path $HOME/qdrant_storage > qdrant.log 2>&1 &
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    curl -L https://github.com/qdrant/qdrant/releases/download/v1.1.1/qdrant-v1.1.1-x86_64-unknown-linux-gnu.tar.gz -o qdrant.tar.gz
    tar -xzf qdrant.tar.gz
    mv qdrant-v1.1.1-x86_64-unknown-linux-gnu/qdrant $HOME/.local/bin/ || \
    sudo mv qdrant-v1.1.1-x86_64-unknown-linux-gnu/qdrant /usr/local/bin/
    rm -rf qdrant-v1.1.1-x86_64-unknown-linux-gnu qdrant.tar.gz
    # Run Qdrant in the background
    nohup qdrant --db-path $HOME/qdrant_storage > qdrant.log 2>&1 &
  fi
  
  echo "Waiting for Qdrant to start..."
  sleep 5
  QDRANT_PID=$!
  echo "Qdrant setup complete. PID: $QDRANT_PID"
}

# Install middleware services without Docker
echo "Setting up middleware services (PostgreSQL, Redis, Qdrant)..."
install_postgresql
install_redis
install_qdrant

# Set up API service
echo "Setting up API service..."
cd api

# Install libmagic on macOS if needed
if [[ "$OSTYPE" == "darwin"* ]]; then
  echo "Installing libmagic for macOS..."
  brew install libmagic
fi

# Copy environment variables
cp .env.example .env

# Update environment variables for local setup
cat > .env << EOL
# Common Variables
CONSOLE_API_URL=
CONSOLE_WEB_URL=
SERVICE_API_URL=
APP_API_URL=
APP_WEB_URL=
FILES_URL=

# Server Configuration
LOG_LEVEL=INFO
DEBUG=false
FLASK_DEBUG=false
SECRET_KEY=$(openssl rand -base64 42)
DEPLOY_ENV=DEVELOPMENT
EDITION=SELF_HOSTED
CHECK_UPDATE_URL=https://updates.dify.ai
OPENAI_API_BASE=https://api.openai.com/v1
MIGRATION_ENABLED=true
FILES_ACCESS_TIMEOUT=300
ACCESS_TOKEN_EXPIRE_MINUTES=60
REFRESH_TOKEN_EXPIRE_DAYS=30
APP_MAX_ACTIVE_REQUESTS=0
APP_MAX_EXECUTION_TIME=1200

# Database Configuration
DB_USERNAME=dify
DB_PASSWORD=difyai123456
DB_HOST=localhost
DB_PORT=5432
DB_DATABASE=dify
SQLALCHEMY_POOL_SIZE=30
SQLALCHEMY_POOL_RECYCLE=3600
SQLALCHEMY_ECHO=false

# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_USERNAME=
REDIS_PASSWORD=difyai123456
REDIS_USE_SSL=false
REDIS_DB=0

# Vector Store Configuration
VECTOR_STORE=qdrant
QDRANT_URL=http://localhost:6333
QDRANT_API_KEY=
EOL

# Install dependencies
echo "Installing API dependencies..."
poetry env use 3.12
poetry self add poetry-plugin-shell  # Add shell plugin if not already installed
poetry install

# Migrate database
echo "Migrating database to latest version..."
poetry run flask db upgrade

# Start API service in background
echo "Starting API service in background..."
poetry run flask run --host 0.0.0.0 --port=5001 --debug > api_service.log 2>&1 &
API_PID=$!
echo "API service started with PID: $API_PID"

# Start Worker service in background
echo "Starting Worker service in background..."
if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "linux-gnu"* ]]; then
  # macOS or Linux
  poetry run celery -A app.celery worker -P gevent -c 1 --loglevel INFO -Q dataset,generation,mail,ops_trace > worker_service.log 2>&1 &
else
  # Windows
  poetry run celery -A app.celery worker -P solo --without-gossip --without-mingle -Q dataset,generation,mail,ops_trace --loglevel INFO > worker_service.log 2>&1 &
fi
WORKER_PID=$!
echo "Worker service started with PID: $WORKER_PID"

cd ..

# Set up Web frontend
echo "Setting up Web frontend..."
cd web

# Copy environment variables
cp .env.example .env.local

# Update environment variables for local development
cat > .env.local << EOL
# For production release, change this to PRODUCTION
NEXT_PUBLIC_DEPLOY_ENV=DEVELOPMENT
# The deployment edition, SELF_HOSTED
NEXT_PUBLIC_EDITION=SELF_HOSTED
# The base URL of console application, refers to the Console base URL of WEB service if console domain is
# different from api or web app domain.
# example: http://cloud.dify.ai/console/api
NEXT_PUBLIC_API_PREFIX=http://localhost:5001/console/api
# The URL for Web APP, refers to the Web App base URL of WEB service if web app domain is different from
# console or api domain.
# example: http://udify.app/api
NEXT_PUBLIC_PUBLIC_API_PREFIX=http://localhost:5001/api
# SENTRY
NEXT_PUBLIC_SENTRY_DSN=
EOL

# Install dependencies
echo "Installing Web dependencies..."
npm install

# Build the frontend
echo "Building Web frontend..."
npm run build

# Start the Web service in background
echo "Starting Web service in background..."
npm run start > web_service.log 2>&1 &
WEB_PID=$!
echo "Web service started with PID: $WEB_PID"

cd ..

echo "===== Dify Setup Complete ====="
echo "Middleware services:"
echo "- PostgreSQL: running on localhost:5432"
echo "- Redis: running on localhost:6379"
echo "- Qdrant: running on localhost:6333"
echo ""
echo "API service running at: http://localhost:5001"
echo "Web interface running at: http://localhost:3000"
echo ""
echo "API and Worker logs can be found in the api directory:"
echo "- api_service.log"
echo "- worker_service.log"
echo ""
echo "Web service logs can be found in the web directory:"
echo "- web_service.log"
echo ""
echo "Use the web interface to complete the initial setup and create your first admin account."
echo ""
echo "Note: To stop the services, run the following commands:"
echo "kill $API_PID $WORKER_PID $QDRANT_PID $WEB_PID"
echo "sudo systemctl stop postgresql redis # (on Linux)"
echo "brew services stop postgresql redis # (on macOS)"
echo ""
echo "To manually start the services again:"
echo "1. PostgreSQL: sudo systemctl start postgresql (Linux) or brew services start postgresql (macOS)"
echo "2. Redis: sudo systemctl start redis (Linux) or brew services start redis (macOS)"
echo "3. Qdrant: qdrant --db-path $HOME/qdrant_storage"
echo "4. API Service: cd api && poetry run flask run --host 0.0.0.0 --port=5001 --debug"
echo "5. Worker Service: cd api && poetry run celery -A app.celery worker -P gevent -c 1 --loglevel INFO -Q dataset,generation,mail,ops_trace"
echo "6. Web Service: cd web && npm run start" 